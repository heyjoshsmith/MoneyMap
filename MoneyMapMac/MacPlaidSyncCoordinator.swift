//
//  MacPlaidSyncCoordinator.swift
//  MoneyMapMac
//
//  Created by Codex on 7/6/26.
//

import AppKit
import Foundation
import SwiftData

@MainActor
final class MacPlaidSyncCoordinator: ObservableObject {
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var pendingLinkSession: PlaidPendingLinkSession?

    private let credentialStore = PlaidCredentialStore()
    private let defaults = UserDefaults.standard
    private let pendingLinkSessionKey = "plaid.pendingHostedLinkSession"
    private let clientUserIDKey = "plaid.clientUserID"
    private let handledMacRefreshRequestIDKey = "plaid.handledMacRefreshRequestID"

    init() {
        if let savedSession = Self.loadPendingLinkSession(defaults: defaults, key: pendingLinkSessionKey),
           !savedSession.isExpired {
            pendingLinkSession = savedSession
        } else {
            pendingLinkSession = nil
            defaults.removeObject(forKey: pendingLinkSessionKey)
        }
    }

    func validateCredentials() async {
        await run {
            let credentials = try self.requireCredentials()
            try await MacPlaidAPIClient(credentials: credentials).validateCredentials()
            self.statusMessage = "Plaid credentials are valid."
        }
    }

    func startHostedLinkConnection() async {
        await run {
            let credentials = try self.requireCredentials()
            let session = try await MacPlaidAPIClient(credentials: credentials).createHostedLinkSession(
                clientUserID: self.clientUserID()
            )
            let pendingSession = PlaidPendingLinkSession(
                linkToken: session.linkToken,
                hostedLinkURL: session.hostedLinkURL,
                expiration: session.expiration,
                requestID: session.requestID,
                mode: .addItem,
                itemID: nil,
                createdAt: .now
            )
            self.savePendingLinkSession(pendingSession)
            NSWorkspace.shared.open(session.hostedLinkURL)
            self.statusMessage = "Plaid Link opened in your browser. After you finish bank login, return here and choose Finish Bank Connection."
        }
    }

    func startReconnect(itemID: String) async {
        await run {
            let credentials = try self.requireCredentials()
            guard let accessToken = try self.credentialStore.accessToken(for: itemID) else {
                throw PlaidMacSyncError.missingAccessToken
            }
            let session = try await MacPlaidAPIClient(credentials: credentials).createHostedLinkSession(
                clientUserID: self.clientUserID(),
                accessToken: accessToken
            )
            let pendingSession = PlaidPendingLinkSession(
                linkToken: session.linkToken,
                hostedLinkURL: session.hostedLinkURL,
                expiration: session.expiration,
                requestID: session.requestID,
                mode: .updateItem,
                itemID: itemID,
                createdAt: .now
            )
            self.savePendingLinkSession(pendingSession)
            NSWorkspace.shared.open(session.hostedLinkURL)
            self.statusMessage = "Plaid reconnect opened in your browser. Finish there, then return here and choose Finish Bank Connection."
        }
    }

    func openPendingLinkSession() {
        guard let pendingLinkSession else {
            statusMessage = nil
            errorMessage = PlaidMacSyncError.noPendingLinkSession.localizedDescription
            return
        }
        NSWorkspace.shared.open(pendingLinkSession.hostedLinkURL)
        statusMessage = "Plaid Link opened again in your browser."
        errorMessage = nil
    }

    func cancelPendingLinkSession() {
        clearPendingLinkSession()
        statusMessage = "Bank connection canceled. Start a new bank connection when you are ready."
        errorMessage = nil
    }

