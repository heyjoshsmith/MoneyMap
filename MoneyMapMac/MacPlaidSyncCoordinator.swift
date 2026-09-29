//
//  MacPlaidSyncCoordinator.swift
//  MoneyMapMac
//
//  Created by Codex on 7/6/26.
//

import AppKit
import Foundation
import OSLog
import SwiftData

@MainActor
final class MacPlaidSyncCoordinator: ObservableObject {
    private let logger = Logger(subsystem: "com.heyjoshsmith.MoneyMap.Mac", category: "BankSync")
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var pendingLinkSession: PlaidPendingLinkSession?

    private let credentialStore = PlaidCredentialStore()
    private let defaults = UserDefaults.standard
    private let pendingLinkSessionKey = "plaid.pendingHostedLinkSession"
    private let clientUserIDKey = "plaid.clientUserID"
    private let handledMacRefreshRequestIDKey = "plaid.handledMacRefreshRequestID"
    private var automaticRefreshTask: Task<Void, Never>?

    func startAutomaticRefresh(context: ModelContext) {
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            await self?.runAutomaticRefreshLoop(context: context)
        }
    }

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

    func startHostedLinkConnection(primaryProduct: String = "transactions") async {
        await run {
            let credentials = try self.requireCredentials()
            let session = try await MacPlaidAPIClient(credentials: credentials).createHostedLinkSession(
                clientUserID: self.clientUserID(),
                primaryProduct: primaryProduct
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

    func startReconnect(itemID: String, upgradeDataAccess: Bool = false) async {
        await run {
            let credentials = try self.requireCredentials()
            guard let accessToken = try self.credentialStore.accessToken(for: itemID) else {
                throw PlaidMacSyncError.missingAccessToken
            }
            let session = try await MacPlaidAPIClient(credentials: credentials).createHostedLinkSession(
                clientUserID: self.clientUserID(),
                accessToken: accessToken
            )
            var pendingSession = PlaidPendingLinkSession(
                linkToken: session.linkToken,
                hostedLinkURL: session.hostedLinkURL,
                expiration: session.expiration,
                requestID: session.requestID,
                mode: .updateItem,
                itemID: itemID,
                createdAt: .now
            )
            pendingSession.isDataUpgrade = upgradeDataAccess
            self.savePendingLinkSession(pendingSession)
            NSWorkspace.shared.open(session.hostedLinkURL)
            self.statusMessage = upgradeDataAccess ? "Approve additional data access in your browser, then return here to finish." : "Bank sign-in opened in your browser. Return here when you finish."
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

            if pendingSession.mode == .updateItem {
                if linkStatus.hasSuccessfulCompletion {
                    guard let itemID = pendingSession.itemID,
                          let accessToken = try self.credentialStore.accessToken(for: itemID) else {
                        throw PlaidMacSyncError.missingAccessToken
                    }
                    // Update mode keeps the same access token, even if Link returns a public token.
                    let summary = try await self.sync(itemID: itemID, accessToken: accessToken, client: client, context: context)
                    try await PlaidCloudSyncService.push(context: context)
                    self.clearPendingLinkSession()
                    let connection = try context.fetch(FetchDescriptor<PlaidConnection>()).first { $0.itemID == itemID }
                    let consentStillNeeded = PlaidConnectionEnrichment.decode(connection?.enrichmentJSON)?.productStatuses.contains {
                        $0.diagnosticMessage?.contains("ADDITIONAL_CONSENT_REQUIRED") == true
                    } ?? false
                    self.statusMessage = consentStillNeeded
                        ? "Bank sign-in finished and available data synced. Plaid still reports that additional data permissions were not granted. Check this connection’s data access details."
                        : summary.userMessage(prefix: pendingSession.isDataUpgrade == true ? "Data access updated" : "Reconnect finished")
                    return
                }
                if linkStatus.finishedWithoutPublicToken {
                    self.clearPendingLinkSession()
                    throw PlaidMacSyncError.linkFinishedWithoutPublicToken(linkStatus.userFacingStatusMessage)
                }
                self.statusMessage = "Waiting for Plaid to confirm the reconnect. Finish the bank flow in your browser, then choose Finish Bank Connection again."
                return
            }

            if publicTokens.isEmpty {
                if linkStatus.finishedWithoutPublicToken {
                    self.clearPendingLinkSession()
                    throw PlaidMacSyncError.linkFinishedWithoutPublicToken(linkStatus.userFacingStatusMessage)
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

    private func runAutomaticRefreshLoop(context: ModelContext) async {
        let pollInterval: UInt64 = 60
        var lastAutomaticRefresh = Date.distantPast

        while !Task.isCancelled {
            let automaticRefreshEnabled = defaults.object(forKey: MacBankSyncPreferences.automaticRefreshEnabledKey) as? Bool ?? true
            let minutes = defaults.object(forKey: MacBankSyncPreferences.refreshIntervalMinutesKey) as? Int ?? 60
            let interval = TimeInterval(max(minutes, 15) * 60)
            let didHandleCommand = await handlePendingMacRefreshCommand(context: context)
            if didHandleCommand {
                lastAutomaticRefresh = .now
            }

            if automaticRefreshEnabled, Date().timeIntervalSince(lastAutomaticRefresh) >= interval {
                await syncAutomatically(context: context)
                lastAutomaticRefresh = .now
            }
            await handlePhoneReconnectCommand(context: context)
            await handleWatchCommands(context: context)

            try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000)
        }
    }

    func removeConnection(itemID: String, context: ModelContext) async {
        await run { try await self.performRemoveConnection(itemID: itemID, context: context) }
    }

    private func performRemoveConnection(itemID: String, context: ModelContext) async throws {
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

    private func sync(itemID: String, accessToken: String, client: MacPlaidAPIClient, context: ModelContext) async throws -> PlaidTransactionSyncSummary {
        let item = try await client.item(accessToken: accessToken)
        var initialStatuses: [PlaidProductSyncStatus] = []
        var institution: PlaidInstitutionDTO?
        if let institutionID = item.institutionID {
            do { institution = try await client.institution(id: institutionID) }
            catch { initialStatuses.append(Self.productFailure("institution", error: error)) }
        }
        let accounts: [PlaidAccountDTO]
        let liveBalances: Bool
        do {
            accounts = try await client.accounts(accessToken: accessToken)
            liveBalances = true
            initialStatuses.append(.init(product: "balance", state: "available"))
        } catch {
            initialStatuses.append(Self.productFailure("balance", error: error))
            do { accounts = try await client.accounts(accessToken: accessToken, cached: true) }
            catch {
                initialStatuses.append(Self.productFailure("accounts", error: error))
                try upsertConnection(item: item, institution: institution, context: context)
                if let connection = try context.fetch(FetchDescriptor<PlaidConnection>()).first(where: { $0.itemID == itemID }) {
                    var metadata = PlaidConnectionEnrichment.decode(connection.enrichmentJSON) ?? PlaidConnectionEnrichment()
                    metadata.item = item.details
                    if let products = institution?.products { metadata.item["institution_supported_products"] = .array(products.map { .string($0) }) }
                    metadata.productStatuses.removeAll { status in initialStatuses.contains { $0.product == status.product } }
                    metadata.productStatuses.append(contentsOf: initialStatuses)
                    connection.enrichmentJSON = try metadata.encoded()
                    connection.status = "needs_attention"
                    connection.errorMessage = error.localizedDescription
                    try context.save()
                }
                throw error
            }
            liveBalances = false
        }
        try upsertConnection(item: item, institution: institution, context: context)
        try upsertAccounts(accounts, itemID: itemID, institutionName: institution?.name, liveBalances: liveBalances, context: context)
        let connections = try context.fetch(FetchDescriptor<PlaidConnection>())
        guard let connection = connections.first(where: { $0.itemID == itemID }) else { throw PlaidMacSyncError.noConnections }
        var enrichment = PlaidConnectionEnrichment.decode(connection.enrichmentJSON) ?? PlaidConnectionEnrichment()
        enrichment.item = item.details
        if let products = institution?.products { enrichment.item["institution_supported_products"] = .array(products.map { .string($0) }) }
        enrichment.productStatuses = initialStatuses
        var documents: [String: [String: PlaidJSONValue]] = [:]
        let products = [("liabilities", "/liabilities/get"), ("recurring", "/transactions/recurring/get"),
                        ("holdings", "/investments/holdings/get"), ("investment_transactions", "/investments/transactions/get")]
        for (product, path) in products {
            // Investments is account-specific. Other optional products can be unavailable despite account support;
            // requesting them records Plaid's actual entitlement/consent error instead of guessing capability.
            if (product == "holdings" || product == "investment_transactions") && !accounts.contains(where: { $0.type == "investment" }) {
                enrichment.productStatuses.append(.init(product: product, state: "unavailable", message: "No investment accounts are connected."))
                continue
            }
            do {
                documents[product] = product == "investment_transactions"
                    ? try await client.investmentTransactions(accessToken: accessToken)
                    : try await client.productDocument(path: path, accessToken: accessToken)
                enrichment.productStatuses.append(.init(product: product, state: "available"))
            } catch {
                enrichment.productStatuses.append(Self.productFailure(product, error: error))
            }
        }
        var liabilities: PlaidLiabilitiesResponse?
        if let document = documents["liabilities"] {
            do { liabilities = try JSONDecoder().decode(PlaidLiabilitiesResponse.self, from: JSONEncoder().encode(document)) }
            catch { enrichment.productStatuses.removeAll { $0.product == "liabilities" }; enrichment.productStatuses.append(Self.productFailure("liabilities", error: error)) }
        }
        try applyEnrichment(documents, accounts: accounts, itemID: itemID, context: context)
        try upsertSuggestions(accounts: accounts, itemID: itemID, liabilities: liabilities, context: context)
        let transactionSummary: PlaidTransactionSyncSummary
        do {
            if accounts.contains(where: { $0.type == "credit" || $0.type == "depository" }) {
                transactionSummary = try await syncTransactions(itemID: itemID, accessToken: accessToken, client: client, context: context)
                enrichment.productStatuses.append(.init(product: "transactions", state: "available"))
            } else {
                transactionSummary = .init(pageCount: 0, addedCount: 0, modifiedCount: 0, removedCount: 0, nextCursor: "not_applicable", restartCount: 0)
                enrichment.productStatuses.append(.init(product: "transactions", state: "unavailable", message: "No checking, savings, or credit accounts are connected. Investment activity is synced separately."))
            }
        } catch {
            enrichment.productStatuses.append(Self.productFailure("transactions", error: error))
            connection.enrichmentJSON = try enrichment.encoded()
            try context.save()
            throw error
        }
        connection.enrichmentJSON = try enrichment.encoded()
        connection.lastSyncAt = .now
        connection.updatedAt = .now
        try context.save()
        return transactionSummary
    }

    private static func productFailure(_ product: String, error: Error) -> PlaidProductSyncStatus {
        var state = "failed"
        if case PlaidAPIError.plaid(let response) = error,
           ["PRODUCT_NOT_READY", "PRODUCT_NOT_SUPPORTED", "ADDITIONAL_CONSENT_REQUIRED", "ACCESS_NOT_GRANTED", "PRODUCTS_NOT_SUPPORTED", "INVALID_PRODUCT", "NO_INVESTMENT_ACCOUNTS"].contains(response.errorCode ?? "") {
            state = "unavailable"
        }
        let message: String
        if case PlaidAPIError.plaid(let response) = error {
            let productName: String
            switch product {
            case "liabilities": productName = "card and loan payment details"
            case "holdings", "investment_transactions": productName = "investment data"
            case "recurring": productName = "recurring bills and income"
            case "balance": productName = "balance updates"
            default: productName = "this bank data"
            }
            switch response.errorCode {
            case "ADDITIONAL_CONSENT_REQUIRED", "ACCESS_NOT_GRANTED":
                message = "Reconnect this bank to allow \(productName)."
            case "PRODUCT_NOT_READY":
                message = "Your bank is still preparing \(productName). MoneyMap will try again on the next sync."
            case "PRODUCT_NOT_SUPPORTED", "PRODUCTS_NOT_SUPPORTED", "INVALID_PRODUCT", "NO_INVESTMENT_ACCOUNTS":
                message = "This connection does not currently provide \(productName)."
            default:
                message = response.displayMessage ?? response.errorMessage ?? "This bank could not provide \(productName). Try syncing again."
            }
        } else { message = error.localizedDescription }
        return .init(product: product, state: state, message: message, diagnosticMessage: error.localizedDescription)
    }

    private func applyEnrichment(_ documents: [String: [String: PlaidJSONValue]], accounts: [PlaidAccountDTO], itemID: String, context: ModelContext) throws {
        let snapshots = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>()).filter { $0.itemID == itemID }
        func objects(_ document: [String: PlaidJSONValue], _ key: String) -> [[String: PlaidJSONValue]] {
            (document[key]?.array ?? []).compactMap(\.object)
        }
        for snapshot in snapshots {
            var data = PlaidAccountEnrichment.decode(snapshot.enrichmentJSON) ?? PlaidAccountEnrichment()
            // Cached Accounts fallback must not replace a credit limit from an earlier live balance.
            if data.balanceSource != "cached" || data.creditLimit == nil {
                data.creditLimit = accounts.first { $0.accountID == snapshot.accountID }?.balances.limit
            }
            for (product, document) in documents {
                data.productUpdatedAt[product] = .now
                switch product {
                case "liabilities":
                    let liabilities = document["liabilities"]?.object ?? [:]
                    data.creditLiability = objects(liabilities, "credit").first { $0["account_id"]?.string == snapshot.accountID }
                    data.mortgageLiability = objects(liabilities, "mortgage").first { $0["account_id"]?.string == snapshot.accountID }
                    data.studentLoanLiability = objects(liabilities, "student").first { $0["account_id"]?.string == snapshot.accountID }
                case "recurring":
                    data.recurringInflows = objects(document, "inflow_streams").filter { $0["account_id"]?.string == snapshot.accountID }
                    data.recurringOutflows = objects(document, "outflow_streams").filter { $0["account_id"]?.string == snapshot.accountID }
                case "holdings":
                    data.holdings = objects(document, "holdings").filter { $0["account_id"]?.string == snapshot.accountID }
                case "investment_transactions":
                    data.investmentTransactions = objects(document, "investment_transactions").filter { $0["account_id"]?.string == snapshot.accountID }
                default: break
                }
            }
            if documents["holdings"] != nil || documents["investment_transactions"] != nil {
                var securities = Dictionary(data.securities.compactMap { object -> (String, [String: PlaidJSONValue])? in
                    guard let id = object["security_id"]?.string else { return nil }; return (id, object)
                }, uniquingKeysWith: { _, new in new })
                let ids = Set((data.holdings + data.investmentTransactions).compactMap { $0["security_id"]?.string })
                for product in ["holdings", "investment_transactions"] {
                    for security in objects(documents[product] ?? [:], "securities") {
                        if let id = security["security_id"]?.string, ids.contains(id) { securities[id] = security }
                    }
                }
                data.securities = securities.filter { ids.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
            }
            snapshot.enrichmentJSON = try data.encoded()
        }
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
            logger.notice("Automatic bank refresh and iCloud upload completed.")
        } catch PlaidMacSyncError.missingCredentials, PlaidMacSyncError.noConnections {
            return
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Automatic bank refresh failed: \(error.localizedDescription, privacy: .public)")
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
        if let name = institution?.name { connection.institutionName = name }
        connection.status = "active"
        connection.errorMessage = nil
        connection.updatedAt = .now

        if !existing.contains(where: { $0 === connection }) {
            context.insert(connection)
        }
    }

    private func upsertAccounts(
        _ accounts: [PlaidAccountDTO],
        itemID: String,
        institutionName: String?,
        liveBalances: Bool,
        context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        let accountsByID = Dictionary(existing.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        // The successful unfiltered Accounts response is authoritative for active connected accounts.
        // Remove stale source snapshots and suggestions, retaining the user's bills and transaction history.
        let activeIDs = Set(accounts.map(\.accountID))
        for snapshot in existing where snapshot.itemID == itemID && !activeIDs.contains(snapshot.accountID) {
            context.delete(snapshot)
        }
        let suggestions = try context.fetch(FetchDescriptor<PlaidSuggestion>())
        for suggestion in suggestions where suggestion.plaidItemID == itemID && !activeIDs.contains(suggestion.plaidAccountID) {
            context.delete(suggestion)
        }

        for dto in accounts {
            let snapshot = accountsByID[dto.accountID] ?? PlaidAccountSnapshot(
                accountID: dto.accountID,
                itemID: itemID,
                accountName: dto.name,
                type: dto.type
            )
            snapshot.itemID = itemID
            if let institutionName { snapshot.institutionName = institutionName }
            snapshot.accountName = dto.name
            snapshot.officialName = dto.officialName
            snapshot.mask = dto.mask
            snapshot.type = dto.type
            snapshot.subtype = dto.subtype
            var metadata = PlaidAccountEnrichment.decode(snapshot.enrichmentJSON) ?? PlaidAccountEnrichment()
            metadata.balanceSource = liveBalances ? "live" : "cached"
            let reportedDate = dto.balances.lastUpdatedDateTime.flatMap { ISO8601DateFormatter().date(from: $0) }
            if liveBalances, reportedDate != nil { metadata.balanceSource = "bank_reported" }
            if liveBalances || accountsByID[dto.accountID] == nil {
                snapshot.currentBalance = dto.balances.current
                snapshot.availableBalance = dto.balances.available
                snapshot.currencyCode = dto.balances.isoCurrencyCode
                // A cache response often has no source timestamp. Never label its retrieval time a fresh bank balance.
                snapshot.updatedAt = reportedDate ?? (liveBalances ? .now : .distantPast)
            }
            if liveBalances { metadata.productUpdatedAt["balance"] = snapshot.updatedAt }
            snapshot.enrichmentJSON = try metadata.encoded()

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
            // A bill schedules a payment, while the statement balance remains in account metadata.
            // This changes only the review suggestion; accepted cards retain their chosen payment amount.
            let creditLiability = creditLiabilities[account.accountID]
            if account.type != "credit" || liabilities != nil || suggestionsByKey["\(kind.rawValue):\(account.accountID)"] == nil {
                suggestion.amount = creditLiability?.minimumPaymentAmount ?? creditLiability?.lastStatementBalance ?? account.balances.current
                suggestion.dueDate = PlaidMacDateParsing.day(creditLiability?.nextPaymentDueDate)
            }
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
        let savedCursor = storedCursor(itemID: itemID)
        let backfillKey = "plaid.transactions.enrichmentBackfill.v1.\(itemID)"
        let existingItems = try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>())
        let needsBackfill = !defaults.bool(forKey: backfillKey) && existingItems.contains {
            $0.plaidItemID == itemID && $0.bankRemovedAt == nil && ($0.enrichmentJSON?.isEmpty ?? true)
        }
        let startingCursor = needsBackfill ? nil : savedCursor
        let maxPaginationRestarts = 3
        var restartCount = 0

        while true {
            do {
                // Capture removals since the old cursor before requesting full history. A nil-cursor
                // response alone cannot tell us which previously imported transactions were removed.
                let delta: PlaidTransactionSyncBatch?
                if needsBackfill, let savedCursor {
                    delta = try await fetchTransactionSyncBatch(accessToken: accessToken, startingCursor: savedCursor, client: client)
                } else { delta = nil }
                let batch = try await fetchTransactionSyncBatch(
                    accessToken: accessToken,
                    startingCursor: startingCursor,
                    client: client
                )
                if let delta { try applyTransactionSyncBatch(delta, itemID: itemID, context: context) }
                try applyTransactionSyncBatch(batch, itemID: itemID, preservingTombstones: needsBackfill, context: context)
                // Persist all rows before committing the external cursor. A crash before this point
                // safely replays the same idempotent batch on the next refresh.
                try context.save()
                if let cursor = batch.nextCursor, !cursor.isEmpty {
                    defaults.set(cursor, forKey: cursorDefaultsKey(itemID: itemID))
                    if needsBackfill { defaults.set(true, forKey: backfillKey) }
                }
                let knownIDs = Set(existingItems.map(\.plaidTransactionID))
                let additions = Set((batch.added + (delta?.added ?? [])).map(\.transactionID)).subtracting(knownIDs).count
                return PlaidTransactionSyncSummary(
                    pageCount: batch.pageCount + (delta?.pageCount ?? 0),
                    addedCount: needsBackfill ? additions : batch.added.count,
                    modifiedCount: batch.modified.count + (delta?.modified.count ?? 0),
                    removedCount: Set((batch.removed + (delta?.removed ?? [])).map(\.transactionID)).count,
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
        preservingTombstones: Bool = false,
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
            let enrichment = PlaidTransactionEnrichment(details: transaction.details)
            reviewItem.enrichmentJSON = try enrichment.encoded()
            if !preservingTombstones { reviewItem.bankRemovedAt = nil }
            reviewItem.category = enrichment.detailedCategory ?? transaction.category?.joined(separator: " / ")
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
            if let reviewItem = reviewItemsByID[removed.transactionID] {
                reviewItem.bankRemovedAt = .now
                reviewItem.updatedAt = .now
                if reviewItem.status == .ready { reviewItem.status = .skipped }
            }
        }
    }

    /// iPhone has its own consent bridge. The separate Watch institution verification gate stays intact.
    private func handlePhoneReconnectCommand(context: ModelContext) async {
        guard !isWorking else { return }
        do {
            guard var command = try await PhoneBankReconnectCommandStore.latest(), !isWorking else { return }
            let activeKey = "phone.bankReconnect.activeRequestID"
            if let previousID = defaults.string(forKey: activeKey), previousID != command.id {
                clearPhoneReconnectSession(id: previousID)
            }
            if command.isTerminal { clearPhoneReconnectSession(id: command.id); return }
            defaults.set(command.id, forKey: activeKey)
            isWorking = true
            defer { isWorking = false }
            let key = "phone.bankReconnect.linkToken.\(command.id)"
            if command.hasExpired {
                command.state = .failed
                command.message = "Bank sign-in expired. Start reconnect again from your iPhone."
                _ = try await PhoneBankReconnectCommandStore.update(command)
                clearPhoneReconnectSession(id: command.id)
                return
            }
            do {
                let connections = try context.fetch(FetchDescriptor<PlaidConnection>())
                guard connections.contains(where: { $0.itemID == command.itemID }),
                      let accessToken = try credentialStore.accessToken(for: command.itemID) else {
                    throw PlaidMacSyncError.missingAccessToken
                }
                let client = MacPlaidAPIClient(credentials: try requireCredentials())
                if let token = defaults.string(forKey: key) {
                    if command.state == .requested {
                        command.hostedURL = defaults.url(forKey: key + ".url")
                        guard command.sanitizedHostedURL != nil else {
                            throw PlaidAPIError.transport("The pending bank sign-in session could not be restored. Start reconnect again from your iPhone.")
                        }
                        if let expiration = defaults.object(forKey: key + ".expiration") as? Date {
                            command.expiresAt = min(command.expiresAt, expiration)
                        }
                        command.state = .ready
                        command.message = "Ready to continue your bank sign-in on iPhone."
                        _ = try await PhoneBankReconnectCommandStore.update(command)
                        return
                    }
                    let result = try await client.linkTokenStatus(linkToken: token)
                    if result.hasSuccessfulCompletion {
                        // Re-check after network work so canceled/superseded requests do not trigger a sync.
                        guard let current = try await PhoneBankReconnectCommandStore.latest(), current.id == command.id,
                              !current.isTerminal, !current.hasExpired else { return }
                        _ = try await sync(itemID: command.itemID, accessToken: accessToken, client: client, context: context)
                        try await PlaidCloudSyncService.push(context: context)
                        let connection = connections.first { $0.itemID == command.itemID }
                        let consentMissing = PlaidConnectionEnrichment.decode(connection?.enrichmentJSON)?.productStatuses.contains {
                            $0.diagnosticMessage?.contains("ADDITIONAL_CONSENT_REQUIRED") == true
                        } ?? false
                        command.state = .succeeded
                        command.message = consentMissing
                            ? "Bank sign-in finished and available data synced. Plaid still needs additional permissions for some bank details."
                            : "Bank reconnected and the latest available data synced."
                        if try await PhoneBankReconnectCommandStore.update(command) { clearPhoneReconnectSession(id: command.id) }
                    } else if result.finishedWithoutPublicToken {
                        command.state = .failed
                        command.message = result.userFacingStatusMessage
                        if try await PhoneBankReconnectCommandStore.update(command) { clearPhoneReconnectSession(id: command.id) }
                    }
                } else if command.state == .requested {
                    let session = try await client.createHostedLinkSession(clientUserID: clientUserID(), accessToken: accessToken, phone: true)
                    command.hostedURL = session.hostedLinkURL
                    guard command.sanitizedHostedURL != nil else {
                        throw PlaidAPIError.transport("Plaid returned an unexpected bank sign-in address. Try reconnecting again.")
                    }
                    command.state = .ready
                    command.message = "Ready to continue your bank sign-in on iPhone."
                    if let expiration = session.expiration { command.expiresAt = min(command.expiresAt, expiration) }
                    // The Link token stays on this Mac; only the short-lived Hosted Link URL goes to iCloud.
                    defaults.set(session.hostedLinkURL, forKey: key + ".url")
                    defaults.set(command.expiresAt, forKey: key + ".expiration")
                    defaults.set(session.linkToken, forKey: key)
                    if !(try await PhoneBankReconnectCommandStore.update(command)) { clearPhoneReconnectSession(id: command.id) }
                } else {
                    command.state = .failed
                    command.message = "This Mac no longer has the pending sign-in session. Start reconnect again from your iPhone."
                    _ = try await PhoneBankReconnectCommandStore.update(command)
                }
            } catch {
                command.state = .failed
                command.message = error.localizedDescription
                if try await PhoneBankReconnectCommandStore.update(command) { clearPhoneReconnectSession(id: command.id) }
            }
        } catch {
            logger.error("iPhone bank reconnect bridge failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearPhoneReconnectSession(id: String) {
        let key = "phone.bankReconnect.linkToken.\(id)"
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + ".url")
        defaults.removeObject(forKey: key + ".expiration")
        if defaults.string(forKey: "phone.bankReconnect.activeRequestID") == id {
            defaults.removeObject(forKey: "phone.bankReconnect.activeRequestID")
        }
    }

    private func handleWatchCommands(context: ModelContext) async {
        guard !isWorking else { return }
        do {
            let commands = try await WatchBankCommandStore.pending()
            guard !commands.isEmpty, !isWorking else { return }
            isWorking = true
            defer { isWorking = false }
            for var command in commands {
                if command.expiresAt < .now {
                    command.state = "expired"; command.message = "Request expired. Start again on Watch."
                    try await WatchBankCommandStore.update(command); continue
                }
                do {
                    if command.action == "refresh" {
                        command.message = try await performSyncAll(context: context)
                        command.state = "succeeded"
                    } else if command.action == "disconnect", let itemID = command.itemID {
                        try await performRemoveConnection(itemID: itemID, context: context)
                        command.state = "succeeded"; command.message = "Bank removed from MoneyMap."
                    } else if command.action == "link" || command.action == "reconnect" {
                        guard !WatchBankCompatibility.verifiedInstitutionIDs.isEmpty else {
                            throw NSError(domain: "MoneyMap", code: 2, userInfo: [NSLocalizedDescriptionKey: "No banks have completed Watch-only verification yet."])
                        }
                        if let itemID = command.itemID {
                            let connection = try context.fetch(FetchDescriptor<PlaidConnection>(predicate: #Predicate { $0.itemID == itemID })).first
                            guard let institutionID = connection?.institutionID, WatchBankCompatibility.verifiedInstitutionIDs.contains(institutionID) else {
                                throw NSError(domain: "MoneyMap", code: 4, userInfo: [NSLocalizedDescriptionKey: "This bank is not verified for Watch-only sign-in."])
                            }
                        }
                        let client = MacPlaidAPIClient(credentials: try requireCredentials())
                        let key = "watch.link." + command.id
                        if let token = defaults.string(forKey: key) {
                            let result = try await client.linkTokenStatus(linkToken: token)
                            if !result.publicTokens.isEmpty && command.itemID == nil {
                                guard !result.institutionIDs.isEmpty, Set(result.institutionIDs).isSubset(of: WatchBankCompatibility.verifiedInstitutionIDs) else {
                                    throw NSError(domain: "MoneyMap", code: 3, userInfo: [NSLocalizedDescriptionKey: "This bank is not verified for Watch-only sign-in."])
                                }
                                for token in result.publicTokens {
                                    let exchangeKey = key + ".exchanged." + String(token.suffix(36))
                                    let itemID: String
                                    let accessToken: String
                                    if let saved = defaults.string(forKey: exchangeKey), let access = try credentialStore.accessToken(for: saved) {
                                        itemID = saved; accessToken = access
                                    } else {
                                        let item = try await client.exchangePublicToken(token)
                                        try credentialStore.saveAccessToken(item.accessToken, itemID: item.itemID)
                                        defaults.set(item.itemID, forKey: exchangeKey)
                                        itemID = item.itemID; accessToken = item.accessToken
                                    }
                                    _ = try await sync(itemID: itemID, accessToken: accessToken, client: client, context: context)
                                }
                                try await PlaidCloudSyncService.push(context: context)
                                command.state = "succeeded"; command.message = "Bank connected."
                            } else if result.hasSuccessfulCompletion, let itemID = command.itemID, let access = try credentialStore.accessToken(for: itemID) {
                                _ = try await sync(itemID: itemID, accessToken: access, client: client, context: context)
                                try await PlaidCloudSyncService.push(context: context)
                                command.state = "succeeded"; command.message = "Bank reconnected."
                            } else if result.finishedWithoutPublicToken {
                                command.state = "failed"; command.message = result.userFacingStatusMessage
                            }
                        } else {
                            let access = try command.itemID.flatMap { try credentialStore.accessToken(for: $0) }
                            let session = try await client.createHostedLinkSession(clientUserID: clientUserID(), accessToken: access, watch: true)
                            defaults.set(session.linkToken, forKey: key)
                            command.hostedURL = session.hostedLinkURL; command.state = "ready"
                            command.message = "Ready to sign in on Watch."
                        }
                    } else {
                        command.state = "failed"; command.message = "Unsupported request."
                    }
                } catch { command.state = "failed"; command.message = error.localizedDescription }
                if command.isTerminal { command.hostedURL = nil }
                try await WatchBankCommandStore.update(command)
            }
        } catch {
            // A missing development schema must not stop existing Mac refreshes.
            print("Watch bank requests unavailable: \(error.localizedDescription)")
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
        guard !isWorking else { return }
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
    var isDataUpgrade: Bool? = nil

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
