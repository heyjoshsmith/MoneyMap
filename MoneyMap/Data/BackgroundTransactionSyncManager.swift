//
//  BackgroundTransactionSyncManager.swift
//  MoneyMap
//
//  Created by Codex on 8/12/26.
//

import Foundation
import SwiftData
import WidgetKit

#if os(iOS)
import BackgroundTasks
#endif

struct BackgroundTransactionSyncResult: Sendable {
    let importedCount: Int
    let skippedCount: Int
    let paidCardCount: Int
    let requestedMacRefresh: Bool

    static let skipped = BackgroundTransactionSyncResult(
        importedCount: 0,
        skippedCount: 0,
        paidCardCount: 0,
        requestedMacRefresh: false
    )
}

@MainActor
enum BackgroundTransactionSyncManager {
    static let backgroundSyncEnabledKey = "backgroundTransactionSyncEnabled"
    static let taskIdentifier = "com.heyjoshsmith.MoneyMap.transaction-refresh"

    private static let refreshInterval: TimeInterval = 30 * 60

    private static var isSyncing = false
    private static var lastForegroundCheck: Date?

    static func refreshOnActivation(modelContainer: ModelContainer) async {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              isBackgroundSyncEnabled, !isSyncing,
              lastForegroundCheck.map({ Date().timeIntervalSince($0) >= 5 * 60 }) ?? true else { return }
        lastForegroundCheck = .now
        do {
            _ = try await performSync(modelContainer: modelContainer, mainContext: modelContainer.mainContext)
        } catch is CancellationError {
            lastForegroundCheck = nil
        } catch {
            MoneyMapDiagnostics.record("bankSync.foreground.failed", error: error)
        }
    }

    static var isBackgroundSyncEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: backgroundSyncEnabledKey) != nil else { return true }
        return defaults.bool(forKey: backgroundSyncEnabledKey)
    }

    static func register(modelContainer: ModelContainer) {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                handle(appRefreshTask, modelContainer: modelContainer)
            }
        }
        #endif
    }

    static func setBackgroundSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: backgroundSyncEnabledKey)
        if enabled {
            scheduleAppRefresh()
        } else {
            cancelAppRefresh()
        }
    }

    static func scheduleAppRefresh() {
        #if os(iOS)
        guard isBackgroundSyncEnabled else {
            cancelAppRefresh()
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Background transaction sync scheduling error: \(error.localizedDescription)")
        }
        #endif
    }

    static func cancelAppRefresh() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        #endif
    }

    @discardableResult
    static func performSync(modelContainer: ModelContainer, mainContext suppliedContext: ModelContext? = nil) async throws -> BackgroundTransactionSyncResult {
        guard isBackgroundSyncEnabled, !isSyncing else { return .skipped }
        isSyncing = true
        defer { isSyncing = false }

        let plaidContainer = try PlaidSyncContainerFactory.make()
        let plaidContext = ModelContext(plaidContainer)
        let mainContext = suppliedContext ?? ModelContext(modelContainer)

        try await PlaidCloudSyncService.pull(context: plaidContext)
        try Task.checkCancellation()
        try LinkedCardRefreshService.reconcile(snapshotContext: plaidContext, context: mainContext)
        let lastSyncAt = try plaidContext.fetch(FetchDescriptor<PlaidConnection>())
            .compactMap(\.lastSyncAt)
            .max()

        let readyItems = try plaidContext.fetch(FetchDescriptor<PlaidTransactionReviewItem>())
        let bills = try mainContext.fetch(FetchDescriptor<Bill>())
        let importSummary = try PlaidLocalSyncImporter.importReviewedItems(
            readyItems,
            context: mainContext,
            bills: bills
        )
        let settlementSummary = try ExtraMoneyPlanSettlementService.settlePendingPayments(context: mainContext)

        if importSummary.importedCount > 0 || importSummary.updatedCount > 0 || importSummary.removedCount > 0 || settlementSummary.paidCardCount > 0 {
            let transactions = try mainContext.fetch(FetchDescriptor<Transaction>())
            _ = BillPaymentMatcher.refreshStatuses(for: bills, transactions: transactions)
            try mainContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            WidgetCenter.shared.reloadAllTimelines()
        }

        try plaidContext.save()
        try await PlaidCloudSyncService.push(context: plaidContext)

        // Counts and timestamps only, for diagnosing delivery without exposing bank identities or amounts.
        let bankAccounts = try plaidContext.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        let comparableCards = bills.compactMap { bill -> (Bill, PlaidAccountSnapshot)? in
            guard bill.category == .creditCard, !bill.plaidUnavailable,
                  let account = bankAccounts.first(where: { $0.accountID == bill.plaidAccountID }),
                  account.currentBalance != nil,
                  account.currencyCode == nil || account.currencyCode?.uppercased() == "USD" else { return nil }
            return (bill, account)
        }
        let matchingCards = comparableCards.filter { bill, account in
            bill.currentCreditCardDetails?.cardBalance == account.currentBalance
                && bill.plaidUpdatedAt == account.updatedAt
        }.count
        let cardsWithBankStatus = bills.filter { $0.bankReportedPaymentStatus != nil }
        let matchingBankStatuses = cardsWithBankStatus.filter { $0.status == $0.bankReportedPaymentStatus }.count
        let enrichedTransactions = try mainContext.fetchCount(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.plaidEnrichmentJSON != nil }
        ))
        let report: [String: Any] = ["receivedAt": Date().timeIntervalSince1970,
            "macSyncAt": lastSyncAt?.timeIntervalSince1970 ?? 0, "accounts": bankAccounts.count,
            "linkedCardsWithBalance": comparableCards.count, "linkedBalancesMatch": matchingCards,
            "linkedCardsWithBankStatus": cardsWithBankStatus.count, "linkedBankStatusesMatch": matchingBankStatuses,
            "enrichedTransactions": enrichedTransactions, "imported": importSummary.importedCount,
            "updated": importSummary.updatedCount, "removed": importSummary.removedCount]
        if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            do {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: report, options: .sortedKeys)
                    .write(to: cache.appendingPathComponent("BankSyncStatus.json"), options: .atomic)
            } catch { MoneyMapDiagnostics.record("bankSync.diagnostics.failed", error: error) }
        }
        let requestedMacRefresh = try await requestMacRefreshIfNeeded(lastSyncAt: lastSyncAt)
        return BackgroundTransactionSyncResult(
            importedCount: importSummary.importedCount,
            skippedCount: importSummary.skippedCount,
            paidCardCount: settlementSummary.paidCardCount,
            requestedMacRefresh: requestedMacRefresh
        )
    }

    private static func requestMacRefreshIfNeeded(lastSyncAt: Date?) async throws -> Bool {
        guard PlaidMacRefreshRequestPolicy().shouldRequestMacRefresh(lastSyncAt: lastSyncAt) else {
            return false
        }

        if let command = try await PlaidCloudSyncService.latestMacRefreshCommand() {
            switch command.state {
            case .pending, .running:
                return false
            case .completed, .failed:
                break
            }
        }

        _ = try await PlaidCloudSyncService.requestMacRefresh(source: "iPhone Background")
        return true
    }

    #if os(iOS)
    private static func handle(_ task: BGAppRefreshTask, modelContainer: ModelContainer) {
        scheduleAppRefresh()

        let syncTask = Task { @MainActor in
            do {
                _ = try await performSync(modelContainer: modelContainer)
                task.setTaskCompleted(success: true)
            } catch {
                print("Background transaction sync error: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }
    #endif
}