    func finishHostedLinkConnection(context: ModelContext) async {
        await run {
            guard let pendingSession = self.pendingLinkSession else {
                throw PlaidMacSyncError.noPendingLinkSession
            }

            let credentials = try self.requireCredentials()
            let client = MacPlaidAPIClient(credentials: credentials)
            let linkStatus = try await client.linkTokenStatus(linkToken: pendingSession.linkToken)
            let publicTokens = NSOrderedSet(array: linkStatus.publicTokens).compactMap { $0 as? String }

            if publicTokens.isEmpty {
                if linkStatus.finishedWithoutPublicToken {
                    self.clearPendingLinkSession()
                    throw PlaidMacSyncError.linkFinishedWithoutPublicToken(linkStatus.userFacingStatusMessage)
                }

                if pendingSession.mode == .updateItem, let itemID = pendingSession.itemID, let accessToken = try self.credentialStore.accessToken(for: itemID) {
                    let summary = try await self.sync(itemID: itemID, accessToken: accessToken, client: client, context: context)
                    try await PlaidCloudSyncService.push(context: context)
                    self.clearPendingLinkSession()
                    self.statusMessage = summary.userMessage(prefix: "Reconnect finished")
                    return
                }

                self.statusMessage = "Plaid Link is not finished yet. Complete the bank login in your browser, then choose Finish Bank Connection again."
                return
            }

            var summaries: [PlaidTransactionSyncSummary] = []
            for publicToken in publicTokens {
                let itemCredentials = try await client.exchangePublicToken(publicToken)
                try self.credentialStore.saveAccessToken(itemCredentials.accessToken, itemID: itemCredentials.itemID)
                let summary = try await self.sync(itemID: itemCredentials.itemID, accessToken: itemCredentials.accessToken, client: client, context: context)
                summaries.append(summary)
            }

            try await PlaidCloudSyncService.push(context: context)
            self.clearPendingLinkSession()
            self.statusMessage = Self.finishedLinkMessage(itemCount: publicTokens.count, summaries: summaries)
        }
    }

    func createSandboxConnection(context: ModelContext) async {
        await run {
            let credentials = try self.requireCredentials()
            let client = MacPlaidAPIClient(credentials: credentials)
            let itemCredentials = try await client.createSandboxItem()
            try self.credentialStore.saveAccessToken(itemCredentials.accessToken, itemID: itemCredentials.itemID)
            let transactionSummary = try await self.sync(itemID: itemCredentials.itemID, accessToken: itemCredentials.accessToken, client: client, context: context)
            try await PlaidCloudSyncService.push(context: context)
            self.statusMessage = transactionSummary.userMessage(prefix: "Created a Plaid Sandbox connection")
        }
    }

    func syncAll(context: ModelContext) async {
        await run {
            self.statusMessage = try await self.performSyncAll(context: context)
        }
    }

