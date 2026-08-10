//
//  PlaidConnectionsView.swift
//  MoneyMap
//
//  Created by Codex on 7/5/26.
//

import AuthenticationServices
import SwiftData
import SwiftUI

struct PlaidConnectionsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PlaidConnection.updatedAt, order: .reverse) private var connections: [PlaidConnection]
    @Query(sort: \PlaidAccountSnapshot.accountName) private var accountSnapshots: [PlaidAccountSnapshot]
    @Query private var bills: [Bill]
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @Query private var importedTransactions: [Transaction]

    @AppStorage("plaidServerBaseURL") private var serverBaseURL = "http://127.0.0.1:3030"

    @StateObject private var authenticationAnchorProvider = PlaidAuthenticationAnchorProvider()
    @State private var authenticationSession: ASWebAuthenticationSession?
    @State private var latestSnapshot: PlaidSnapshot?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var manualPublicToken = ""
    @State private var isWorking = false

    var body: some View {
        List {
            Section {
                TextField("Server URL", text: $serverBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                HStack {
                    Button {
                        connectWithHostedLink()
                    } label: {
                        Label("Connect Bank", systemImage: "link")
                    }
                    .disabled(isWorking || client == nil)

                    Spacer()

                    Button {
                        syncNow()
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isWorking || client == nil || connections.isEmpty)
                }

                Button {
                    createSandboxConnection()
                } label: {
                    Label("Create Sandbox Connection", systemImage: "testtube.2")
                }
                .disabled(isWorking || client == nil)
            } header: {
                Text("Plaid Server")
            } footer: {
                Text("Run the local server with PLAID_CLIENT_ID and PLAID_SECRET set. MoneyMap stores Plaid access tokens on that server, not in the app.")
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            if let statusMessage {
                Section {
                    MoneyMapStatusLabel(message: statusMessage, systemImage: "checkmark.circle")
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }

            if let errorMessage {
                Section {
                    MoneyMapStatusLabel(message: errorMessage, systemImage: "exclamationmark.triangle", tint: MoneyMapDesign.attentionRed)
                        .textSelection(.enabled)
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }

            connectionsSection
            accountsSection
            reviewSection
            suggestionsSection
            advancedSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("Bank Connections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isWorking {
                    ProgressView()
                } else {
                    Button {
                        loadSnapshot()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(client == nil)
                }
            }
        }
        .task {
            if latestSnapshot == nil {
                await loadSnapshotIfPossible()
            }
        }
    }

    private var connectionsSection: some View {
        Section("Connections") {
            if connections.isEmpty {
                ContentUnavailableView(
                    "No Banks Connected",
                    systemImage: "building.columns",
                    description: Text("Connect a Plaid Sandbox institution or complete a hosted Plaid Link session.")
                )
            } else {
                ForEach(0..<connectionRows.count, id: \.self) { index in
                    PlaidConnectionListRow(connection: connectionRows[index].connection)
                }
            }
        }
    }

    private var accountsSection: some View {
        Section("Accounts") {
            if accountSnapshots.isEmpty {
                Text("Synced Plaid accounts will appear here before you choose what to import into MoneyMap.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(0..<accountRows.count, id: \.self) { index in
                    PlaidAccountSnapshotRow(
                        account: accountRows[index].account,
                        detail: accountDetail(accountRows[index].account),
                        icon: icon(
                            for: accountRows[index].account.type,
                            subtype: accountRows[index].account.subtype
                        )
                    )
                }
            }
        }
    }

    private var reviewSection: some View {
        Section {
            if unimportedTransactions.isEmpty {
                Text("No reviewed transactions are waiting to import.")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(unimportedTransactions.count) transactions ready")
                            .font(.headline)
                        Text("MoneyMap will skip Plaid IDs and likely CSV duplicates it already has.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Import") {
                        importReviewedTransactions()
                    }
                    .disabled(isWorking)
                }

                ForEach(Array(unimportedTransactions.prefix(8))) { transaction in
                    PlaidTransactionReviewRow(transaction: transaction)
                }

                if unimportedTransactions.count > 8 {
                    Text("\(unimportedTransactions.count - 8) more transactions will import with this batch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Review Transactions")
        } footer: {
            Text("Plaid transactions are not written to MoneyMap until you import them from this review queue.")
        }
    }

    private var suggestionsSection: some View {
        Section("Suggested Updates") {
            if paymentMethodSuggestions.isEmpty && cardSuggestions.isEmpty {
                Text("Sync Plaid to review payment method and credit card suggestions.")
                    .foregroundStyle(.secondary)
            }

            ForEach(paymentMethodSuggestions) { account in
                PlaidSuggestionRow(
                    icon: account.paymentMethodType.icon,
                    title: "Create \(account.paymentMethodType.name)",
                    detail: suggestionDetail(for: account),
                    actionTitle: "Create"
                ) {
                    createPaymentMethod(from: account)
                }
                .disabled(isWorking)
            }

            ForEach(cardSuggestions) { suggestion in
                PlaidSuggestionRow(
                    icon: "creditcard",
                    title: suggestion.bill == nil ? "Create Credit Card Bill" : "Update \(suggestion.bill?.name ?? "Card")",
                    detail: cardSuggestionDetail(suggestion),
                    actionTitle: suggestion.bill == nil ? "Create" : "Update"
                ) {
                    applyCardSuggestion(suggestion)
                }
                .disabled(isWorking)
            }
        }
    }

    private var advancedSection: some View {
        Section {
            TextField("Public token", text: $manualPublicToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                exchangeManualPublicToken()
            } label: {
                Label("Exchange Public Token", systemImage: "key")
            }
            .disabled(isWorking || manualPublicToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Advanced")
        } footer: {
            Text("Use this only for Plaid Sandbox or debugging. Real users should connect through Plaid Link.")
        }
    }

    private var client: PlaidClient? {
        guard let url = URL(string: serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return PlaidClient(baseURL: url)
    }

    private var connectionRows: [PlaidConnectionRowData] {
        connections.map(PlaidConnectionRowData.init)
    }

    private var accountRows: [PlaidAccountRowData] {
        accountSnapshots.map(PlaidAccountRowData.init)
    }

    private var currentSnapshot: PlaidSnapshot {
        latestSnapshot ?? PlaidSnapshot(
            connections: connections.map {
                PlaidConnectionDTO(
                    itemId: $0.itemID,
                    institutionId: $0.institutionID,
                    institutionName: $0.institutionName,
                    transactionsCursor: nil,
                    status: $0.status,
                    errorMessage: $0.errorMessage,
                    createdAt: nil,
                    updatedAt: nil,
                    lastSyncAt: nil
                )
            },
            accounts: accountSnapshots.map {
                PlaidAccountDTO(
                    accountId: $0.accountID,
                    itemId: $0.itemID,
                    institutionName: $0.institutionName,
                    name: $0.accountName,
                    officialName: $0.officialName,
                    mask: $0.mask,
                    type: $0.type,
                    subtype: $0.subtype,
                    currentBalance: $0.currentBalance,
                    availableBalance: $0.availableBalance,
                    currencyCode: $0.currencyCode,
                    updatedAt: nil
                )
            },
            transactions: [],
            liabilities: []
        )
    }

    private var unimportedTransactions: [PlaidTransactionDTO] {
        let importedIDs = Set(importedTransactions.compactMap(\.plaidTransactionID))
        return currentSnapshot.transactions
            .filter { !importedIDs.contains($0.transactionId) }
            .sorted {
                ($0.date ?? "") > ($1.date ?? "")
            }
    }

    private var paymentMethodSuggestions: [PlaidAccountDTO] {
        let existingAccountIDs = Set(paymentMethods.compactMap(\.plaidAccountID))
        return currentSnapshot.accounts
            .filter { !existingAccountIDs.contains($0.accountId) }
            .filter { $0.paymentMethodType != .creditCard }
    }

    private var cardSuggestions: [PlaidCardSuggestion] {
        currentSnapshot.liabilities
            .filter { $0.type == "credit" }
            .compactMap { liability in
                guard let account = account(for: liability.accountId) else { return nil }
                let bill = linkedCardBill(for: account)
                return PlaidCardSuggestion(liability: liability, account: account, bill: bill)
            }
    }

    private func connectWithHostedLink() {
        runTask {
            guard let client else { throw PlaidViewError.invalidServerURL }
            let hostedLinkSession = try await client.createHostedLinkToken()
            guard let hostedURL = hostedLinkSession.hostedURL else {
                throw PlaidViewError.invalidHostedLinkURL
            }

            statusMessage = "Opening Plaid Link."
            errorMessage = nil
            openHostedLink(hostedURL, linkToken: hostedLinkSession.linkToken)
        }
    }

    private func openHostedLink(_ url: URL, linkToken: String) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "moneymap") { _, error in
            Task { @MainActor in
                if let error {
                    errorMessage = error.localizedDescription
                    statusMessage = nil
                    return
                }

                await completeHostedLink(linkToken: linkToken)
            }
        }
        session.presentationContextProvider = authenticationAnchorProvider
        session.prefersEphemeralWebBrowserSession = true
        authenticationSession = session
        if !session.start() {
            errorMessage = "Could not start the Plaid Link session."
        }
    }

    private func completeHostedLink(linkToken: String) async {
        await runAsyncTask {
            guard let client else { throw PlaidViewError.invalidServerURL }
            _ = try await client.completeHostedLink(linkToken: linkToken)
            try await syncWithClient(client)
            statusMessage = "Plaid connection added."
        }
    }

    private func createSandboxConnection() {
        runTask {
            guard let client else { throw PlaidViewError.invalidServerURL }
            _ = try await client.createSandboxConnection()
            try await syncWithClient(client)
            statusMessage = "Sandbox connection added and synced."
        }
    }

    private func exchangeManualPublicToken() {
        runTask {
            guard let client else { throw PlaidViewError.invalidServerURL }
            let token = manualPublicToken.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await client.exchangePublicToken(token)
            manualPublicToken = ""
            try await syncWithClient(client)
            statusMessage = "Public token exchanged and synced."
        }
    }

    private func syncNow() {
        runTask {
            guard let client else { throw PlaidViewError.invalidServerURL }
            try await syncWithClient(client)
            statusMessage = "Plaid sync complete."
        }
    }

    private func loadSnapshot() {
        runTask {
            guard let client else { throw PlaidViewError.invalidServerURL }
            let snapshot = try await client.snapshot(limit: 500)
            try PlaidLocalSyncImporter.refreshSnapshots(snapshot, context: modelContext)
            latestSnapshot = snapshot
            statusMessage = "Plaid snapshot refreshed."
        }
    }

    private func loadSnapshotIfPossible() async {
        guard let client else { return }
        do {
            let snapshot = try await client.snapshot(limit: 500)
            try PlaidLocalSyncImporter.refreshSnapshots(snapshot, context: modelContext)
            latestSnapshot = snapshot
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncWithClient(_ client: PlaidClient) async throws {
        let response = try await client.sync()
        try PlaidLocalSyncImporter.refreshSnapshots(response.snapshot, context: modelContext)
        latestSnapshot = response.snapshot
    }

    private func importReviewedTransactions() {
        runTask {
            let summary = try PlaidLocalSyncImporter.importReviewedTransactions(
                unimportedTransactions,
                context: modelContext,
                bills: bills
            )
            let settlementSummary = try ExtraMoneyPlanSettlementService.settlePendingPayments(context: modelContext)
            var message = "Imported \(summary.importedCount) transactions. Skipped \(summary.skippedCount)."
            if settlementSummary.paidCardCount > 0 {
                message += " Confirmed \(settlementSummary.paidCardCount) pending card payment\(settlementSummary.paidCardCount == 1 ? "" : "s")."
            }
            statusMessage = message
            AppRefreshEvents.notifyBillsDidChange()
        }
    }

    private func createPaymentMethod(from account: PlaidAccountDTO) {
        let paymentMethod = PaymentMethod(
            name: account.displayName,
            type: account.paymentMethodType,
            institutionName: account.institutionName,
            lastFourDigits: account.mask,
            plaidAccountID: account.accountId,
            plaidItemID: account.itemId,
            plaidUpdatedAt: .now
        )
        modelContext.insert(paymentMethod)
        saveSuggestionResult("Payment method created.")
    }

    private func applyCardSuggestion(_ suggestion: PlaidCardSuggestion) {
        let bill = suggestion.bill ?? Bill(
            name: suggestion.account.displayName,
            amount: suggestion.liability.minimumPaymentAmount,
            dueDate: PlaidDateParsing.day(suggestion.liability.nextPaymentDueDate),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )

        bill.name = bill.name?.isEmpty == false ? bill.name : suggestion.account.displayName
        bill.amount = suggestion.liability.minimumPaymentAmount ?? bill.amount
        bill.dueDate = PlaidDateParsing.day(suggestion.liability.nextPaymentDueDate) ?? bill.dueDate
        bill.recurrenceInterval = bill.recurrenceInterval ?? 1
        bill.recurrenceUnit = bill.recurrenceUnit ?? .month
        bill.category = .creditCard
        bill.creditCardDetails = CreditCardDetails(
            creditLimit: suggestion.liability.creditLimit ?? bill.creditCardDetails?.creditLimit ?? 0,
            cardBalance: suggestion.account.currentBalance ?? suggestion.liability.currentBalance ?? bill.creditCardDetails?.cardBalance ?? 0,
            annualPercentageRate: suggestion.liability.aprPercentage ?? bill.creditCardDetails?.annualPercentageRate,
            minimumPayment: suggestion.liability.minimumPaymentAmount ?? bill.creditCardDetails?.minimumPayment,
            statementBalance: suggestion.liability.lastStatementBalance ?? bill.creditCardDetails?.statementBalance,
            issuerName: suggestion.account.institutionName ?? bill.creditCardDetails?.issuerName,
            lastFourDigits: suggestion.account.mask ?? bill.creditCardDetails?.lastFourDigits,
            statementClosingDate: PlaidDateParsing.day(suggestion.liability.lastStatementIssueDate) ?? bill.creditCardDetails?.statementClosingDate,
            promoAPRExpiration: bill.creditCardDetails?.promoAPRExpiration
        )
        bill.plaidAccountID = suggestion.account.accountId
        bill.plaidItemID = suggestion.account.itemId
        bill.plaidUpdatedAt = .now
        bill.checkStatus()

        if suggestion.bill == nil {
            modelContext.insert(bill)
        }

        saveSuggestionResult(suggestion.bill == nil ? "Credit card bill created." : "Credit card bill updated.")
    }

    private func saveSuggestionResult(_ message: String) {
        do {
            try modelContext.save()
            statusMessage = message
            errorMessage = nil
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runTask(_ operation: @escaping () async throws -> Void) {
        Task { @MainActor in
            await runAsyncTask(operation)
        }
    }

    private func runAsyncTask(_ operation: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func account(for accountID: String) -> PlaidAccountDTO? {
        currentSnapshot.accounts.first { $0.accountId == accountID }
    }

    private func linkedCardBill(for account: PlaidAccountDTO) -> Bill? {
        if let linkedBill = bills.first(where: { $0.plaidAccountID == account.accountId }) {
            return linkedBill
        }

        guard let mask = account.mask else { return nil }
        return bills.first { bill in
            bill.category == .creditCard &&
            bill.creditCardDetails?.lastFourDigits == mask &&
            (account.institutionName == nil || bill.creditCardDetails?.issuerName == account.institutionName)
        }
    }

    private func suggestionDetail(for account: PlaidAccountDTO) -> String {
        let parts = [
            account.institutionName,
            account.mask.map { "Ending \($0)" },
            account.currentBalance.map { MoneyMapFormatters.currencyString(for: $0) }
        ]
        return parts.compactMap { $0 }.joined(separator: " - ")
    }

    private func cardSuggestionDetail(_ suggestion: PlaidCardSuggestion) -> String {
        let pieces = [
            suggestion.account.institutionName,
            suggestion.account.mask.map { "Ending \($0)" },
            suggestion.liability.minimumPaymentAmount.map { "Minimum \(MoneyMapFormatters.currencyString(for: $0))" },
            suggestion.liability.nextPaymentDueDate.map { "Due \($0)" }
        ]
        return pieces.compactMap { $0 }.joined(separator: " - ")
    }

    private func accountDetail(_ account: PlaidAccountSnapshot) -> String {
        let parts = [
            account.institutionName,
            account.subtype,
            account.lastFourLabel
        ]
        return parts.compactMap { $0 }.joined(separator: " - ")
    }

    private func icon(for type: String, subtype: String?) -> String {
        if subtype == "credit card" || type == "credit" {
            return "creditcard"
        }
        if subtype == "savings" {
            return "banknote"
        }
        return "building.columns"
    }
}

private struct PlaidTransactionReviewRow: View {
    let transaction: PlaidTransactionDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.pending ? "clock" : "checkmark.circle")
                .foregroundStyle(transaction.pending ? .orange : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.displayMerchant)
                    .font(.subheadline.weight(.semibold))
                Text(transaction.category ?? transaction.date ?? "Uncategorized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let amount = transaction.amount {
                Text(amount, format: .currency(code: transaction.currencyCode ?? "USD"))
                    .font(.subheadline)
            }
        }
    }
}

struct PlaidConnectionListRow: View {
    let connection: PlaidConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(connection.institutionName ?? "Plaid Institution")
                    .font(.headline)
                Spacer()
                Text(connection.status ?? "Connected")
                    .font(.caption)
                    .foregroundStyle(connection.errorMessage == nil ? Color.secondary : MoneyMapDesign.attentionRed)
            }

            if let lastSyncAt = connection.lastSyncAt {
                Text("Last sync \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = connection.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(MoneyMapDesign.attentionRed)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PlaidAccountSnapshotRow: View {
    let account: PlaidAccountSnapshot
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let balance = account.currentBalance {
                Text(balance, format: .currency(code: account.currencyCode ?? "USD"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PlaidSuggestionRow: View {
    let icon: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail.isEmpty ? "Plaid account metadata" : detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(actionTitle, action: action)
        }
        .padding(.vertical, 2)
    }
}

private struct PlaidCardSuggestion: Identifiable {
    var id: String { liability.accountId }

    let liability: PlaidLiabilityDTO
    let account: PlaidAccountDTO
    let bill: Bill?
}

private struct PlaidConnectionRowData: Identifiable {
    let connection: PlaidConnection

    var id: UUID {
        connection.id
    }
}

private struct PlaidAccountRowData: Identifiable {
    let account: PlaidAccountSnapshot

    var id: UUID {
        account.id
    }
}

private enum PlaidViewError: LocalizedError {
    case invalidServerURL
    case invalidHostedLinkURL

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid MoneyMap Plaid server URL."
        case .invalidHostedLinkURL:
            return "The Plaid server did not return a valid Hosted Link URL."
        }
    }
}

private final class PlaidAuthenticationAnchorProvider: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        guard let windowScene else {
            preconditionFailure("Plaid Link requires an active window scene.")
        }

        if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        return ASPresentationAnchor(windowScene: windowScene)
    }
}

#Preview {
    NavigationStack {
        PlaidConnectionsView()
    }
    .modelContainer(SharedModelContainerFactory.makeInMemory())
}
