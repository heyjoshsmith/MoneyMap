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
    static func performSync(modelContainer: ModelContainer) async throws -> BackgroundTransactionSyncResult {
        guard isBackgroundSyncEnabled else { return .skipped }

        let plaidContainer = try PlaidSyncContainerFactory.make()
        let plaidContext = ModelContext(plaidContainer)
        let mainContext = ModelContext(modelContainer)

        try await PlaidCloudSyncService.pull(context: plaidContext)
        let lastSyncAt = try plaidContext.fetch(FetchDescriptor<PlaidConnection>())
            .compactMap(\.lastSyncAt)
            .max()

        let readyItems = try plaidContext.fetch(FetchDescriptor<PlaidTransactionReviewItem>())
            .filter { $0.status == .ready }
        let bills = try mainContext.fetch(FetchDescriptor<Bill>())
        let importSummary = try PlaidLocalSyncImporter.importReviewedItems(
            readyItems,
            context: mainContext,
            bills: bills
        )
        let settlementSummary = try ExtraMoneyPlanSettlementService.settlePendingPayments(context: mainContext)

        if importSummary.importedCount > 0 || settlementSummary.paidCardCount > 0 {
            let transactions = try mainContext.fetch(FetchDescriptor<Transaction>())
            _ = BillPaymentMatcher.refreshStatuses(for: bills, transactions: transactions)
            try mainContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            WidgetCenter.shared.reloadAllTimelines()
        }

        try plaidContext.save()
        try await PlaidCloudSyncService.push(context: plaidContext)

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