    func runAutomaticRefreshLoop(
        context: ModelContext,
        automaticRefreshEnabled: Bool,
        refreshIntervalMinutes: Int
    ) async {
        let interval = TimeInterval(max(refreshIntervalMinutes, 15) * 60)
        let pollInterval: UInt64 = 60
        var nextAutomaticRefresh = Date().addingTimeInterval(interval)

        while !Task.isCancelled {
            let didHandleCommand = await handlePendingMacRefreshCommand(context: context)
            if didHandleCommand {
                nextAutomaticRefresh = Date().addingTimeInterval(interval)
            }

            if automaticRefreshEnabled, Date() >= nextAutomaticRefresh {
                await syncAutomatically(context: context)
                nextAutomaticRefresh = Date().addingTimeInterval(interval)
            }

            try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000)
        }
    }

    func removeConnection(itemID: String, context: ModelContext) async {
        await run {
            try self.credentialStore.deleteAccessToken(for: itemID)
            self.defaults.removeObject(forKey: self.cursorDefaultsKey(itemID: itemID))

            let connections = try context.fetch(FetchDescriptor<PlaidConnection>())
            for connection in connections where connection.itemID == itemID {
                context.delete(connection)
            }

            let accounts = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
            for account in accounts where account.itemID == itemID {
                context.delete(account)
            }

            let reviewItems = try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>())
            for reviewItem in reviewItems where reviewItem.plaidItemID == itemID {
                context.delete(reviewItem)
            }

            let suggestions = try context.fetch(FetchDescriptor<PlaidSuggestion>())
            for suggestion in suggestions where suggestion.plaidItemID == itemID {
                context.delete(suggestion)
            }

            try context.save()
            try await PlaidCloudSyncService.push(context: context)
            self.statusMessage = "Bank removed from MoneyMap. Its local snapshots and Mac Keychain token were deleted."
        }
    }

    private func sync(itemID: String, accessToken: String, client: MacPlaidAPIClient, context: ModelContext) async throws -> PlaidTransactionSyncSummary {
        let item = try await client.item(accessToken: accessToken)
        let institution: PlaidInstitutionDTO?
        if let institutionID = item.institutionID {
            institution = try await client.institution(id: institutionID)
        } else {
            institution = nil
        }
        let accounts = try await client.accounts(accessToken: accessToken)
        let liabilities = try? await client.liabilities(accessToken: accessToken)
        try upsertConnection(item: item, institution: institution, context: context)
        try upsertAccounts(accounts, itemID: itemID, institutionName: institution?.name, context: context)
        try upsertSuggestions(accounts: accounts, itemID: itemID, liabilities: liabilities, context: context)
        let transactionSummary = try await syncTransactions(itemID: itemID, accessToken: accessToken, client: client, context: context)
        try context.save()
        return transactionSummary
    }

    private func performSyncAll(context: ModelContext) async throws -> String {
        let credentials = try requireCredentials()
        let client = MacPlaidAPIClient(credentials: credentials)
        let connections = try context.fetch(FetchDescriptor<PlaidConnection>())

        guard !connections.isEmpty else {
            throw PlaidMacSyncError.noConnections
        }

        var transactionSummaries: [PlaidTransactionSyncSummary] = []
        for connection in connections {
            guard let accessToken = try credentialStore.accessToken(for: connection.itemID) else {
                connection.status = "needs_credentials"
                connection.errorMessage = "Access token is missing from this Mac's Keychain."
                continue
            }
            do {
                let summary = try await sync(itemID: connection.itemID, accessToken: accessToken, client: client, context: context)
                transactionSummaries.append(summary)
            } catch {
                connection.status = "needs_attention"
                connection.errorMessage = error.localizedDescription
                connection.updatedAt = .now
            }
        }

        try context.save()
        try await PlaidCloudSyncService.push(context: context)
        return Self.syncAllMessage(transactionSummaries)
    }

    private func syncAutomatically(context: ModelContext) async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        defer { isWorking = false }

        do {
            let message = try await performSyncAll(context: context)
            statusMessage = "Automatic refresh finished. \(message)"
        } catch PlaidMacSyncError.missingCredentials, PlaidMacSyncError.noConnections {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func handlePendingMacRefreshCommand(context: ModelContext) async -> Bool {
        guard !isWorking else { return false }

        do {
            guard let command = try await PlaidCloudSyncService.latestMacRefreshCommand(),
                  command.state == .pending,
                  defaults.string(forKey: handledMacRefreshRequestIDKey) != command.requestID else {
                return false
            }

            isWorking = true
            statusMessage = "iPhone requested a bank refresh."
            errorMessage = nil
            defer { isWorking = false }

            do {
                try await PlaidCloudSyncService.updateMacRefreshCommand(
                    requestID: command.requestID,
                    state: .running,
                    message: "MoneyMap for Mac is refreshing bank data.",
                    handledBy: Host.current().localizedName
                )
                let message = try await performSyncAll(context: context)
                try await PlaidCloudSyncService.updateMacRefreshCommand(
                    requestID: command.requestID,
                    state: .completed,
                    message: message,
                    handledBy: Host.current().localizedName
                )
                defaults.set(command.requestID, forKey: handledMacRefreshRequestIDKey)
                statusMessage = "Synced from iPhone request. \(message)"
                return true
            } catch {
                try? await PlaidCloudSyncService.updateMacRefreshCommand(
                    requestID: command.requestID,
                    state: .failed,
                    message: error.localizedDescription,
                    handledBy: Host.current().localizedName
                )
                defaults.set(command.requestID, forKey: handledMacRefreshRequestIDKey)
                errorMessage = error.localizedDescription
                return true
            }
        } catch {
            return false
        }
    }

    private func upsertConnection(item: PlaidItemDTO, institution: PlaidInstitutionDTO?, context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidConnection>())
        let connection = existing.first(where: { $0.itemID == item.itemID }) ?? PlaidConnection(itemID: item.itemID)
        connection.institutionID = item.institutionID
        connection.institutionName = institution?.name
        connection.status = "active"
        connection.errorMessage = nil
        connection.lastSyncAt = .now
        connection.updatedAt = .now

        if !existing.contains(where: { $0 === connection }) {
            context.insert(connection)
        }
    }

    private func upsertAccounts(
        _ accounts: [PlaidAccountDTO],
        itemID: String,
        institutionName: String?,
        context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        let accountsByID = Dictionary(existing.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })

        for dto in accounts {
            let snapshot = accountsByID[dto.accountID] ?? PlaidAccountSnapshot(
                accountID: dto.accountID,
                itemID: itemID,
                accountName: dto.name,
                type: dto.type
            )
            snapshot.itemID = itemID
            snapshot.institutionName = institutionName
            snapshot.accountName = dto.name
            snapshot.officialName = dto.officialName
            snapshot.mask = dto.mask
            snapshot.type = dto.type
            snapshot.subtype = dto.subtype
            snapshot.currentBalance = dto.balances.current
            snapshot.availableBalance = dto.balances.available
            snapshot.currencyCode = dto.balances.isoCurrencyCode
            snapshot.updatedAt = .now

            if accountsByID[dto.accountID] == nil {
                context.insert(snapshot)
            }
        }
    }

    private func upsertSuggestions(
        accounts: [PlaidAccountDTO],
        itemID: String,
        liabilities: PlaidLiabilitiesResponse?,
        context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidSuggestion>())
        let suggestionsByKey = Dictionary(existing.map { ("\($0.kindRaw):\($0.plaidAccountID)", $0) }, uniquingKeysWith: { first, _ in first })
        let creditLiabilities = Dictionary((liabilities?.liabilities.credit ?? []).map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })

        for account in accounts {
            let kind: PlaidSuggestionKind = account.type == "credit" ? .creditCardBill : .paymentMethod
            let suggestion = suggestionsByKey["\(kind.rawValue):\(account.accountID)"] ?? PlaidSuggestion(
                kind: kind,
                plaidAccountID: account.accountID,
                plaidItemID: itemID,
                title: account.name
            )

            suggestion.kind = kind
            suggestion.plaidItemID = itemID
            suggestion.title = account.name
            suggestion.amount = creditLiabilities[account.accountID]?.lastStatementBalance ?? account.balances.current
            suggestion.dueDate = PlaidMacDateParsing.day(creditLiabilities[account.accountID]?.nextPaymentDueDate)
            suggestion.detail = account.mask.map { "Ending \($0)" }
            suggestion.updatedAt = .now

            if suggestionsByKey["\(kind.rawValue):\(account.accountID)"] == nil {
                context.insert(suggestion)
            }
        }
    }

    private func syncTransactions(
        itemID: String,
        accessToken: String,
        client: MacPlaidAPIClient,
        context: ModelContext
    ) async throws -> PlaidTransactionSyncSummary {
        let startingCursor = storedCursor(itemID: itemID)
        let maxPaginationRestarts = 3
        var restartCount = 0

        while true {
            do {
                let batch = try await fetchTransactionSyncBatch(
                    accessToken: accessToken,
                    startingCursor: startingCursor,
                    client: client
                )
                try applyTransactionSyncBatch(batch, itemID: itemID, context: context)

                if let cursor = batch.nextCursor, !cursor.isEmpty {
                    defaults.set(cursor, forKey: cursorDefaultsKey(itemID: itemID))
                }

                return PlaidTransactionSyncSummary(
                    pageCount: batch.pageCount,
                    addedCount: batch.added.count,
                    modifiedCount: batch.modified.count,
                    removedCount: batch.removed.count,
                    nextCursor: batch.nextCursor,
                    restartCount: restartCount
                )
            } catch let error as PlaidAPIError where error.isTransactionsSyncMutationDuringPagination && restartCount < maxPaginationRestarts {
                restartCount += 1
                continue
            } catch let error as PlaidAPIError where error.isTransactionsSyncMutationDuringPagination {
                throw PlaidMacSyncError.transactionsChangedDuringPagination
            }
        }
    }

    private func fetchTransactionSyncBatch(
        accessToken: String,
        startingCursor: String?,
        client: MacPlaidAPIClient
    ) async throws -> PlaidTransactionSyncBatch {
        var cursor = startingCursor
        var hasMore = true
        var pageCount = 0
        var added: [PlaidTransactionDTO] = []
        var modified: [PlaidTransactionDTO] = []
        var removed: [PlaidRemovedTransactionDTO] = []

        while hasMore {
            let response = try await client.transactions(accessToken: accessToken, cursor: cursor)
            pageCount += 1
            added.append(contentsOf: response.added)
            modified.append(contentsOf: response.modified)
            removed.append(contentsOf: response.removed)
            cursor = response.nextCursor
            hasMore = response.hasMore
        }

        return PlaidTransactionSyncBatch(
            pageCount: pageCount,
            added: added,
            modified: modified,
            removed: removed,
            nextCursor: cursor
        )
    }

    private func applyTransactionSyncBatch(
        _ batch: PlaidTransactionSyncBatch,
        itemID: String,
        context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>())
        var reviewItemsByID = Dictionary(existing.map { ($0.plaidTransactionID, $0) }, uniquingKeysWith: { first, _ in first })

        for transaction in batch.added + batch.modified {
            let reviewItem = reviewItemsByID[transaction.transactionID] ?? PlaidTransactionReviewItem(
                plaidTransactionID: transaction.transactionID,
                plaidAccountID: transaction.accountID,
                plaidItemID: itemID,
                name: transaction.name,
                amount: transaction.amount
            )
            reviewItem.plaidAccountID = transaction.accountID
            reviewItem.plaidItemID = itemID
            reviewItem.name = transaction.name
            reviewItem.merchantName = transaction.merchantName
            reviewItem.category = transaction.category?.joined(separator: " / ")
            reviewItem.date = PlaidMacDateParsing.day(transaction.date)
            reviewItem.authorizedDate = PlaidMacDateParsing.day(transaction.authorizedDate)
            reviewItem.amount = transaction.amount
            reviewItem.currencyCode = transaction.isoCurrencyCode
            reviewItem.pending = transaction.pending
            reviewItem.pendingTransactionID = transaction.pendingTransactionID
            reviewItem.updatedAt = .now

            if reviewItemsByID[transaction.transactionID] == nil {
                context.insert(reviewItem)
                reviewItemsByID[transaction.transactionID] = reviewItem
            }
        }

        for removed in batch.removed {
            if let reviewItem = reviewItemsByID[removed.transactionID], reviewItem.status == .ready {
                reviewItem.status = .skipped
            }
        }
    }

    private func requireCredentials() throws -> PlaidStoredCredentials {
        guard let credentials = try credentialStore.loadCredentials() else {
            throw PlaidMacSyncError.missingCredentials
        }
        return credentials
    }

    private func cursorDefaultsKey(itemID: String) -> String {
        "plaid.transactions.cursor.\(itemID)"
    }

    private func storedCursor(itemID: String) -> String? {
        let value = defaults.string(forKey: cursorDefaultsKey(itemID: itemID))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clientUserID() -> String {
        if let existing = defaults.string(forKey: clientUserIDKey), !existing.isEmpty {
            return existing
        }
        let value = "moneymap-\(UUID().uuidString)"
        defaults.set(value, forKey: clientUserIDKey)
        return value
    }

    private func savePendingLinkSession(_ session: PlaidPendingLinkSession) {
        pendingLinkSession = session
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: pendingLinkSessionKey)
        }
    }

    private func clearPendingLinkSession() {
        pendingLinkSession = nil
        defaults.removeObject(forKey: pendingLinkSessionKey)
    }

    private static func loadPendingLinkSession(defaults: UserDefaults, key: String) -> PlaidPendingLinkSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlaidPendingLinkSession.self, from: data)
    }

    private static func syncAllMessage(_ summaries: [PlaidTransactionSyncSummary]) -> String {
        let addedCount = summaries.reduce(0) { $0 + $1.addedCount }
        if summaries.isEmpty {
            return "Sync finished with no transaction batches. Check connection diagnostics for any bank that needs attention."
        }
        if addedCount > 0 {
            return "Bank data synced. Added \(addedCount) transactions for review."
        }
        if summaries.contains(where: \.isWaitingForInitialTransactions) {
            return "Accounts and suggestions are ready. Plaid has not returned transaction history yet; click Sync Now again in a minute."
        }
        return "Bank data synced. No new transactions were returned."
    }

    private static func finishedLinkMessage(itemCount: Int, summaries: [PlaidTransactionSyncSummary]) -> String {
        let addedCount = summaries.reduce(0) { $0 + $1.addedCount }
        if addedCount > 0 {
            return "Connected \(itemCount) bank item\(itemCount == 1 ? "" : "s"). Added \(addedCount) transactions for review."
        }
        if summaries.contains(where: \.isWaitingForInitialTransactions) {
            return "Connected \(itemCount) bank item\(itemCount == 1 ? "" : "s"). Accounts are ready; Plaid may need a minute before transaction history appears."
        }
        return "Connected \(itemCount) bank item\(itemCount == 1 ? "" : "s"). Sync completed."
    }
}

