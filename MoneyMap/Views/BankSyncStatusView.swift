//
//  BankSyncStatusView.swift
//  MoneyMap
//
//  Created by Codex on 7/6/26.
//

import SwiftData
import SwiftUI

struct BankSyncStatusContainerView: View {
    @Environment(\.modelContext) private var mainModelContext
    private let plaidContainer: ModelContainer
    private let mode: BankSyncStatusMode

    init(mode: BankSyncStatusMode = .settings) {
        self.mode = mode
        do {
            plaidContainer = try PlaidSyncContainerFactory.make()
        } catch {
            plaidContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: "The Plaid sync store could not be opened: \(error.localizedDescription)")
        }
    }

    var body: some View {
        BankSyncStatusView(mainModelContext: mainModelContext, mode: mode)
            .modelContainer(plaidContainer)
    }
}

enum BankSyncStatusMode {
    case settings
    case cardUpgrade
}

struct PlaidConnectionValue: Identifiable, Hashable {
    let id: UUID
    let itemID: String
    let institutionID: String?
    let institutionName: String?
    let status: String?
    let lastSyncAt: Date?
    let errorMessage: String?

    init(_ connection: PlaidConnection) {
        id = connection.id
        itemID = connection.itemID
        institutionID = connection.institutionID
        institutionName = connection.institutionName
        status = connection.status
        lastSyncAt = connection.lastSyncAt
        errorMessage = connection.errorMessage
    }

    var isDisconnected: Bool {
        status?.localizedCaseInsensitiveContains("disconnect") == true
            || errorMessage?.localizedCaseInsensitiveContains("disconnected") == true
    }
}

struct PlaidAccountValue: Identifiable, Hashable {
    let id: UUID
    let accountID: String
    let itemID: String
    let institutionName: String?
    let accountName: String
    let officialName: String?
    let mask: String?
    let type: String
    let subtype: String?
    let currentBalance: Double?
    let availableBalance: Double?
    let currencyCode: String?
    let updatedAt: Date

    init(_ account: PlaidAccountSnapshot) {
        id = account.id
        accountID = account.accountID
        itemID = account.itemID
        institutionName = account.institutionName
        accountName = account.accountName
        officialName = account.officialName
        mask = account.mask
        type = account.type
        subtype = account.subtype
        currentBalance = account.currentBalance
        availableBalance = account.availableBalance
        currencyCode = account.currencyCode
        updatedAt = account.updatedAt
    }

    var displayName: String {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? (officialName ?? "Plaid Account") : trimmedName
    }

    var lastFourLabel: String? {
        guard let mask, !mask.isEmpty else { return nil }
        return "Ending \(mask)"
    }
}

struct BankSyncStatusView: View {
    let mainModelContext: ModelContext
    let mode: BankSyncStatusMode

    @Environment(\.modelContext) private var plaidModelContext
    @Query(sort: \PlaidConnection.updatedAt, order: .reverse) private var connections: [PlaidConnection]
    @Query(sort: \PlaidAccountSnapshot.accountName) private var accounts: [PlaidAccountSnapshot]
    @Query(sort: \PlaidTransactionReviewItem.updatedAt, order: .reverse) private var reviewItems: [PlaidTransactionReviewItem]
    @Query(sort: \PlaidSuggestion.updatedAt, order: .reverse) private var suggestions: [PlaidSuggestion]
    @State private var cloudStatusMessage: String?
    @State private var cloudErrorMessage: String?
    @State private var isRefreshingCloud = false
    @State private var importStatusMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImporting = false
    @State private var connectionSnapshots: [PlaidConnectionValue] = []
    @State private var accountSnapshots: [PlaidAccountValue] = []
    @State private var macRefreshCommand: PlaidMacRefreshCommand?
    @State private var isRequestingMacRefresh = false
    @State private var macRefreshStatusMessage: String?
    @State private var macRefreshErrorMessage: String?

    var body: some View {
        Group {
            switch mode {
            case .settings:
                settingsContent
            case .cardUpgrade:
                PlaidCardUpgradeView(
                    mainModelContext: mainModelContext,
                    connections: activeConnectionSnapshots,
                    accounts: activeAccountSnapshots
                )
            }
        }
        .task {
            loadSnapshotValues()
            await loadMacRefreshCommand()
        }
    }

    private var settingsContent: some View {
        List {
            bankSyncHeroSection
            bankSyncActionSection

            Section {
                NavigationLink {
                    PlaidCardUpgradeView(
                        mainModelContext: mainModelContext,
                        connections: activeConnectionSnapshots,
                        accounts: activeAccountSnapshots
                    )
                } label: {
                    BankSyncFeatureRow(
                        title: "Upgrade Cards",
                        detail: "Link Plaid cards to existing MoneyMap cards",
                        systemImage: "creditcard.and.123",
                        tint: MoneyMapDesign.calmGreen
                    )
                }
            } footer: {
                Text("Link synced Plaid cards to your existing MoneyMap credit-card bills without deleting your current schedules or history.")
            }

            Section {
                if activeConnectionSnapshots.isEmpty {
                    Label("No banks have synced from the Mac yet.", systemImage: "desktopcomputer")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeConnectionSnapshots) { connection in
                        PlaidConnectionSummaryRow(connection: connection)
                    }
                }
            } header: {
                Text("Connected Banks")
            } footer: {
                Text("Add or remove banks from MoneyMap for Mac. This phone receives synced snapshots only.")
            }
        }
        .navigationTitle("Bank Sync")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isRefreshingCloud || isImporting {
                    ProgressView()
                } else {
                    Button {
                        Task { await refreshFromCloud() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
                    }
                }
            }
        }
    }

    private var bankSyncHeroSection: some View {
        Section {
            BankSyncHeroCard(
                title: syncStatusTitle,
                detail: statusDetail,
                systemImage: syncStatusIcon,
                showsError: activeConnectionSnapshots.contains(where: { $0.errorMessage != nil }) || syncFreshness.level.isStale,
                banks: activeConnectionSnapshots.count,
                accounts: activeAccountSnapshots.count,
                ready: readyReviewItems.count
            )
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private var bankSyncActionSection: some View {
        Section {
            VStack(spacing: 10) {
                Button {
                    Task { await refreshFromCloud() }
                } label: {
                    MoneyMapActionCardLabel(
                        title: isRefreshingCloud ? "Refreshing" : "Refresh from Mac",
                        detail: syncFreshness.level.isStale ? "Download the latest Mac snapshot now." : "Download the latest Mac bank snapshot.",
                        systemImage: "icloud.and.arrow.down",
                        tint: .blue,
                        isProminent: syncFreshness.level.isStale
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingCloud)

                Button {
                    Task { await requestMacRefresh() }
                } label: {
                    MoneyMapActionCardLabel(
                        title: isRequestingMacRefresh ? "Requesting Mac Refresh" : "Tell Mac to Refresh",
                        detail: macRefreshCommandDetail,
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: MoneyMapDesign.calmGreen
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRequestingMacRefresh)

                if readyReviewItems.isEmpty {
                    MoneyMapStatusBanner(
                        message: "Transactions are current. No reviewed transactions are waiting.",
                        systemImage: "checkmark.circle.fill",
                        tint: MoneyMapDesign.calmGreen
                    )
                } else {
                    Button {
                        Task { await importReadyTransactions() }
                    } label: {
                        MoneyMapActionCardLabel(
                            title: isImporting ? "Importing Transactions" : "Import Transactions",
                            detail: "\(readyReviewItems.count) waiting for Wallet.",
                            systemImage: "square.and.arrow.down",
                            tint: MoneyMapDesign.warningGold,
                            isProminent: true
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                }

                bankSyncStatusMessages
            }
        } header: {
            Text("Sync")
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var bankSyncStatusMessages: some View {
        if let cloudStatusMessage {
            MoneyMapStatusBanner(message: cloudStatusMessage, systemImage: "icloud.and.arrow.down")
        }
        if let cloudErrorMessage {
            MoneyMapStatusBanner(message: cloudErrorMessage, systemImage: "exclamationmark.icloud", tint: MoneyMapDesign.attentionRed)
                .textSelection(.enabled)
        }
        if let macRefreshStatusMessage {
            MoneyMapStatusBanner(message: macRefreshStatusMessage, systemImage: "desktopcomputer")
        }
        if let macRefreshErrorMessage {
            MoneyMapStatusBanner(message: macRefreshErrorMessage, systemImage: "exclamationmark.triangle", tint: MoneyMapDesign.attentionRed)
                .textSelection(.enabled)
        }
        if let importStatusMessage {
            MoneyMapStatusBanner(message: importStatusMessage, systemImage: "checkmark.circle")
        }
        if let importErrorMessage {
            MoneyMapStatusBanner(message: importErrorMessage, systemImage: "exclamationmark.triangle", tint: MoneyMapDesign.attentionRed)
                .textSelection(.enabled)
        }
    }

    private var storageSection: some View {
        let report = PlaidSyncContainerFactory.lastReport

        return Section {
            Label(report.mode.displayName, systemImage: report.mode == .cloudKit ? "icloud" : "externaldrive.badge.exclamationmark")
                .foregroundStyle(report.mode == .cloudKit ? Color.primary : Color.orange)

            if let fallbackReason = report.fallbackReason {
                Text(fallbackReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Both Mac and iPhone must show iCloud sync here before bank data can move between devices.")
        }
    }

    private var cloudRefreshSection: some View {
        Section {
            if let cloudStatusMessage {
                Label(cloudStatusMessage, systemImage: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
            if let cloudErrorMessage {
                Label(cloudErrorMessage, systemImage: "exclamationmark.icloud")
                    .foregroundStyle(MoneyMapDesign.attentionRed)
                    .textSelection(.enabled)
            }
        } header: {
            Text("iCloud Refresh")
        }
    }

    private var lastSyncAt: Date? {
        activeConnectionSnapshots.compactMap(\.lastSyncAt).max()
    }

    private var syncFreshness: BankSyncFreshness {
        BankSyncFreshness(lastSyncAt: lastSyncAt)
    }

    private var connectionValues: [PlaidConnectionValue] {
        connections.map(PlaidConnectionValue.init)
    }

    private var activeConnectionSnapshots: [PlaidConnectionValue] {
        connectionSnapshots.filter { !$0.isDisconnected }
    }

    private var activeAccountSnapshots: [PlaidAccountValue] {
        let activeItemIDs = Set(activeConnectionSnapshots.map(\.itemID))
        return accountSnapshots
            .filter { activeItemIDs.isEmpty || activeItemIDs.contains($0.itemID) }
    }

    private var readyReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .ready }
    }

    private var importedReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .imported }
    }

    private var skippedReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .skipped }
    }

    private var readySuggestions: [PlaidSuggestion] {
        suggestions.filter { $0.status == .ready }
    }

    private var syncStatusTitle: String {
        if activeConnectionSnapshots.contains(where: { $0.errorMessage != nil }) {
            return "Mac sync needs attention"
        }
        if syncFreshness.level == .veryStale {
            return "Bank data is stale"
        }
        if syncFreshness.level == .stale {
            return "Bank data is getting old"
        }
        if lastSyncAt != nil {
            return "Bank sync is active"
        }
        return "Bank sync is connected"
    }

    private var syncStatusIcon: String {
        if activeConnectionSnapshots.contains(where: { $0.errorMessage != nil }) || syncFreshness.level.isStale {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    private var statusDetail: String {
        if let errorMessage = activeConnectionSnapshots.compactMap(\.errorMessage).first {
            return errorMessage
        }

        if let lastSyncAt {
            let synced = lastSyncAt.formatted(date: .abbreviated, time: .shortened)
            if syncFreshness.level.isStale {
                return "Last Mac sync was \(synced) (\(syncFreshness.ageLabel ?? "old")). Ask the Mac to refresh, then download the new snapshot."
            }
            return "Last synced from the Mac on \(synced)."
        }

        if activeConnectionSnapshots.isEmpty {
            return "Set up bank connections in MoneyMap for Mac. They will appear here after the Mac syncs to iCloud."
        }

        return "Waiting for the Mac to send the first bank sync snapshot."
    }

    private var macRefreshCommandDetail: String {
        guard let macRefreshCommand else {
            return "Queue a refresh command for MoneyMap for Mac"
        }

        switch macRefreshCommand.state {
        case .pending:
            return "Waiting for MoneyMap for Mac to pick it up"
        case .running:
            return "MoneyMap for Mac is refreshing now"
        case .completed:
            if let completedAt = macRefreshCommand.completedAt {
                return "Completed \(completedAt.formatted(date: .omitted, time: .shortened))"
            }
            return "The Mac completed the last refresh"
        case .failed:
            return macRefreshCommand.message ?? "The Mac could not complete the last refresh"
        }
    }

    private func loadSnapshotValues() {
        connectionSnapshots = connections.map(PlaidConnectionValue.init)
        accountSnapshots = accounts.map(PlaidAccountValue.init)
    }

    private func accountDetail(_ account: PlaidAccountSnapshot) -> String {
        var details: [String] = []
        if let lastFourLabel = account.lastFourLabel {
            details.append(lastFourLabel)
        }
        if let balance = account.currentBalance {
            details.append(balance.formatted(.currency(code: account.currencyCode ?? "USD")))
        }
        return details.joined(separator: " • ")
    }

    private func icon(for account: PlaidAccountSnapshot) -> String {
        switch account.subtype ?? account.type {
        case "credit card":
            return "creditcard"
        case "savings":
            return "banknote"
        case "checking":
            return "building.columns"
        default:
            return "dollarsign.circle"
        }
    }

    @MainActor
    private func refreshFromCloud() async {
        isRefreshingCloud = true
        cloudStatusMessage = nil
        cloudErrorMessage = nil
        defer { isRefreshingCloud = false }

        do {
            try await PlaidCloudSyncService.pull(context: plaidModelContext)
            loadSnapshotValues()
            await loadMacRefreshCommand()
            cloudStatusMessage = "Downloaded latest Plaid sync data."
        } catch {
            cloudErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func requestMacRefresh() async {
        isRequestingMacRefresh = true
        macRefreshStatusMessage = nil
        macRefreshErrorMessage = nil
        defer { isRequestingMacRefresh = false }

        do {
            macRefreshCommand = try await PlaidCloudSyncService.requestMacRefresh(source: "iPhone")
            macRefreshStatusMessage = "MoneyMap for Mac will refresh when it sees this request."
        } catch {
            macRefreshErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMacRefreshCommand() async {
        do {
            macRefreshCommand = try await PlaidCloudSyncService.latestMacRefreshCommand()
        } catch {
            macRefreshErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importReadyTransactions() async {
        isImporting = true
        importStatusMessage = nil
        importErrorMessage = nil
        defer { isImporting = false }

        do {
            let bills = try mainModelContext.fetch(FetchDescriptor<Bill>())
            let summary = try PlaidLocalSyncImporter.importReviewedItems(
                readyReviewItems,
                context: mainModelContext,
                bills: bills
            )
            try plaidModelContext.save()
            try await PlaidCloudSyncService.push(context: plaidModelContext)
            loadSnapshotValues()

            if summary.importedCount == 0 {
                importStatusMessage = "No new transactions were imported. \(summary.skippedCount) were already in MoneyMap."
            } else if summary.skippedCount == 0 {
                importStatusMessage = "Imported \(summary.importedCount) transactions."
            } else {
                importStatusMessage = "Imported \(summary.importedCount) transactions. Skipped \(summary.skippedCount) duplicates."
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct BankSyncHeroCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let showsError: Bool
    let banks: Int
    let accounts: Int
    let ready: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.16))
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                BankSyncHeroMetric(value: banks, title: "Banks")
                BankSyncHeroMetric(value: accounts, title: "Accounts")
                BankSyncHeroMetric(value: ready, title: "Ready")
            }
        }
        .padding(16)
        .background(showsError ? AnyShapeStyle(MoneyMapDesign.attentionRed.gradient) : AnyShapeStyle(MoneyMapDesign.moneyGradient))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BankSyncHeroMetric: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BankSyncMetric: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BankSyncFeatureRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 34)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaidConnectionSummaryRow: View {
    let connection: PlaidConnectionValue

    private var freshness: BankSyncFreshness {
        BankSyncFreshness(lastSyncAt: connection.lastSyncAt)
    }

    private var statusText: String? {
        if freshness.level.isStale {
            return "Stale"
        }
        return connection.status?.capitalized
    }

    private var statusColor: Color {
        if freshness.level == .veryStale || connection.errorMessage != nil {
            return MoneyMapDesign.attentionRed
        }
        if freshness.level == .stale {
            return MoneyMapDesign.warningGold
        }
        return MoneyMapDesign.calmGreen
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusColor.opacity(0.14))
                Image(systemName: "building.columns")
                    .font(.headline)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 38, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(connection.institutionName ?? "Plaid connection")
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let statusText {
                        Text(statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.12), in: Capsule())
                    }
                }

                if let lastSyncAt = connection.lastSyncAt {
                    Text(lastSyncLabel(for: lastSyncAt))
                        .font(.subheadline)
                        .foregroundStyle(freshness.level.isStale ? statusColor : .secondary)
                }

                if let errorMessage = connection.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(MoneyMapDesign.attentionRed)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func lastSyncLabel(for lastSyncAt: Date) -> String {
        let formatted = lastSyncAt.formatted(date: .abbreviated, time: .shortened)
        guard freshness.level.isStale else {
            return "Last synced \(formatted)"
        }
        return "Last synced \(formatted) - \(freshness.ageLabel ?? "stale")"
    }
}

private struct PlaidTransactionReviewPreviewRow: View {
    let reviewItem: PlaidTransactionReviewItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reviewItem.pending ? "clock" : "checkmark.circle")
                .foregroundStyle(reviewItem.pending ? Color.orange : Color.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(reviewItem.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(reviewItem.amount.formatted(.currency(code: reviewItem.currencyCode ?? "USD")))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var detailText: String {
        var parts: [String] = []
        if let date = reviewItem.date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let category = reviewItem.category, !category.isEmpty {
            parts.append(category)
        }
        return parts.joined(separator: " • ")
    }
}

private enum BankDataBrowserSection: String, CaseIterable, Identifiable {
    case overview
    case connections
    case accounts
    case transactions
    case imported
    case suggestions
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .connections: return "Connections"
        case .accounts: return "Accounts"
        case .transactions: return "Transactions"
        case .imported: return "Imported"
        case .suggestions: return "Suggestions"
        case .diagnostics: return "Diagnostics"
        }
    }
}

private enum BankDataTransactionFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case imported
    case skipped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .ready: return "Ready"
        case .imported: return "Imported"
        case .skipped: return "Skipped"
        }
    }
}

private struct BankDataBrowserView: View {
    let mainModelContext: ModelContext
    let connections: [PlaidConnection]
    let accounts: [PlaidAccountSnapshot]
    let reviewItems: [PlaidTransactionReviewItem]
    let suggestions: [PlaidSuggestion]

    @Environment(\.modelContext) private var plaidModelContext
    @State private var selectedSection: BankDataBrowserSection = .overview
    @State private var transactionFilter: BankDataTransactionFilter = .all
    @State private var importedTransactions: [Transaction] = []
    @State private var actionMessage: String?
    @State private var actionErrorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("View", selection: $selectedSection) {
                    ForEach(BankDataBrowserSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
            }

            if let actionMessage {
                Section {
                    Label(actionMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let actionErrorMessage {
                Section {
                    Label(actionErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(MoneyMapDesign.attentionRed)
                        .textSelection(.enabled)
                }
            }

            switch selectedSection {
            case .overview:
                overviewContent
            case .connections:
                connectionsContent
            case .accounts:
                accountsContent
            case .transactions:
                transactionsContent
            case .imported:
                importedContent
            case .suggestions:
                suggestionsContent
            case .diagnostics:
                diagnosticsContent
            }
        }
        .navigationTitle("Bank Data")
        .task {
            loadImportedTransactions()
        }
        .refreshable {
            loadImportedTransactions()
        }
    }

    private var overviewContent: some View {
        Group {
            Section("Summary") {
                LabeledContent("Connections", value: "\(connections.count)")
                LabeledContent("Accounts", value: "\(accounts.count)")
                LabeledContent("Ready transactions", value: "\(readyReviewItems.count)")
                LabeledContent("Imported transactions", value: "\(importedReviewItems.count)")
                LabeledContent("Suggestions", value: "\(readySuggestions.count)")
            }

            Section("Last Sync") {
                if let lastSyncAt {
                    LabeledContent("Mac sync", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                    if syncFreshness.level.isStale {
                        Label(
                            "This snapshot is \(syncFreshness.ageLabel ?? "stale"). Run Sync Now in MoneyMap for Mac, then refresh this screen.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(syncFreshness.level == .veryStale ? MoneyMapDesign.attentionRed : MoneyMapDesign.warningGold)
                    }
                } else {
                    Text("No Mac sync has reached this device yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connectionsContent: some View {
        Section("Connections") {
            if connections.isEmpty {
                Text("No bank connections have synced from the Mac yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(connections) { connection in
                    PlaidConnectionSummaryRow(connection: PlaidConnectionValue(connection))
                }
            }
        }
    }

    private var accountsContent: some View {
        Section("Accounts") {
            if accounts.isEmpty {
                Text("No account snapshots have synced yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accounts) { account in
                    PlaidAccountSnapshotRow(
                        account: account,
                        detail: accountDetail(account),
                        icon: icon(for: account)
                    )
                }
            }
        }
    }

    private var transactionsContent: some View {
        Group {
            Section {
                Picker("Status", selection: $transactionFilter) {
                    ForEach(BankDataTransactionFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            }

            Section("Transactions") {
                if filteredReviewItems.isEmpty {
                    Text("No transactions match this filter.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredReviewItems) { reviewItem in
                        PlaidTransactionReviewPreviewRow(reviewItem: reviewItem)
                    }
                }
            }
        }
    }

    private var importedContent: some View {
        Group {
            Section {
                if importedTransactions.isEmpty {
                    Text("No Plaid transactions are currently in MoneyMap's normal transaction history on this device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(importedTransactions.enumerated()), id: \.offset) { _, transaction in
                        ImportedMoneyMapTransactionRow(transaction: transaction)
                    }
                }
            } header: {
                Text("MoneyMap History")
            } footer: {
                Text("These are normal MoneyMap transactions with Plaid source IDs attached for duplicate protection.")
            }

            Section("Synced Import Audit") {
                if importedReviewItems.isEmpty {
                    Text("No imported review records have synced yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(importedReviewItems) { reviewItem in
                        PlaidTransactionReviewPreviewRow(reviewItem: reviewItem)
                    }
                }
            }
        }
    }

    private var suggestionsContent: some View {
        Section("Suggestions") {
            if readySuggestions.isEmpty {
                Text("No ready suggestions are waiting.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(readySuggestions) { suggestion in
                    PlaidSuggestionActionRow(
                        suggestion: suggestion,
                        account: accounts.first(where: { $0.accountID == suggestion.plaidAccountID }),
                        onAccept: { acceptSuggestion(suggestion) },
                        onSkip: { skipSuggestion(suggestion) }
                    )
                }
            }
        }
    }

    private var diagnosticsContent: some View {
        Group {
            Section("Storage") {
                let report = PlaidSyncContainerFactory.lastReport
                LabeledContent("Mode", value: report.mode.displayName)
                if let storeURL = report.storeURL {
                    Text(storeURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let fallbackReason = report.fallbackReason {
                    Text(fallbackReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Counts") {
                LabeledContent("Connections", value: "\(connections.count)")
                LabeledContent("Accounts", value: "\(accounts.count)")
                LabeledContent("Review records", value: "\(reviewItems.count)")
                LabeledContent("Suggestions", value: "\(suggestions.count)")
                LabeledContent("MoneyMap imports", value: "\(importedTransactions.count)")
            }

            Section("Connection Errors") {
                let erroredConnections = connections.filter { $0.errorMessage != nil }
                if erroredConnections.isEmpty {
                    Text("No connection errors are synced to this device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(erroredConnections) { connection in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.institutionName ?? "Plaid connection")
                                .font(.headline)
                            Text(connection.errorMessage ?? "Needs attention")
                                .font(.caption)
                                .foregroundStyle(MoneyMapDesign.attentionRed)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var readyReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .ready }
    }

    private var importedReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .imported }
    }

    private var skippedReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .skipped }
    }

    private var readySuggestions: [PlaidSuggestion] {
        suggestions.filter { $0.status == .ready }
    }

    private var filteredReviewItems: [PlaidTransactionReviewItem] {
        switch transactionFilter {
        case .all: return reviewItems
        case .ready: return readyReviewItems
        case .imported: return importedReviewItems
        case .skipped: return skippedReviewItems
        }
    }

    private var lastSyncAt: Date? {
        connections.compactMap(\.lastSyncAt).max()
    }

    private var syncFreshness: BankSyncFreshness {
        BankSyncFreshness(lastSyncAt: lastSyncAt)
    }

    private func accountDetail(_ account: PlaidAccountSnapshot) -> String {
        var details: [String] = []
        if let lastFourLabel = account.lastFourLabel {
            details.append(lastFourLabel)
        }
        if let balance = account.currentBalance {
            details.append(balance.formatted(.currency(code: account.currencyCode ?? "USD")))
        }
        return details.joined(separator: " • ")
    }

    private func icon(for account: PlaidAccountSnapshot) -> String {
        switch account.subtype ?? account.type {
        case "credit card":
            return "creditcard"
        case "savings":
            return "banknote"
        case "checking":
            return "building.columns"
        default:
            return "dollarsign.circle"
        }
    }

    private func loadImportedTransactions() {
        let transactions = (try? mainModelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        importedTransactions = transactions
            .filter { $0.plaidTransactionID != nil }
            .sorted { lhs, rhs in
                let lhsDate = lhs.transactionDate ?? lhs.clearingDate ?? .distantPast
                let rhsDate = rhs.transactionDate ?? rhs.clearingDate ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private func acceptSuggestion(_ suggestion: PlaidSuggestion) {
        actionMessage = nil
        actionErrorMessage = nil

        do {
            switch suggestion.kind {
            case .paymentMethod:
                try createPaymentMethod(from: suggestion)
            case .creditCardBill:
                try createCreditCardBill(from: suggestion)
            }
            suggestion.status = .imported
            try plaidModelContext.save()
            try mainModelContext.save()
            Task {
                try? await PlaidCloudSyncService.push(context: plaidModelContext)
            }
            actionMessage = "Accepted \(suggestion.title)."
            loadImportedTransactions()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func skipSuggestion(_ suggestion: PlaidSuggestion) {
        actionMessage = nil
        actionErrorMessage = nil

        do {
            suggestion.status = .skipped
            try plaidModelContext.save()
            Task {
                try? await PlaidCloudSyncService.push(context: plaidModelContext)
            }
            actionMessage = "Ignored \(suggestion.title)."
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func createPaymentMethod(from suggestion: PlaidSuggestion) throws {
        let paymentMethods = try mainModelContext.fetch(FetchDescriptor<PaymentMethod>())
        if paymentMethods.contains(where: { $0.plaidAccountID == suggestion.plaidAccountID }) {
            return
        }

        let account = accounts.first(where: { $0.accountID == suggestion.plaidAccountID })
        let paymentMethod = PaymentMethod(
            name: suggestion.title,
            type: paymentMethodType(for: account),
            institutionName: account?.institutionName,
            lastFourDigits: account?.mask,
            plaidAccountID: suggestion.plaidAccountID,
            plaidItemID: suggestion.plaidItemID,
            plaidUpdatedAt: .now
        )
        mainModelContext.insert(paymentMethod)
    }

    private func createCreditCardBill(from suggestion: PlaidSuggestion) throws {
        let bills = try mainModelContext.fetch(FetchDescriptor<Bill>())
        if bills.contains(where: { $0.plaidAccountID == suggestion.plaidAccountID }) {
            return
        }

        let bill = Bill(
            name: suggestion.title,
            amount: suggestion.amount,
            dueDate: suggestion.dueDate,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            notes: "Created from Bank Sync.",
            plaidAccountID: suggestion.plaidAccountID,
            plaidItemID: suggestion.plaidItemID,
            plaidUpdatedAt: .now
        )
        mainModelContext.insert(bill)
    }

    private func paymentMethodType(for account: PlaidAccountSnapshot?) -> PaymentMethodType {
        switch account?.subtype ?? account?.type ?? "" {
        case "credit card":
            return .creditCard
        case "checking":
            return .checking
        case "savings":
            return .savings
        default:
            return .other
        }
    }
}

private struct ImportedMoneyMapTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.plaidIsPending == true ? "clock" : "checkmark.circle")
                .foregroundStyle(transaction.plaidIsPending == true ? Color.orange : Color.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Transaction")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text((transaction.amountUSD ?? 0).formatted(.currency(code: "USD")))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var detailText: String {
        var parts: [String] = []
        if let date = transaction.transactionDate ?? transaction.clearingDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let category = transaction.category, !category.isEmpty {
            parts.append(category)
        }
        if let importedAt = transaction.plaidImportedAt {
            parts.append("Imported \(importedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " • ")
    }
}

private struct PlaidSuggestionActionRow: View {
    let suggestion: PlaidSuggestion
    let account: PlaidAccountSnapshot?
    let onAccept: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.kind == .creditCardBill ? "creditcard" : "building.columns")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.headline)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack {
                Button {
                    onAccept()
                } label: {
                    Label(acceptTitle, systemImage: "checkmark")
                }

                Button(role: .destructive) {
                    onSkip()
                } label: {
                    Label("Ignore", systemImage: "xmark")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var acceptTitle: String {
        suggestion.kind == .creditCardBill ? "Create Bill" : "Create Payment Method"
    }

    private var detailText: String {
        var parts: [String] = []
        if let detail = suggestion.detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let account {
            parts.append(account.subtype ?? account.type)
        }
        if let amount = suggestion.amount {
            parts.append(amount.formatted(.currency(code: account?.currencyCode ?? "USD")))
        }
        if let dueDate = suggestion.dueDate {
            parts.append("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " • ")
    }
}

private struct PlaidCardUpgradeView: View {
    let mainModelContext: ModelContext
    let connections: [PlaidConnectionValue]
    let accounts: [PlaidAccountValue]

    @State private var bills: [Bill] = []
    @State private var paymentMethods: [PaymentMethod] = []
    @State private var selectedBillIDsByAccountID: [String: UUID] = [:]
    @State private var actionMessage: String?
    @State private var actionErrorMessage: String?
    @State private var didRevealHeader = false
    @State private var hasLoadedData = false

    var body: some View {
        List {
            if !hasLoadedData {
                Section {
                    ProgressView("Preparing card upgrades")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }

            Section {
                PlaidCardUpgradeHero(
                    readyCount: unlinkedPlaidCreditAccounts.count,
                    linkedCount: linkedCreditCards.count,
                    manualCount: unlinkedManualCreditCards.count,
                    isRevealed: didRevealHeader
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if hasLoadedData {
                if let actionMessage {
                    Section {
                        PlaidUpgradeFeedbackBanner(
                            message: actionMessage,
                            systemImage: "checkmark.circle.fill",
                            tint: MoneyMapDesign.calmGreen
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                if let actionErrorMessage {
                    Section {
                        PlaidUpgradeFeedbackBanner(
                            message: actionErrorMessage,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: MoneyMapDesign.attentionRed
                        )
                        .textSelection(.enabled)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                Section {
                    if unlinkedPlaidCreditAccounts.isEmpty {
                        ContentUnavailableView(
                            "No Cards Waiting",
                            systemImage: "checkmark.circle",
                            description: Text("Linked cards and manual-only cards are listed below.")
                        )
                    } else {
                        ForEach(unlinkedPlaidCreditAccounts) { account in
                            PlaidCardUpgradeAccountRow(
                                account: account,
                                candidateBills: unlinkedManualCreditCards,
                                selectedBillID: bindingForSelectedBill(account),
                                suggestedBill: suggestedBill(for: account),
                                link: { linkSelectedBill(to: account) },
                                create: { createCard(from: account) }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .scale(scale: 0.96).combined(with: .opacity)
                            ))
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                } header: {
                    Text("Ready to Upgrade")
                } footer: {
                    Text("Linking does not delete your custom card. It upgrades that same card with Plaid account identity so future bank transactions import into the existing card view.")
                }

                Section("Linked Cards") {
                    if linkedCreditCards.isEmpty {
                        Text("No MoneyMap cards are linked to Plaid yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedCreditCards) { bill in
                            PlaidLinkedCardRow(
                                bill: bill,
                                account: plaidCreditAccounts.first(where: { $0.accountID == bill.plaidAccountID }),
                                unlink: { unlink(bill) }
                            )
                        }
                    }
                }

                Section {
                    if unlinkedManualCreditCards.isEmpty {
                        Text("All MoneyMap credit cards are either linked or no manual card bills exist.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unlinkedManualCreditCards) { bill in
                            PlaidManualCardRow(bill: bill)
                        }
                    }
                } header: {
                    Text("Manual Cards")
                } footer: {
                    Text("Keep a card manual if Plaid does not support it, or if you still want to import that card's transaction history by file.")
                }

                Section("How It Works") {
                    Label("Existing card bill stays in place", systemImage: "checkmark.circle")
                    Label("Future Plaid imports attach to the linked card", systemImage: "arrow.down.doc")
                    Label("Already imported Plaid transactions move onto the linked card", systemImage: "arrow.triangle.merge")
                    Label("Manual transaction history stays visible", systemImage: "clock.arrow.circlepath")
                    Label("You can unlink without deleting the card", systemImage: "link.badge.minus")
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Upgrade Cards")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .safeAreaPadding(.bottom, 96)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: unlinkedPlaidCreditAccounts.count)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: linkedCreditCards.count)
        .animation(.snappy(duration: 0.25), value: actionMessage)
        .animation(.snappy(duration: 0.25), value: actionErrorMessage)
        .task {
            await Task.yield()
            loadMoneyMapData()
            seedSuggestedMatches()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                hasLoadedData = true
                didRevealHeader = true
            }
        }
        .refreshable {
            loadMoneyMapData()
            seedSuggestedMatches()
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
    }

    private var plaidCreditAccounts: [PlaidAccountValue] {
        accounts.filter { account in
            account.type == "credit" || account.subtype == "credit card"
        }
    }

    private var creditCardBills: [Bill] {
        bills.filter { $0.category == .creditCard }
    }

    private var linkedCreditCards: [Bill] {
        creditCardBills.filter { bill in
            guard let plaidAccountID = bill.plaidAccountID else { return false }
            return !plaidAccountID.isEmpty
        }
    }

    private var unlinkedManualCreditCards: [Bill] {
        creditCardBills.filter { bill in
            (bill.plaidAccountID ?? "").isEmpty && !bill.plaidUnavailable
        }
    }

    private var unlinkedPlaidCreditAccounts: [PlaidAccountValue] {
        let linkedAccountIDs = Set(linkedCreditCards.compactMap(\.plaidAccountID))
        return plaidCreditAccounts.filter { !linkedAccountIDs.contains($0.accountID) }
    }

    private func loadMoneyMapData() {
        bills = (try? mainModelContext.fetch(FetchDescriptor<Bill>())) ?? []
        paymentMethods = (try? mainModelContext.fetch(FetchDescriptor<PaymentMethod>())) ?? []
    }

    private func seedSuggestedMatches() {
        for account in unlinkedPlaidCreditAccounts where selectedBillIDsByAccountID[account.accountID] == nil {
            if let bill = suggestedBill(for: account) {
                selectedBillIDsByAccountID[account.accountID] = bill.id
            }
        }
    }

    private func bindingForSelectedBill(_ account: PlaidAccountValue) -> Binding<UUID?> {
        Binding(
            get: { selectedBillIDsByAccountID[account.accountID] },
            set: { selectedBillIDsByAccountID[account.accountID] = $0 }
        )
    }

    private func suggestedBill(for account: PlaidAccountValue) -> Bill? {
        if let mask = normalizedLastFour(account.mask),
           let exactLastFour = unlinkedManualCreditCards.first(where: { normalizedLastFour($0.creditCardDetails?.lastFourDigits) == mask }) {
            return exactLastFour
        }

        let accountName = normalizedMatchText(account.displayName)
        let institutionName = normalizedMatchText(account.institutionName)
        return unlinkedManualCreditCards
            .map { bill -> (bill: Bill, score: Int) in
                var score = 0
                let billName = normalizedMatchText(bill.name)
                let issuerName = normalizedMatchText(bill.creditCardDetails?.issuerName)
                if !accountName.isEmpty, billName.contains(accountName) || accountName.contains(billName) {
                    score += 3
                }
                if !institutionName.isEmpty, issuerName.contains(institutionName) || institutionName.contains(issuerName) {
                    score += 2
                }
                return (bill, score)
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .first?
            .bill
    }

    private func linkSelectedBill(to account: PlaidAccountValue) {
        actionMessage = nil
        actionErrorMessage = nil

        guard let selectedBillID = selectedBillIDsByAccountID[account.accountID],
              let bill = bills.first(where: { $0.id == selectedBillID }) else {
            actionErrorMessage = "Choose the MoneyMap card to link first."
            return
        }

        do {
            upgrade(bill, with: account)
            try attachExistingTransactions(for: account.accountID, to: bill)
            syncPaymentMethods()
            try mainModelContext.save()
            withAnimation {
                loadMoneyMapData()
                seedSuggestedMatches()
                actionMessage = "\(bill.name ?? "Card") now uses Plaid data from \(account.displayName)."
            }
        } catch {
            withAnimation {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func createCard(from account: PlaidAccountValue) {
        actionMessage = nil
        actionErrorMessage = nil

        do {
            let details = creditCardDetails(from: account, existing: nil)
            let bill = Bill(
                name: account.displayName,
                amount: account.currentBalance,
                dueDate: nil,
                category: .creditCard,
                recurrenceInterval: 1,
                recurrenceUnit: .month,
                creditCardDetails: details,
                notes: "Created from Bank Sync.",
                plaidAccountID: account.accountID,
                plaidItemID: account.itemID,
                plaidInstitutionID: connection(for: account)?.institutionID,
                plaidUpdatedAt: .now
            )
            mainModelContext.insert(bill)
            bills.append(bill)
            try attachExistingTransactions(for: account.accountID, to: bill)
            syncPaymentMethods()
            try mainModelContext.save()
            withAnimation {
                loadMoneyMapData()
                actionMessage = "Created \(account.displayName) as a Plaid-linked card."
            }
        } catch {
            withAnimation {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func unlink(_ bill: Bill) {
        actionMessage = nil
        actionErrorMessage = nil

        do {
            let name = bill.name ?? "Card"
            bill.plaidAccountID = nil
            bill.plaidItemID = nil
            bill.plaidInstitutionID = nil
            bill.plaidUpdatedAt = .now
            bill.plaidUnavailable = false
            syncPaymentMethods()
            try mainModelContext.save()
            withAnimation {
                loadMoneyMapData()
                actionMessage = "\(name) is now manual again. Existing transactions were not deleted."
            }
        } catch {
            withAnimation {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func upgrade(_ bill: Bill, with account: PlaidAccountValue) {
        bill.plaidAccountID = account.accountID
        bill.plaidItemID = account.itemID
        bill.plaidInstitutionID = connection(for: account)?.institutionID
        bill.plaidUpdatedAt = .now
        bill.plaidUnavailable = false
        bill.creditCardDetails = creditCardDetails(from: account, existing: bill.creditCardDetails)

        if (bill.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bill.name = account.displayName
        }
    }

    private func attachExistingTransactions(for plaidAccountID: String, to bill: Bill) throws {
        let transactions = try mainModelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions where transaction.plaidAccountID == plaidAccountID {
            transaction.creditCard = bill
        }
    }

    private func creditCardDetails(from account: PlaidAccountValue, existing: CreditCardDetails?) -> CreditCardDetails {
        let currentBalance = account.currentBalance ?? existing?.cardBalance ?? 0
        let estimatedLimit = estimatedCreditLimit(for: account, existing: existing)
        return CreditCardDetails(
            creditLimit: estimatedLimit,
            cardBalance: currentBalance,
            annualPercentageRate: existing?.annualPercentageRate,
            minimumPayment: existing?.minimumPayment,
            statementBalance: existing?.statementBalance,
            issuerName: account.institutionName ?? existing?.issuerName,
            lastFourDigits: account.mask ?? existing?.lastFourDigits,
            statementClosingDate: existing?.statementClosingDate,
            promoAPRExpiration: existing?.promoAPRExpiration
        )
    }

    private func estimatedCreditLimit(for account: PlaidAccountValue, existing: CreditCardDetails?) -> Double {
        let current = account.currentBalance ?? 0
        let available = account.availableBalance ?? 0
        let plaidEstimate = current + max(available, 0)
        return max(existing?.creditLimit ?? 0, plaidEstimate, current, 0)
    }

    private func syncPaymentMethods() {
        _ = PaymentMethodSyncService.syncCreditCardPaymentMethods(
            bills: bills,
            paymentMethods: paymentMethods,
            context: mainModelContext
        )
    }

    private func connection(for account: PlaidAccountValue) -> PlaidConnectionValue? {
        connections.first(where: { $0.itemID == account.itemID })
    }

    private func normalizedLastFour(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : String(digits.suffix(4))
    }

    private func normalizedMatchText(_ value: String?) -> String {
        value?
            .lowercased()
            .replacingOccurrences(of: "credit card", with: "")
            .replacingOccurrences(of: "card", with: "")
            .filter { $0.isLetter || $0.isNumber }
            ?? ""
    }
}

private struct PlaidCardUpgradeHero: View {
    let readyCount: Int
    let linkedCount: Int
    let manualCount: Int
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.16))
                    Image(systemName: "creditcard.and.123")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: linkedCount)
                }
                .frame(width: 56, height: 48)
                .scaleEffect(isRevealed ? 1 : 0.92)
                .opacity(isRevealed ? 1 : 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready to upgrade cards")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Match Plaid cards to cards you already use. Bills, reminders, and manual history stay in place.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                PlaidUpgradeMetric(value: readyCount, title: "Ready")
                PlaidUpgradeMetric(value: linkedCount, title: "Linked")
                PlaidUpgradeMetric(value: manualCount, title: "Manual")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MoneyMapDesign.moneyGradient)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
        .offset(y: isRevealed ? 0 : 10)
        .opacity(isRevealed ? 1 : 0)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaidUpgradeMetric: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PlaidUpgradeFeedbackBanner: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(message)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .symbolEffect(.bounce, value: message)
        }
        .foregroundStyle(tint)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaidCardUpgradeAccountRow: View {
    let account: PlaidAccountValue
    let candidateBills: [Bill]
    @Binding var selectedBillID: UUID?
    let suggestedBill: Bill?
    let link: () -> Void
    let create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MoneyMapDesign.calmGreen.opacity(0.16))
                    Image(systemName: "creditcard")
                        .font(.headline)
                        .foregroundStyle(MoneyMapDesign.calmGreen)
                }
                .frame(width: 44, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if !detailText.isEmpty {
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            if let suggestedBill {
                Label("Suggested match: \(suggestedBill.name ?? "Card")", systemImage: "sparkle.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MoneyMapDesign.calmGreen.opacity(0.12), in: Capsule())
            }

            if candidateBills.isEmpty {
                Label("No manual MoneyMap cards are available to link.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MoneyMap Card")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedBillName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    Picker("MoneyMap Card", selection: $selectedBillID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(candidateBills) { bill in
                            Text(cardLabel(for: bill)).tag(Optional(bill.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    link()
                } label: {
                    Label("Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .disabled(selectedBillID == nil)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(MoneyMapDesign.calmGreen)
                .foregroundStyle(.white)

                Button {
                    create()
                } label: {
                    Label("Create", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MoneyMapDesign.surfaceBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .animation(.snappy(duration: 0.2), value: selectedBillID)
    }

    private var detailText: String {
        var parts: [String] = []
        if let institution = account.institutionName, !institution.isEmpty {
            parts.append(institution)
        }
        if let lastFourLabel = account.lastFourLabel {
            parts.append(lastFourLabel)
        }
        if let balance = account.currentBalance {
            parts.append("Balance \(balance.formatted(.currency(code: account.currencyCode ?? "USD")))")
        }
        if let available = account.availableBalance {
            parts.append("Available \(available.formatted(.currency(code: account.currencyCode ?? "USD")))")
        }
        return parts.joined(separator: " • ")
    }

    private var selectedBillName: String {
        guard let selectedBillID,
              let bill = candidateBills.first(where: { $0.id == selectedBillID }) else {
            return "Choose Card"
        }
        return bill.name ?? "Card"
    }

    private func cardLabel(for bill: Bill) -> String {
        var parts = [bill.name ?? "Card"]
        if let lastFour = bill.creditCardDetails?.lastFourDigits, !lastFour.isEmpty {
            parts.append("Ending \(lastFour)")
        }
        return parts.joined(separator: " • ")
    }
}

private struct PlaidLinkedCardRow: View {
    let bill: Bill
    let account: PlaidAccountValue?
    let unlink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(Color.green)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bill.name ?? "Card")
                        .font(.headline)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button(role: .destructive) {
                unlink()
            } label: {
                Label("Unlink Plaid", systemImage: "link.badge.minus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var detailText: String {
        var parts: [String] = []
        if let account {
            parts.append(account.displayName)
            if let lastFourLabel = account.lastFourLabel {
                parts.append(lastFourLabel)
            }
        } else if let plaidAccountID = bill.plaidAccountID {
            parts.append("Plaid account \(plaidAccountID)")
        }
        if let updatedAt = bill.plaidUpdatedAt {
            parts.append("Linked \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " • ")
    }
}

private struct PlaidManualCardRow: View {
    let bill: Bill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard")
                .foregroundStyle(Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(bill.name ?? "Card")
                    .font(.headline)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var detailText: String {
        var parts: [String] = ["Manual"]
        if let lastFour = bill.creditCardDetails?.lastFourDigits, !lastFour.isEmpty {
            parts.append("Ending \(lastFour)")
        }
        if let balance = bill.creditCardDetails?.cardBalance {
            parts.append("Balance \(balance.formatted(.currency(code: "USD")))")
        }
        return parts.joined(separator: " • ")
    }
}