struct PlaidPendingLinkSession: Codable, Identifiable {
    var linkToken: String
    var hostedLinkURL: URL
    var expiration: Date?
    var requestID: String?
    var mode: PlaidPendingLinkMode
    var itemID: String?
    var createdAt: Date

    var id: String { linkToken }

    var isExpired: Bool {
        guard let expiration else { return false }
        return expiration < .now
    }
}

enum PlaidPendingLinkMode: String, Codable {
    case addItem
    case updateItem
}

struct PlaidTransactionSyncSummary {
    var pageCount: Int
    var addedCount: Int
    var modifiedCount: Int
    var removedCount: Int
    var nextCursor: String?
    var restartCount: Int

    var totalChanges: Int {
        addedCount + modifiedCount + removedCount
    }

    var isWaitingForInitialTransactions: Bool {
        totalChanges == 0 && (nextCursor?.isEmpty ?? true)
    }

    func userMessage(prefix: String) -> String {
        let retryDetail = restartCount > 0 ? " Restarted Plaid pagination \(restartCount) time\(restartCount == 1 ? "" : "s") while the bank data changed." : ""
        if isWaitingForInitialTransactions {
            return "\(prefix). Accounts and suggestions are ready. Plaid is still preparing transaction history; click Sync Now again in a minute.\(retryDetail)"
        }
        return "\(prefix). Added \(addedCount) transactions for review.\(retryDetail)"
    }
}

private struct PlaidTransactionSyncBatch {
    var pageCount: Int
    var added: [PlaidTransactionDTO]
    var modified: [PlaidTransactionDTO]
    var removed: [PlaidRemovedTransactionDTO]
    var nextCursor: String?
}

enum PlaidMacSyncError: LocalizedError {
    case missingCredentials
    case noConnections
    case noPendingLinkSession
    case missingAccessToken
    case linkFinishedWithoutPublicToken(String)
    case transactionsChangedDuringPagination

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Add your Plaid Client ID and environment secret first."
        case .noConnections:
            return "Connect a bank before syncing."
        case .noPendingLinkSession:
            return "Start a bank connection first. MoneyMap does not have a Plaid Link session to finish."
        case .missingAccessToken:
            return "This bank's Plaid access token is missing from Keychain. Reconnect this bank from the Connections list."
        case .linkFinishedWithoutPublicToken(let message):
            return message
        case .transactionsChangedDuringPagination:
            return "Plaid kept changing transaction data while MoneyMap was syncing. Wait a minute, then click Sync Now again."
        }
    }
}

enum PlaidMacDateParsing {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func day(_ value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }
}
