//
//  WalletView.swift
//  MoneyMap
//
//  Created by Codex on 7/7/26.
//

import SwiftData
import SwiftUI
import TipKit

struct WalletView: View {
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @Query private var bills: [Bill]
    @Query(sort: \Transaction.transactionDate, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @AppStorage(RecurringBillDetector.ignoredSuggestionIDsKey) private var ignoredRecurringBillSuggestionIDs = ""

    private let plaidContainer: ModelContainer

    @State private var destination: WalletDestination?
    @State private var viewingBill: Bill?
    @State private var isRefreshingBankData = false
    @State private var refreshSummary: WalletRefreshSummary?
    @State private var refreshErrorMessage: String?
    @State private var refreshDismissTask: Task<Void, Never>?
    @State private var plaidConnectionSnapshots: [PlaidConnectionValue] = []
    @State private var plaidAccountSnapshots: [PlaidAccountValue] = []
    @State private var recurringReviewSuggestions: [RecurringBillSuggestion] = []
    @State private var recurringReviewRefreshTask: Task<Void, Never>?

    init() {
        do {
            plaidContainer = try PlaidSyncContainerFactory.make()
        } catch {
            plaidContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: "Wallet could not open the Plaid sync store: \(error.localizedDescription)")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                refreshFeedbackSection
                destinationCardsSection
            }
            .navigationTitle("Wallet")
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .refreshable {
                await refreshBankData()
            }
            .navigationDestination(item: $destination, destination: destinationView)
            .navigationDestination(item: $viewingBill) { bill in
                BillView(bill: bill)
            }
            .onAppear {
                MoneyMapDiagnostics.record(
                    "wallet.appear",
                    metadata: [
                        "bills": "\(bills.count)",
                        "transactions": "\(transactions.count)",
                        "cachedRecurringSuggestions": "\(recurringReviewSuggestions.count)"
                    ]
                )
                consumeDeepLinks()
                loadPlaidSnapshots()
                scheduleRecurringReviewRefresh()
            }
            .onChange(of: deepLinkManager.requestedBillID) { _, _ in
                consumeDeepLinks()
            }
            .onChange(of: deepLinkManager.requestedBillsDestination) { _, _ in
                consumeDeepLinks()
            }
            .onChange(of: bills.count) { _, _ in
                consumeDeepLinks()
                scheduleRecurringReviewRefresh()
            }
            .onChange(of: transactions.count) { _, _ in
                scheduleRecurringReviewRefresh()
            }
            .onChange(of: ignoredRecurringBillSuggestionIDs) { _, _ in
                scheduleRecurringReviewRefresh()
            }
        }
    }

    private var summarySection: some View {
        Section {
            WalletOverviewCard(
                cards: creditCards.count,
                linkedCards: linkedCards.count,
                accounts: nonCreditPlaidAccounts.count,
                transactions: plaidImportedTransactions.count,
                balance: bills.totalBalance,
                limit: bills.totalCreditLimit
            )

            TipView(WalletRefreshTip())
        } header: {
            Text("Overview")
        } footer: {
            Text("Cards, synced bank data, payment methods, and imported transactions in one place.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var refreshFeedbackSection: some View {
        if isRefreshingBankData || refreshSummary != nil || refreshErrorMessage != nil {
            Section {
                WalletRefreshStatusNotice(
                    isRefreshing: isRefreshingBankData,
                    summary: refreshSummary,
                    errorMessage: refreshErrorMessage,
                    dismiss: dismissRefreshFeedback
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var destinationCardsSection: some View {
        Section {
            LazyVGrid(columns: destinationColumns, spacing: 12) {
                Button {
                    destination = .cards
                } label: {
                    WalletDestinationTile(
                        title: "Cards",
                        detail: cardsDestinationDetail,
                        systemImage: "creditcard.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())

                Button {
                    destination = .accounts
                } label: {
                    WalletDestinationTile(
                        title: "Accounts",
                        detail: accountsDestinationDetail,
                        systemImage: "building.columns.fill",
                        tint: MoneyMapDesign.calmGreen
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())

                Button {
                    destination = .transactions
                } label: {
                    WalletDestinationTile(
                        title: "Activity",
                        detail: transactionsDestinationDetail,
                        systemImage: "list.bullet.rectangle.fill",
                        tint: .purple
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())

                Button {
                    destination = .bills
                } label: {
                    WalletDestinationTile(
                        title: "Bills",
                        detail: billsDestinationDetail,
                        systemImage: "calendar.badge.clock",
                        tint: MoneyMapDesign.warningGold
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())

                Button {
                    destination = .paymentMethods
                } label: {
                    WalletDestinationTile(
                        title: "Payments",
                        detail: paymentMethodsDestinationDetail,
                        systemImage: "wallet.pass.fill",
                        tint: .blue
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())

                Button {
                    destination = .recurringBills
                } label: {
                    WalletDestinationTile(
                        title: "Recurring",
                        detail: recurringDestinationDetail,
                        systemImage: "repeat.circle.fill",
                        tint: MoneyMapDesign.calmGreen
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())

                Button {
                    destination = .bankSyncSettings
                } label: {
                    WalletDestinationTile(
                        title: "Sync",
                        detail: bankSyncDestinationDetail,
                        systemImage: "icloud.and.arrow.down.fill",
                        tint: MoneyMapDesign.brandGreen
                    )
                }
                .buttonStyle(WalletDestinationTileButtonStyle())
            }
            .padding(.vertical, 2)
        } header: {
            Text("Explore")
                .padding(.leading, 28)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var manageSection: some View {
        Section("Manage") {
            NavigationLink {
                destinationView(.bills)
            } label: {
                WalletActionRow(
                    title: "Bills",
                    detail: billsSummary,
                    systemImage: "calendar.badge.clock",
                    tint: MoneyMapDesign.warningGold
                )
            }

            NavigationLink {
                destinationView(.paymentMethods)
            } label: {
                WalletActionRow(
                    title: "Payment Methods",
                    detail: paymentMethodSummary,
                    systemImage: "creditcard.and.123",
                    tint: .blue
                )
            }

            NavigationLink {
                WalletAccountsView(
                    accounts: nonCreditPlaidAccounts,
                    plaidAccounts: plaidAccountSnapshots
                )
            } label: {
                WalletActionRow(
                    title: "Accounts",
                    detail: accountSummary,
                    systemImage: "building.columns",
                    tint: MoneyMapDesign.calmGreen
                )
            }

            NavigationLink {
                destinationView(.transactions)
            } label: {
                WalletActionRow(
                    title: "All Transactions",
                    detail: transactionSummary,
                    systemImage: "list.bullet.rectangle",
                    tint: .purple
                )
            }

            NavigationLink {
                destinationView(.recurringBills)
            } label: {
                WalletActionRow(
                    title: "Recurring & Subscriptions",
                    detail: recurringReviewSummary,
                    systemImage: "repeat",
                    tint: MoneyMapDesign.calmGreen
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var accountsSection: some View {
        if !nonCreditPlaidAccounts.isEmpty {
            ForEach(accountInstitutionGroups) { group in
                Section {
                    ForEach(group.accounts) { account in
                        NavigationLink {
                            WalletAccountDetailView(
                                account: account,
                                plaidAccounts: plaidAccountSnapshots
                            )
                        } label: {
                            WalletAccountRow(
                                account: account,
                                transactionCount: transactionCount(for: account)
                            )
                        }
                    }
                } header: {
                    Text(accountInstitutionGroups.count == 1 ? "Accounts" : group.title)
                } footer: {
                    if group.id == accountInstitutionGroups.last?.id {
                        Text("Synced checking, debit, savings, investment, and other non-credit accounts from Bank Sync.")
                    }
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
        }
    }

    @ViewBuilder
    private var cardUpgradeCalloutSection: some View {
        if !unlinkedPlaidCreditAccounts.isEmpty {
            Section {
                Button {
                    destination = .cardUpgrade
                } label: {
                    WalletCardUpgradeCallout(
                        plaidCards: unlinkedPlaidCreditAccounts.count,
                        manualCards: manualCardsAvailableForUpgrade.count,
                        linkedCards: linkedCards.count
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MoneyMapDesign.moneyGradient)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private var recurringBillReviewCalloutSection: some View {
        if !recurringReviewSuggestions.isEmpty {
            Section {
                Button {
                    openRecurringReview()
                } label: {
                    WalletRecurringBillCallout(suggestions: recurringReviewSuggestions)
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MoneyMapDesign.moneyGradient)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var cardsSection: some View {
        Section {
            if creditCards.isEmpty {
                ContentUnavailableView(
                    "No Cards Yet",
                    systemImage: "creditcard",
                    description: Text("Cards you add manually or connect through Plaid will appear here.")
                )
            } else {
                ForEach(creditCards) { card in
                    Button {
                        viewingBill = card
                    } label: {
                        WalletCardRow(card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Cards")
        } footer: {
            if !manualCardsAvailableForUpgrade.isEmpty {
                Text("\(manualCardsAvailableForUpgrade.count) manual card\(manualCardsAvailableForUpgrade.count == 1 ? "" : "s") can still be linked when a matching Plaid account is available.")
            } else if !manualCards.isEmpty {
                Text("Manual-only cards stay in Wallet without showing upgrade prompts.")
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var transactionsSection: some View {
        Section("Recent Transactions") {
            if recentTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Imported bank transactions will appear here after you review them from Bank Sync.")
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        destinationView(.transactions)
                    } label: {
                        Label("Open All Transactions", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            } else {
                ForEach(recentTransactions, id: \.self) { transaction in
                    NavigationLink {
                        WalletTransactionDetailView(
                            transaction: transaction,
                            plaidAccounts: plaidAccountSnapshots
                        )
                    } label: {
                        WalletTransactionRow(transaction: transaction)
                    }
                }

                if transactions.count > recentTransactions.count {
                    NavigationLink {
                        destinationView(.transactions)
                    } label: {
                        Label("View All Transactions", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var destinationColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var creditCards: [Bill] {
        bills.creditCards.sorted(by: Bill.byStatusDateUtilization)
    }

    private var linkedCards: [Bill] {
        creditCards.filter { $0.plaidAccountID?.isEmpty == false }
    }

    private var manualCards: [Bill] {
        creditCards.filter { $0.plaidAccountID?.isEmpty != false }
    }

    private var manualCardsAvailableForUpgrade: [Bill] {
        manualCards.filter { !$0.plaidUnavailable }
    }

    private var activePlaidAccountSnapshots: [PlaidAccountValue] {
        let activeItemIDs = Set(plaidConnectionSnapshots.filter { !$0.isDisconnected }.map(\.itemID))
        return plaidAccountSnapshots.filter { account in
            activeItemIDs.isEmpty || activeItemIDs.contains(account.itemID)
        }
    }

    private var nonCreditPlaidAccounts: [PlaidAccountValue] {
        activePlaidAccountSnapshots
            .filter { !isCreditAccount($0) }
            .sorted { lhs, rhs in
                let lhsInstitution = lhs.institutionName ?? ""
                let rhsInstitution = rhs.institutionName ?? ""
                if lhsInstitution.localizedCaseInsensitiveCompare(rhsInstitution) == .orderedSame {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhsInstitution.localizedCaseInsensitiveCompare(rhsInstitution) == .orderedAscending
            }
    }

    private var accountInstitutionGroups: [WalletAccountInstitutionGroup] {
        WalletAccountGrouping.groups(for: nonCreditPlaidAccounts)
    }

    private var unlinkedPlaidCreditAccounts: [PlaidAccountValue] {
        let linkedAccountIDs = Set(linkedCards.compactMap(\.plaidAccountID))
        return activePlaidAccountSnapshots.filter { account in
            isCreditAccount(account)
                && !linkedAccountIDs.contains(account.accountID)
        }
    }

    private var recentTransactions: [Transaction] {
        Array(transactions.prefix(8))
    }

    private var recentActivityTransactions: [Transaction] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantFuture
        return transactions.filter { transactionDate(for: $0) >= cutoff }
    }

    private var recentActivitySpend: Double {
        recentActivityTransactions.reduce(0) { total, transaction in
            total + max(transaction.amountUSD ?? 0, 0)
        }
    }

    private var plaidImportedTransactions: [Transaction] {
        transactions.filter { $0.plaidTransactionID?.isEmpty == false }
    }

    private var cardUtilizationText: String {
        bills.creditCardUtilization.formatted(.percent.precision(.fractionLength(0)))
    }

    private func compactCurrencyString(for amount: Double) -> String {
        let absoluteAmount = abs(amount)
        let prefix = amount < 0 ? "-$" : "$"

        if absoluteAmount >= 1_000_000 {
            let value = absoluteAmount / 1_000_000
            let digits = absoluteAmount < 10_000_000 ? 1 : 0
            return "\(prefix)\(value.formatted(.number.precision(.fractionLength(digits))))M"
        }

        if absoluteAmount >= 1_000 {
            let value = absoluteAmount / 1_000
            let digits = absoluteAmount < 10_000 ? 1 : 0
            return "\(prefix)\(value.formatted(.number.precision(.fractionLength(digits))))K"
        }

        return "\(prefix)\(absoluteAmount.formatted(.number.precision(.fractionLength(0))))"
    }

    private var billsSummary: String {
        let activeBills = bills.withoutCreditCards.filter { $0.lifecycleState == .active }
        if activeBills.isEmpty {
            return "Open your full bills view"
        }

        return "\(activeBills.count) active - \(MoneyMapFormatters.currencyString(for: activeBills.totalAmount)) tracked"
    }

    private var bankSyncSummary: String {
        if linkedCards.isEmpty && plaidImportedTransactions.isEmpty {
            return "Connect banks and upgrade cards"
        }

        let cardText = "\(linkedCards.count) linked card\(linkedCards.count == 1 ? "" : "s")"
        let transactionText = "\(plaidImportedTransactions.count) imported transaction\(plaidImportedTransactions.count == 1 ? "" : "s")"
        return "\(cardText) - \(transactionText)"
    }

    private var paymentMethodSummary: String {
        if paymentMethods.isEmpty {
            return "Add accounts and cards used to pay bills"
        }

        let mirroredCards = paymentMethods.filter(\.isCreditCardMirror).count
        if mirroredCards > 0 {
            return "\(paymentMethods.count) saved - \(mirroredCards) managed from cards"
        }

        return "\(paymentMethods.count) saved method\(paymentMethods.count == 1 ? "" : "s")"
    }

    private var accountSummary: String {
        if nonCreditPlaidAccounts.isEmpty {
            return "Synced checking, debit, savings, and investment accounts"
        }

        let importedTransactionCount = nonCreditPlaidAccounts.reduce(0) { count, account in
            count + transactionCount(for: account)
        }
        return "\(nonCreditPlaidAccounts.count) synced - \(importedTransactionCount) transaction\(importedTransactionCount == 1 ? "" : "s")"
    }

    private var transactionSummary: String {
        if transactions.isEmpty {
            return "No imported history yet"
        }

        return "\(transactions.count) total - \(plaidImportedTransactions.count) from Plaid"
    }

    private var recurringReviewSummary: String {
        if !recurringReviewSuggestions.isEmpty {
            return "\(recurringReviewSuggestions.count) ready to review"
        }

        let ignoredCount = ignoredRecurringBillSuggestionIDs.split(separator: "|").count
        if ignoredCount > 0 {
            return "\(ignoredCount) ignored - review recurring charges"
        }

        return "Review detected bills and subscriptions"
    }

    private var cardsDestinationDetail: String {
        if creditCards.isEmpty {
            return "Add cards"
        }

        if !unlinkedPlaidCreditAccounts.isEmpty {
            return "\(unlinkedPlaidCreditAccounts.count) to link"
        }

        return "\(compactCurrencyString(for: bills.totalBalance)) • \(cardUtilizationText)"
    }

    private var accountsDestinationDetail: String {
        if nonCreditPlaidAccounts.isEmpty {
            return "Add banks"
        }

        let institutionCount = Set(nonCreditPlaidAccounts.compactMap { $0.institutionName?.nilIfBlank }).count
        let bankText = institutionCount == 1 ? "1 bank" : "\(institutionCount) banks"
        return "\(bankText) • \(nonCreditPlaidAccounts.count)"
    }

    private var transactionsDestinationDetail: String {
        if !recentActivityTransactions.isEmpty {
            return "30d \(recentActivityTransactions.count) • \(compactCurrencyString(for: recentActivitySpend))"
        }

        if transactions.isEmpty {
            return "No history"
        }

        return "\(transactions.count) total • 0 recent"
    }

    private var billsDestinationDetail: String {
        let activeBills = bills.withoutCreditCards.filter { $0.lifecycleState == .active }
        guard !activeBills.isEmpty else {
            return "Track upcoming bills"
        }

        let unpaidBills = activeBills.filter { $0.status != .paid }
        let needsAttention = activeBills.filter { bill in
            bill.status != .paid && billNeedsAttentionPreview(bill)
        }
        if !needsAttention.isEmpty {
            return "\(needsAttention.count) action • \(compactCurrencyString(for: unpaidBills.totalAmount))"
        }

        if unpaidBills.isEmpty {
            return "\(activeBills.count) active • paid"
        }

        return "\(unpaidBills.count) due • \(compactCurrencyString(for: unpaidBills.totalAmount))"
    }

    private var paymentMethodsDestinationDetail: String {
        if paymentMethods.isEmpty {
            return "Add method"
        }

        let mirroredCards = paymentMethods.filter(\.isCreditCardMirror).count
        if mirroredCards > 0 {
            return "\(paymentMethods.count) saved • \(mirroredCards) cards"
        }

        return "\(paymentMethods.count) saved"
    }

    private var recurringDestinationDetail: String {
        if !recurringReviewSuggestions.isEmpty {
            return "\(recurringReviewSuggestions.count) to review"
        }

        return "Scanning charges"
    }

    private var bankSyncDestinationDetail: String {
        if isRefreshingBankData {
            return "Refreshing"
        }

        if !unlinkedPlaidCreditAccounts.isEmpty {
            return "\(unlinkedPlaidCreditAccounts.count) to link"
        }

        if !activePlaidAccountSnapshots.isEmpty {
            let bankCount = plaidConnectionSnapshots.filter { !$0.isDisconnected }.count
            return "\(bankCount) bank\(bankCount == 1 ? "" : "s") • \(activePlaidAccountSnapshots.count)"
        }

        return "Connect banks"
    }

    @ViewBuilder
    private func destinationView(_ destination: WalletDestination) -> some View {
        switch destination {
        case .cards:
            WalletCardsView(cards: creditCards)
        case .accounts:
            WalletAccountsView(
                accounts: nonCreditPlaidAccounts,
                plaidAccounts: plaidAccountSnapshots
            )
        case .bills:
            BillsHome()
        case .paymentMethods:
            PaymentMethodsView()
        case .transactions:
            WalletTransactionsView(plaidAccounts: plaidAccountSnapshots)
        case .cardUtilization:
            CardUtilizationView()
        case .bankSyncSettings:
            BankSyncStatusContainerView(mode: .settings)
        case .cardUpgrade:
            BankSyncStatusContainerView(mode: .cardUpgrade)
        case .recurringBills:
            RecurringBillReviewView(
                initialSuggestions: recurringReviewSuggestions,
                initialPlaidAccounts: plaidAccountSnapshots
            )
        }
    }

    private func consumeDeepLinks() {
        if let requestedBillID = deepLinkManager.requestedBillID,
           let targetBill = bills.first(where: { $0.id == requestedBillID }) {
            viewingBill = targetBill
            deepLinkManager.requestedBillID = nil
        }

        guard let requestedDestination = deepLinkManager.requestedBillsDestination else {
            return
        }

        switch requestedDestination {
        case .upcomingBills:
            destination = .bills
        case .cardUtilization:
            destination = .cardUtilization
        }
        deepLinkManager.requestedBillsDestination = nil
    }

    private func transactionDate(for transaction: Transaction) -> Date {
        transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt ?? .distantPast
    }

    private func transactionTitle(for transaction: Transaction) -> String {
        transaction.friendlyName?.nilIfBlank
            ?? transaction.merchant?.nilIfBlank
            ?? transaction.transactionDescription?.nilIfBlank
            ?? "Transaction"
    }

    private func billNeedsAttentionPreview(_ bill: Bill) -> Bool {
        guard bill.lifecycleState == .active else { return false }
        guard bill.status != .paid else { return false }
        guard let dueDate = bill.dueDate else { return true }

        let today = Calendar.current.startOfDay(for: .now)
        let dueDay = Calendar.current.startOfDay(for: dueDate)
        if dueDay < today {
            return true
        }
        if dueDay == today {
            return !bill.autopayEnabled
        }
        return false
    }

    private func isCreditAccount(_ account: PlaidAccountValue) -> Bool {
        account.type.localizedCaseInsensitiveCompare("credit") == .orderedSame
            || account.subtype?.localizedCaseInsensitiveCompare("credit card") == .orderedSame
    }

    private func transactionCount(for account: PlaidAccountValue) -> Int {
        transactions.filter { $0.plaidAccountID == account.accountID }.count
    }

    private func recurringDetectionDate(for transaction: Transaction) -> Date? {
        transaction.transactionDate ?? transaction.clearingDate
    }

    private func openRecurringReview() {
        MoneyMapDiagnostics.record(
            "wallet.recurringCard.tap",
            metadata: [
                "bills": "\(bills.count)",
                "transactions": "\(transactions.count)",
                "cachedRecurringSuggestions": "\(recurringReviewSuggestions.count)"
            ]
        )
        refreshRecurringReviewSuggestions()
        destination = .recurringBills
        MoneyMapDiagnostics.record(
            "wallet.recurringCard.destinationSet",
            metadata: ["refreshedSuggestions": "\(recurringReviewSuggestions.count)"]
        )
    }

    private func scheduleRecurringReviewRefresh() {
        recurringReviewRefreshTask?.cancel()
        MoneyMapDiagnostics.record(
            "wallet.recurringRefresh.schedule",
            metadata: [
                "bills": "\(bills.count)",
                "transactions": "\(transactions.count)"
            ]
        )
        recurringReviewRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            refreshRecurringReviewSuggestions()
        }
    }

    private func refreshRecurringReviewSuggestions() {
        let start = Date()
        let ignoredIDs = Set(ignoredRecurringBillSuggestionIDs.split(separator: "|").map(String.init))
        let cutoff = Calendar.current.date(byAdding: .month, value: -18, to: .now) ?? .distantPast
        let recentTransactions = Array(transactions.lazy
            .filter { transaction in
                guard let detectionDate = recurringDetectionDate(for: transaction) else {
                    return false
                }
                return detectionDate >= cutoff
            }
            .prefix(5_000)
            .map { $0 })

        let detected = MoneyMapDiagnostics.measure(
            "wallet.recurringDetect",
            metadata: [
                "bills": "\(bills.count)",
                "transactions": "\(recentTransactions.count)"
            ]
        ) {
            RecurringBillDetector.detect(transactions: recentTransactions, existingBills: bills)
        }
        let suggestions = detected
            .filter { !ignoredIDs.contains($0.id) }
        recurringReviewSuggestions = suggestions
        MoneyMapDiagnostics.record(
            "wallet.recurringRefresh.complete",
            metadata: [
                "durationMs": MoneyMapDiagnostics.durationMilliseconds(since: start),
                "inputTransactions": "\(recentTransactions.count)",
                "suggestions": "\(suggestions.count)"
            ]
        )
    }

    @MainActor
    private func refreshBankData() async {
        refreshDismissTask?.cancel()
        refreshDismissTask = nil
        withAnimation(.snappy(duration: 0.2)) {
            isRefreshingBankData = true
            refreshSummary = nil
            refreshErrorMessage = nil
        }

        do {
            let context = ModelContext(plaidContainer)
            try await PlaidCloudSyncService.pull(context: context)
            loadPlaidSnapshots(context: context)
            let summary = makeRefreshSummary(context: context)
            withAnimation(.snappy(duration: 0.25)) {
                refreshSummary = summary
            }
            scheduleRefreshFeedbackDismissal()
        } catch {
            withAnimation(.snappy(duration: 0.25)) {
                refreshErrorMessage = error.localizedDescription
            }
        }

        withAnimation(.snappy(duration: 0.2)) {
            isRefreshingBankData = false
        }
    }

    @MainActor
    private func dismissRefreshFeedback() {
        refreshDismissTask?.cancel()
        refreshDismissTask = nil
        withAnimation(.snappy(duration: 0.2)) {
            refreshSummary = nil
            refreshErrorMessage = nil
        }
    }

    @MainActor
    private func scheduleRefreshFeedbackDismissal() {
        refreshDismissTask?.cancel()
        refreshDismissTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.snappy(duration: 0.25)) {
                    refreshSummary = nil
                }
                refreshDismissTask = nil
            }
        }
    }

    @MainActor
    private func loadPlaidSnapshots(context: ModelContext? = nil) {
        let context = context ?? ModelContext(plaidContainer)
        plaidConnectionSnapshots = ((try? context.fetch(FetchDescriptor<PlaidConnection>())) ?? [])
            .map(PlaidConnectionValue.init)
        plaidAccountSnapshots = ((try? context.fetch(FetchDescriptor<PlaidAccountSnapshot>())) ?? [])
            .map(PlaidAccountValue.init)
    }

    @MainActor
    private func makeRefreshSummary(context: ModelContext) -> WalletRefreshSummary {
        let connections = ((try? context.fetch(FetchDescriptor<PlaidConnection>())) ?? [])
            .filter { !PlaidConnectionValue($0).isDisconnected }
        let accounts = (try? context.fetch(FetchDescriptor<PlaidAccountSnapshot>())) ?? []
        let reviewItems = ((try? context.fetch(FetchDescriptor<PlaidTransactionReviewItem>())) ?? [])
            .filter { $0.status == .ready }
        let suggestions = ((try? context.fetch(FetchDescriptor<PlaidSuggestion>())) ?? [])
            .filter { $0.status == .ready }

        return WalletRefreshSummary(
            refreshedAt: .now,
            connectionCount: connections.count,
            accountCount: accounts.count,
            readyTransactionCount: reviewItems.count,
            readySuggestionCount: suggestions.count,
            unlinkedPlaidCardCount: unlinkedPlaidCreditAccounts.count
        )
    }
}

private enum WalletDestination: Hashable, Identifiable {
    case cards
    case accounts
    case bills
    case paymentMethods
    case transactions
    case cardUtilization
    case bankSyncSettings
    case cardUpgrade
    case recurringBills

    var id: Self { self }
}

private struct WalletRefreshSummary: Equatable {
    let refreshedAt: Date
    let connectionCount: Int
    let accountCount: Int
    let readyTransactionCount: Int
    let readySuggestionCount: Int
    let unlinkedPlaidCardCount: Int

    var reviewItemCount: Int {
        readyTransactionCount + readySuggestionCount
    }

    var compactStatusText: String {
        if reviewItemCount == 0 && unlinkedPlaidCardCount == 0 {
            return "Up to date at \(refreshedAtText)"
        }
        return "Refreshed at \(refreshedAtText)"
    }

    var secondaryDetail: String? {
        if reviewItemCount == 0 && unlinkedPlaidCardCount == 0 {
            return "\(connectionCount) bank\(connectionCount == 1 ? "" : "s") - \(accountCount) account\(accountCount == 1 ? "" : "s")"
        }

        let bankText = "\(connectionCount) bank\(connectionCount == 1 ? "" : "s")"
        let accountText = "\(accountCount) account\(accountCount == 1 ? "" : "s")"
        let reviewText = "\(reviewItemCount) ready to review"
        let upgradeText = unlinkedPlaidCardCount > 0
            ? " - \(unlinkedPlaidCardCount) card\(unlinkedPlaidCardCount == 1 ? "" : "s") to upgrade"
            : ""
        return "\(bankText) - \(accountText) - \(reviewText)\(upgradeText)"
    }

    var refreshedAtText: String {
        refreshedAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct WalletRefreshStatusNotice: View {
    let isRefreshing: Bool
    let summary: WalletRefreshSummary?
    let errorMessage: String?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if !isRefreshing {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss refresh status")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
        } else if errorMessage != nil {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(MoneyMapDesign.attentionRed)
        } else {
            Image(systemName: summary == nil ? "icloud.and.arrow.down" : "checkmark.icloud")
                .foregroundStyle(summary == nil ? .secondary : MoneyMapDesign.calmGreen)
        }
    }

    private var title: String {
        if isRefreshing {
            return "Checking for bank updates..."
        }
        if errorMessage != nil {
            return "Bank refresh failed"
        }
        return summary?.compactStatusText ?? "Bank data refreshed"
    }

    private var detail: String? {
        if isRefreshing {
            return "Downloading the latest snapshot from iCloud."
        }
        if let errorMessage {
            return errorMessage
        }
        return summary?.secondaryDetail
    }

    private var titleColor: Color {
        errorMessage == nil ? .primary : MoneyMapDesign.attentionRed
    }
}

private struct WalletOverviewCard: View {
    let cards: Int
    let linkedCards: Int
    let accounts: Int
    let transactions: Int
    let balance: Double
    let limit: Double

    private var utilization: Double {
        guard limit > 0 else { return 0 }
        return balance / limit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Card Balance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(MoneyMapFormatters.currencyString(for: balance))
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Utilization")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(utilization.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                }
            }

            Divider()

            HStack(spacing: 10) {
                WalletCompactMetric(title: "Cards", value: "\(cards)", detail: "\(linkedCards) linked", systemImage: "creditcard", tint: .blue)
                WalletCompactMetric(title: "Accounts", value: "\(accounts)", detail: "Synced", systemImage: "building.columns", tint: MoneyMapDesign.calmGreen)
                WalletCompactMetric(title: "Imports", value: "\(transactions)", detail: "Plaid", systemImage: "arrow.down.doc", tint: .purple)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct WalletCompactMetric: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WalletMetric: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .tint(tint)
    }
}

private struct WalletActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WalletDestinationTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    private let cardCornerRadius: CGFloat = 24
    private let iconCornerRadius: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                    .fill(tint.opacity(0.14))

                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 46, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 142, maxHeight: 142, alignment: .topLeading)
        .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct WalletDestinationTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private struct WalletCardUpgradeCallout: View {
    let plaidCards: Int
    let manualCards: Int
    let linkedCards: Int

    var body: some View {
        WalletAnnouncementCard(
            title: title,
            detail: detail,
            systemImage: "creditcard.and.123",
            actionTitle: "Upgrade",
            stats: [
                WalletAnnouncementStat(value: "\(plaidCards)", title: "Ready"),
                WalletAnnouncementStat(value: "\(linkedCards)", title: "Linked"),
                WalletAnnouncementStat(value: "\(manualCards)", title: "Manual")
            ]
        )
    }

    private var title: String {
        return "Ready to upgrade cards"
    }

    private var detail: String {
        "Match Plaid cards to the MoneyMap cards you already use."
    }
}

private struct WalletRecurringBillCallout: View {
    let suggestions: [RecurringBillSuggestion]

    var body: some View {
        WalletAnnouncementCard(
            title: title,
            detail: detail,
            systemImage: "repeat",
            actionTitle: "Review",
            stats: [
                WalletAnnouncementStat(value: "\(suggestions.count)", title: "Found"),
                WalletAnnouncementStat(value: "\(highConfidenceCount)", title: "High"),
                WalletAnnouncementStat(value: monthlyTotalText, title: "Monthly")
            ]
        )
    }

    private var title: String {
        "\(suggestions.count) recurring charge\(suggestions.count == 1 ? "" : "s") found"
    }

    private var detail: String {
        "Review detected subscriptions and repeating bills from imported transactions."
    }

    private var highConfidenceCount: Int {
        suggestions.filter { $0.confidence >= 0.86 }.count
    }

    private var monthlyTotalText: String {
        let total = suggestions
            .filter { $0.cadence == .monthly }
            .reduce(0) { $0 + $1.amount }
        return MoneyMapFormatters.currencyString(for: total)
    }
}

private struct WalletAnnouncementCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String
    let stats: [WalletAnnouncementStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.16))
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 36)

                Spacer()

                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.deepMoneyGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.86), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                ForEach(stats) { stat in
                    WalletCalloutChip(value: stat.value, title: stat.title)
                }
            }
        }
        .padding(16)
        .background(MoneyMapDesign.moneyGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct WalletAnnouncementStat: Identifiable {
    let value: String
    let title: String

    var id: String { "\(title)-\(value)" }
}

private struct WalletCalloutChip: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
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

private struct WalletCardRow: View {
    let card: Bill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.plaidAccountID?.isEmpty == false ? "link.circle.fill" : "creditcard")
                .foregroundStyle(card.plaidAccountID?.isEmpty == false ? MoneyMapDesign.calmGreen : .blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(card.name ?? "Credit Card")
                        .font(.headline)
                        .lineLimit(1)

                    if card.plaidAccountID?.isEmpty == false {
                        Text("Linked")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MoneyMapDesign.calmGreen)
                    }
                }

                Text(cardDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(MoneyMapFormatters.currencyString(for: card.creditCardDetails?.cardBalance ?? card.amount ?? 0))
                    .font(.headline)
                    .monospacedDigit()

                Text(card.displayStatusName)
                    .font(.caption)
                    .foregroundStyle(card.displayStatusColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var cardDetail: String {
        let details = card.creditCardDetails
        let lastFour = details?.lastFourDigits.map { "Ending \($0)" }
        let limit = details.map { MoneyMapFormatters.currencyString(for: $0.creditLimit) + " limit" }
        let issuer = details?.issuerName

        return [issuer, lastFour, limit]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }
}

private struct WalletCardsView: View {
    let cards: [Bill]

    var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Cards",
                    systemImage: "creditcard",
                    description: Text("Cards you add manually or connect through Plaid will appear here.")
                )
            } else {
                Section {
                    ForEach(cards) { card in
                        NavigationLink {
                            BillView(bill: card)
                        } label: {
                            WalletCardRow(card: card)
                        }
                    }
                } header: {
                    Text("\(cards.count) Card\(cards.count == 1 ? "" : "s")")
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
        }
        .navigationTitle("Cards")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
}

private struct WalletTransactionRow: View {
    let transaction: Transaction
    var leadingSymbolName: String?
    var leadingSymbolColor: Color?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: leadingSymbolName ?? defaultLeadingSymbolName)
                .foregroundStyle(leadingSymbolColor ?? defaultLeadingSymbolColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Transaction")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(MoneyMapFormatters.currencyString(for: transaction.amountUSD ?? 0))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle((transaction.amountUSD ?? 0) < 0 ? MoneyMapDesign.calmGreen : .primary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var isPlaidImported: Bool {
        transaction.plaidTransactionID?.isEmpty == false
            || transaction.plaidAccountID?.isEmpty == false
            || transaction.plaidImportedAt != nil
    }

    private var defaultLeadingSymbolName: String {
        isPlaidImported ? "arrow.down.circle" : "list.bullet.circle"
    }

    private var defaultLeadingSymbolColor: Color {
        isPlaidImported ? MoneyMapDesign.calmGreen : .secondary
    }

    private var detail: String {
        let date = (transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt)
            .map(MoneyMapFormatters.mediumDateString(for:)) ?? "Unknown date"
        let category = transaction.category ?? "Uncategorized"
        let card = transaction.creditCard?.name

        return [category, card, date]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }
}

private enum WalletTransactionSourceFilter: String, CaseIterable, Identifiable {
    case all
    case plaid
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Sources"
        case .plaid: return "Plaid Imports"
        case .other: return "Manual or CSV"
        }
    }
}

private enum WalletTransactionStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case posted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Statuses"
        case .pending: return "Pending"
        case .posted: return "Posted"
        }
    }
}

private struct WalletTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]

    let plaidAccounts: [PlaidAccountValue]

    @State private var searchText = ""
    @State private var searchTokens: [WalletTransactionSearchToken] = []
    @State private var suggestedSearchTokens: [WalletTransactionSearchToken] = []
    @State private var selectedCardFilterID: String?
    @State private var selectedPlaidInstitutionFilterName: String?
    @State private var selectedPlaidAccountFilterID: String?
    @State private var selectedTypeGroupFilter: String?
    @State private var selectedTypeFilter: String?
    @State private var selectedCategoryGroupFilter: String?
    @State private var selectedCategoryFilter: String?
    @State private var sourceFilter: WalletTransactionSourceFilter = .all
    @State private var statusFilter: WalletTransactionStatusFilter = .all
    @State private var showingFilterSheet = false
    @State private var isUpdatingSearchTokens = false
    @State private var isSelecting = false
    @State private var selectedTransactionIDs = Set<PersistentIdentifier>()
    @State private var transactionPendingDeletion: Transaction?
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var deletionErrorMessage: String?

    private let noCardFilterID = "__moneymap_no_card__"
    private let noPlaidAccountFilterID = "__moneymap_no_plaid_account__"
    private let noTypeFilterValue = "__moneymap_no_type__"
    private let noCategoryFilterValue = "__moneymap_no_category__"

    private var sortedTransactions: [Transaction] {
        transactions.sorted { lhs, rhs in
            transactionDate(for: lhs) > transactionDate(for: rhs)
        }
    }

    private var visibleTransactions: [Transaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sortedTransactions.filter { transaction in
            matchesSelectedFilters(transaction)
                && matchesSearchTokens(transaction)
                && (query.isEmpty || searchableText(for: transaction).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            if let deletionErrorMessage {
                Section {
                    Label(deletionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MoneyMapDesign.attentionRed)
                        .textSelection(.enabled)
                }
            }

            if hasActiveFilters {
                filterSummarySection
            }

            if transactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Imported Plaid and card transactions will appear here.")
                )
            } else if visibleTransactions.isEmpty {
                ContentUnavailableView(
                    "No Matching Transactions",
                    systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
                    description: Text(hasActiveFilters ? "Clear a filter or search term to see more transactions." : "Try a different merchant, category, card, or amount.")
                )
            } else {
                Section {
                    ForEach(visibleTransactions, id: \.persistentModelID) { transaction in
                        transactionRow(for: transaction)
                    }
                } header: {
                    Text(transactionListHeader)
                } footer: {
                    Text(isSelecting ? "Selected transactions can be deleted together from MoneyMap." : "Swipe a test or duplicate import to delete it from MoneyMap.")
                }
            }
        }
        .navigationTitle("Transactions")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .searchable(
            text: $searchText,
            tokens: $searchTokens,
            suggestedTokens: $suggestedSearchTokens,
            prompt: Text("Search transactions")
        ) { token in
            Label(token.title, systemImage: token.systemImage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterButton

                Button(isSelecting ? "Done" : "Select") {
                    toggleSelectionMode()
                }
                .disabled(visibleTransactions.isEmpty && !isSelecting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            WalletTransactionFilterSheet(
                selectedCardFilterID: $selectedCardFilterID,
                selectedPlaidInstitutionFilterName: $selectedPlaidInstitutionFilterName,
                selectedPlaidAccountFilterID: $selectedPlaidAccountFilterID,
                selectedTypeGroupFilter: $selectedTypeGroupFilter,
                selectedTypeFilter: $selectedTypeFilter,
                selectedCategoryGroupFilter: $selectedCategoryGroupFilter,
                selectedCategoryFilter: $selectedCategoryFilter,
                sourceFilter: $sourceFilter,
                statusFilter: $statusFilter,
                cardOptions: cardFilterOptions,
                plaidAccountOptions: plaidAccountFilterOptions,
                typeOptions: typeFilterOptions,
                categoryOptions: categoryFilterOptions,
                hasActiveFilters: hasActiveFilters,
                activeFilterSummary: activeFilterSummary,
                clearFilters: {
                    clearFilters()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            syncFilterSearchTokens()
            refreshSearchSuggestions()
        }
        .animation(.default, value: isSelecting)
        .onChange(of: searchText) { _, _ in
            pruneSelectionToVisibleTransactions()
            refreshSearchSuggestions()
        }
        .onChange(of: searchTokens) { oldValue, newValue in
            handleSearchTokensChanged(from: oldValue, to: newValue)
        }
        .onChange(of: selectedCardFilterID) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: selectedPlaidInstitutionFilterName) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: selectedPlaidAccountFilterID) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: selectedTypeGroupFilter) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: selectedTypeFilter) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: selectedCategoryGroupFilter) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: selectedCategoryFilter) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: sourceFilter) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: statusFilter) { _, _ in
            pruneSelectionToVisibleTransactions()
            syncFilterSearchTokens()
        }
        .onChange(of: transactions.count) { _, _ in
            pruneSelectionToExistingTransactions()
            syncFilterSearchTokens()
            refreshSearchSuggestions()
        }
        .confirmationDialog(
            "Delete transaction?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Transaction", role: .destructive) {
                if let transactionPendingDeletion {
                    delete(transactionPendingDeletion)
                }
                transactionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                transactionPendingDeletion = nil
            }
        } message: {
            Text("This removes the imported transaction from MoneyMap. It does not delete any bill or Plaid connection.")
        }
        .confirmationDialog(
            "Delete selected transactions?",
            isPresented: $showingBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedTransactionCount) Transaction\(selectedTransactionCount == 1 ? "" : "s")", role: .destructive) {
                deleteSelectedTransactions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected transactions from MoneyMap. It does not delete any bills, cards, or Plaid connections.")
        }
    }

    private var transactionListHeader: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasActiveFilters {
            return "\(sortedTransactions.count) Transaction\(sortedTransactions.count == 1 ? "" : "s")"
        }

        return "\(visibleTransactions.count) Match\(visibleTransactions.count == 1 ? "" : "es")"
    }

    private var filterSummarySection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label {
                    Text(activeFilterSummary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(MoneyMapDesign.calmGreen)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("Clear") {
                    clearFilters()
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 2)
        }
    }

    private var filterButton: some View {
        Button {
            showingFilterSheet = true
        } label: {
            Label(hasActiveFilters ? "Filters On" : "Filter", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                Button(allVisibleTransactionsSelected ? "Clear" : "Select All") {
                    toggleSelectAllVisibleTransactions()
                }
                .disabled(visibleTransactions.isEmpty)

                Spacer(minLength: 8)

                Text("\(selectedTransactionCount) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    showingBulkDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedTransactionIDs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func transactionRow(for transaction: Transaction) -> some View {
        if isSelecting {
            Button {
                toggleSelection(for: transaction)
            } label: {
                WalletTransactionRow(
                    transaction: transaction,
                    leadingSymbolName: selectedTransactionIDs.contains(transaction.persistentModelID) ? "checkmark.circle.fill" : "circle",
                    leadingSymbolColor: selectedTransactionIDs.contains(transaction.persistentModelID) ? MoneyMapDesign.calmGreen : .secondary
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityAddTraits(selectedTransactionIDs.contains(transaction.persistentModelID) ? [.isButton, .isSelected] : .isButton)
        } else {
            NavigationLink {
                WalletTransactionDetailView(
                    transaction: transaction,
                    plaidAccounts: plaidAccounts
                )
            } label: {
                WalletTransactionRow(transaction: transaction)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    confirmDelete(transaction)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    confirmDelete(transaction)
                } label: {
                    Label("Delete Transaction", systemImage: "trash")
                }
            }
        }
    }

    private var cardsForFilter: [Bill] {
        var seenCardIDs = Set<UUID>()
        return transactions
            .compactMap(\.creditCard)
            .filter { seenCardIDs.insert($0.id).inserted }
            .sorted {
                ($0.name?.nilIfBlank ?? "Card").localizedCaseInsensitiveCompare($1.name?.nilIfBlank ?? "Card") == .orderedAscending
            }
    }

    private var plaidAccountsForFilter: [PlaidAccountValue] {
        let referencedAccountIDs = Set(transactions.compactMap { $0.plaidAccountID?.nilIfBlank })
        return plaidAccounts
            .filter { referencedAccountIDs.contains($0.accountID) }
            .sorted {
                plaidAccountFilterLabel(for: $0).localizedCaseInsensitiveCompare(plaidAccountFilterLabel(for: $1)) == .orderedAscending
            }
    }

    private var plaidAccountIDsWithoutSnapshot: [String] {
        let knownAccountIDs = Set(plaidAccounts.map(\.accountID))
        let referencedAccountIDs = Set(transactions.compactMap { $0.plaidAccountID?.nilIfBlank })
        return referencedAccountIDs
            .filter { !knownAccountIDs.contains($0) }
            .sorted()
    }

    private var typeFilters: [String] {
        distinctValues(transactions.compactMap { $0.type?.nilIfBlank })
    }

    private var categoryFilters: [String] {
        distinctValues(transactions.compactMap { $0.category?.nilIfBlank })
    }

    private var cardFilterOptions: [WalletFilterOption] {
        var options = cardsForFilter.map { card in
            WalletFilterOption(
                id: card.id.uuidString,
                title: card.name?.nilIfBlank ?? "Card",
                subtitle: card.creditCardDetails?.issuerName?.nilIfBlank
            )
        }

        if hasTransactionsWithoutCards {
            options.append(WalletFilterOption(id: noCardFilterID, title: "No Card"))
        }

        return options
    }

    private var plaidAccountFilterOptions: [WalletFilterOption] {
        var options = plaidAccountsForFilter.map { account in
            let institutionName = account.institutionName?.nilIfBlank ?? "Unknown Institution"
            return WalletFilterOption(
                id: account.accountID,
                title: accountFilterTitle(for: account),
                subtitle: [account.lastFourLabel?.nilIfBlank, account.type.capitalized.nilIfBlank, account.subtype?.nilIfBlank]
                    .compactMap { $0 }
                    .joined(separator: " - ")
                    .nilIfBlank,
                sectionTitle: institutionName,
                groupID: institutionName,
                groupTitle: institutionName
            )
        }

        options.append(contentsOf: plaidAccountIDsWithoutSnapshot.map { accountID in
            WalletFilterOption(
                id: accountID,
                title: orphanPlaidAccountLabel(for: accountID),
                sectionTitle: "Unknown Institution"
            )
        })

        if hasTransactionsWithoutPlaidAccounts {
            options.append(WalletFilterOption(id: noPlaidAccountFilterID, title: "No Plaid Account", sectionTitle: "Other"))
        }

        return options
    }

    private var typeFilterOptions: [WalletFilterOption] {
        var options = typeFilters.map { value in
            let hierarchy = filterHierarchy(for: value)
            return WalletFilterOption(
                id: value,
                title: hierarchy.title,
                subtitle: hierarchy.group == nil ? nil : value,
                sectionTitle: hierarchy.group,
                groupID: hierarchy.group,
                groupTitle: hierarchy.group
            )
        }

        if hasTransactionsWithoutTypes {
            options.append(WalletFilterOption(id: noTypeFilterValue, title: "No Type", sectionTitle: "Other"))
        }

        return options
    }

    private var categoryFilterOptions: [WalletFilterOption] {
        var options = categoryFilters.map { value in
            let hierarchy = filterHierarchy(for: value)
            return WalletFilterOption(
                id: value,
                title: hierarchy.title,
                subtitle: hierarchy.group == nil ? nil : value,
                sectionTitle: hierarchy.group,
                groupID: hierarchy.group,
                groupTitle: hierarchy.group
            )
        }

        if hasTransactionsWithoutCategories {
            options.append(WalletFilterOption(id: noCategoryFilterValue, title: "Uncategorized", sectionTitle: "Other"))
        }

        return options
    }

    private var hasTransactionsWithoutCards: Bool {
        transactions.contains { $0.creditCard == nil }
    }

    private var hasTransactionsWithoutPlaidAccounts: Bool {
        transactions.contains { $0.plaidAccountID?.nilIfBlank == nil }
    }

    private var hasTransactionsWithoutTypes: Bool {
        transactions.contains { $0.type?.nilIfBlank == nil }
    }

    private var hasTransactionsWithoutCategories: Bool {
        transactions.contains { $0.category?.nilIfBlank == nil }
    }

    private var hasActiveFilters: Bool {
        selectedCardFilterID != nil
            || selectedPlaidInstitutionFilterName != nil
            || selectedPlaidAccountFilterID != nil
            || selectedTypeGroupFilter != nil
            || selectedTypeFilter != nil
            || selectedCategoryGroupFilter != nil
            || selectedCategoryFilter != nil
            || sourceFilter != .all
            || statusFilter != .all
    }

    private var activeFilterSummary: String {
        [
            cardFilterSummary,
            plaidAccountFilterSummary,
            typeFilterSummary,
            categoryFilterSummary,
            sourceFilter == .all ? nil : sourceFilter.title,
            statusFilter == .all ? nil : statusFilter.title
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private var cardFilterSummary: String? {
        guard let selectedCardFilterID else { return nil }
        if selectedCardFilterID == noCardFilterID {
            return "No Card"
        }
        return cardsForFilter.first { $0.id.uuidString == selectedCardFilterID }?.name?.nilIfBlank ?? "Selected Card"
    }

    private var plaidAccountFilterSummary: String? {
        if let selectedPlaidInstitutionFilterName {
            return selectedPlaidInstitutionFilterName
        }

        guard let selectedPlaidAccountFilterID else { return nil }
        if selectedPlaidAccountFilterID == noPlaidAccountFilterID {
            return "No Plaid Account"
        }
        if let account = plaidAccounts.first(where: { $0.accountID == selectedPlaidAccountFilterID }) {
            return plaidAccountFilterLabel(for: account)
        }
        return orphanPlaidAccountLabel(for: selectedPlaidAccountFilterID)
    }

    private var typeFilterSummary: String? {
        if let selectedTypeGroupFilter {
            return selectedTypeGroupFilter
        }

        guard let selectedTypeFilter else { return nil }
        return selectedTypeFilter == noTypeFilterValue ? "No Type" : selectedTypeFilter
    }

    private var categoryFilterSummary: String? {
        if let selectedCategoryGroupFilter {
            return selectedCategoryGroupFilter
        }

        guard let selectedCategoryFilter else { return nil }
        return selectedCategoryFilter == noCategoryFilterValue ? "Uncategorized" : selectedCategoryFilter
    }

    private var selectedTransactions: [Transaction] {
        transactions.filter { selectedTransactionIDs.contains($0.persistentModelID) }
    }

    private var selectedTransactionCount: Int {
        selectedTransactions.count
    }

    private var allVisibleTransactionsSelected: Bool {
        !visibleTransactions.isEmpty
            && visibleTransactions.allSatisfy { selectedTransactionIDs.contains($0.persistentModelID) }
    }

    private func transactionDate(for transaction: Transaction) -> Date {
        transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt ?? .distantPast
    }

    private func matchesSelectedFilters(_ transaction: Transaction) -> Bool {
        if let selectedCardFilterID {
            if selectedCardFilterID == noCardFilterID {
                guard transaction.creditCard == nil else { return false }
            } else {
                guard transaction.creditCard?.id.uuidString == selectedCardFilterID else { return false }
            }
        }

        if let selectedPlaidAccountFilterID {
            if selectedPlaidAccountFilterID == noPlaidAccountFilterID {
                guard transaction.plaidAccountID?.nilIfBlank == nil else { return false }
            } else {
                guard transaction.plaidAccountID?.nilIfBlank == selectedPlaidAccountFilterID else { return false }
            }
        } else if let selectedPlaidInstitutionFilterName {
            guard plaidAccount(for: transaction)?.institutionName?.nilIfBlank == selectedPlaidInstitutionFilterName else { return false }
        }

        if let selectedTypeFilter {
            if selectedTypeFilter == noTypeFilterValue {
                guard transaction.type?.nilIfBlank == nil else { return false }
            } else {
                guard transaction.type?.nilIfBlank == selectedTypeFilter else { return false }
            }
        } else if let selectedTypeGroupFilter {
            guard filterGroup(for: transaction.type) == selectedTypeGroupFilter else { return false }
        }

        if let selectedCategoryFilter {
            if selectedCategoryFilter == noCategoryFilterValue {
                guard transaction.category?.nilIfBlank == nil else { return false }
            } else {
                guard transaction.category?.nilIfBlank == selectedCategoryFilter else { return false }
            }
        } else if let selectedCategoryGroupFilter {
            guard filterGroup(for: transaction.category) == selectedCategoryGroupFilter else { return false }
        }

        switch sourceFilter {
        case .all:
            break
        case .plaid:
            guard isPlaidImported(transaction) else { return false }
        case .other:
            guard !isPlaidImported(transaction) else { return false }
        }

        switch statusFilter {
        case .all:
            break
        case .pending:
            guard transaction.plaidIsPending == true else { return false }
        case .posted:
            guard transaction.plaidIsPending != true else { return false }
        }

        return true
    }

    private func isPlaidImported(_ transaction: Transaction) -> Bool {
        transaction.plaidTransactionID?.nilIfBlank != nil
            || transaction.plaidAccountID?.nilIfBlank != nil
            || transaction.plaidImportedAt != nil
    }

    private func matchesSearchTokens(_ transaction: Transaction) -> Bool {
        searchTokens.allSatisfy { token in
            switch token.kind {
            case .merchant(let merchantName):
                return [
                    transactionTitle(for: transaction),
                    transaction.merchant,
                    transaction.friendlyName,
                    transaction.transactionDescription
                ]
                .compactMap { $0?.nilIfBlank }
                .contains { $0.localizedCaseInsensitiveContains(merchantName) }
            default:
                return true
            }
        }
    }

    private func refreshSearchSuggestions() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            suggestedSearchTokens = []
            return
        }

        let activeTokenIDs = Set(searchTokens.map(\.id))
        let suggestions = allSearchSuggestionTokens
            .filter { !activeTokenIDs.contains($0.id) }
            .filter { $0.matches(query) }
            .prefix(12)

        suggestedSearchTokens = Array(suggestions)
    }

    private var allSearchSuggestionTokens: [WalletTransactionSearchToken] {
        var tokens: [WalletTransactionSearchToken] = []

        tokens.append(contentsOf: institutionSearchTokens)
        tokens.append(contentsOf: plaidAccountFilterOptions.map {
            WalletTransactionSearchToken(
                kind: .plaidAccount($0.id),
                title: $0.title,
                subtitle: $0.sectionTitle,
                systemImage: "building.columns"
            )
        })
        tokens.append(contentsOf: cardFilterOptions.map {
            WalletTransactionSearchToken(
                kind: .card($0.id),
                title: $0.title,
                subtitle: $0.subtitle,
                systemImage: "creditcard"
            )
        })
        tokens.append(contentsOf: groupedSearchTokens(for: typeFilterOptions, groupKind: WalletTransactionSearchTokenKind.typeGroup, optionKind: WalletTransactionSearchTokenKind.type, systemImage: "tag"))
        tokens.append(contentsOf: groupedSearchTokens(for: categoryFilterOptions, groupKind: WalletTransactionSearchTokenKind.categoryGroup, optionKind: WalletTransactionSearchTokenKind.category, systemImage: "folder"))
        tokens.append(contentsOf: WalletTransactionSourceFilter.allCases.filter { $0 != .all }.map {
            WalletTransactionSearchToken(kind: .source($0), title: $0.title, subtitle: "Source", systemImage: "tray.and.arrow.down")
        })
        tokens.append(contentsOf: WalletTransactionStatusFilter.allCases.filter { $0 != .all }.map {
            WalletTransactionSearchToken(kind: .status($0), title: $0.title, subtitle: "Status", systemImage: "clock")
        })
        tokens.append(contentsOf: merchantSearchTokens)

        return deduplicatedSearchTokens(tokens)
    }

    private var institutionSearchTokens: [WalletTransactionSearchToken] {
        distinctValues(plaidAccountsForFilter.compactMap { $0.institutionName?.nilIfBlank })
            .map {
                WalletTransactionSearchToken(
                    kind: .plaidInstitution($0),
                    title: $0,
                    subtitle: "Institution",
                    systemImage: "building.columns"
                )
            }
    }

    private var merchantSearchTokens: [WalletTransactionSearchToken] {
        distinctValues(transactions.map(transactionTitle(for:)).filter { $0 != "Transaction" })
            .map {
                WalletTransactionSearchToken(
                    kind: .merchant($0),
                    title: $0,
                    subtitle: "Merchant",
                    systemImage: "storefront"
                )
            }
    }

    private func groupedSearchTokens(
        for options: [WalletFilterOption],
        groupKind: (String) -> WalletTransactionSearchTokenKind,
        optionKind: (String) -> WalletTransactionSearchTokenKind,
        systemImage: String
    ) -> [WalletTransactionSearchToken] {
        var tokens: [WalletTransactionSearchToken] = []
        let groupTitles = distinctValues(options.compactMap(\.groupTitle))

        tokens.append(contentsOf: groupTitles.map {
            WalletTransactionSearchToken(kind: groupKind($0), title: $0, subtitle: "Group", systemImage: systemImage)
        })

        tokens.append(contentsOf: options.map {
            WalletTransactionSearchToken(
                kind: optionKind($0.id),
                title: $0.searchTitle,
                subtitle: $0.groupTitle,
                systemImage: systemImage
            )
        })

        return tokens
    }

    private var activeFilterSearchTokens: [WalletTransactionSearchToken] {
        [
            selectedCardFilterID.flatMap { tokenForCardFilter($0) },
            selectedPlaidInstitutionFilterName.map {
                WalletTransactionSearchToken(kind: .plaidInstitution($0), title: $0, subtitle: "Institution", systemImage: "building.columns")
            },
            selectedPlaidAccountFilterID.flatMap { tokenForPlaidAccountFilter($0) },
            selectedTypeGroupFilter.map {
                WalletTransactionSearchToken(kind: .typeGroup($0), title: $0, subtitle: "Type", systemImage: "tag")
            },
            selectedTypeFilter.flatMap { tokenForTypeFilter($0) },
            selectedCategoryGroupFilter.map {
                WalletTransactionSearchToken(kind: .categoryGroup($0), title: $0, subtitle: "Category", systemImage: "folder")
            },
            selectedCategoryFilter.flatMap { tokenForCategoryFilter($0) },
            sourceFilter == .all ? nil : WalletTransactionSearchToken(kind: .source(sourceFilter), title: sourceFilter.title, subtitle: "Source", systemImage: "tray.and.arrow.down"),
            statusFilter == .all ? nil : WalletTransactionSearchToken(kind: .status(statusFilter), title: statusFilter.title, subtitle: "Status", systemImage: "clock")
        ]
        .compactMap { $0 }
    }

    private func tokenForCardFilter(_ id: String) -> WalletTransactionSearchToken? {
        guard let option = cardFilterOptions.first(where: { $0.id == id }) else { return nil }
        return WalletTransactionSearchToken(kind: .card(id), title: option.title, subtitle: option.subtitle, systemImage: "creditcard")
    }

    private func tokenForPlaidAccountFilter(_ id: String) -> WalletTransactionSearchToken? {
        guard let option = plaidAccountFilterOptions.first(where: { $0.id == id }) else { return nil }
        return WalletTransactionSearchToken(kind: .plaidAccount(id), title: option.title, subtitle: option.sectionTitle, systemImage: "building.columns")
    }

    private func tokenForTypeFilter(_ id: String) -> WalletTransactionSearchToken? {
        guard let option = typeFilterOptions.first(where: { $0.id == id }) else { return nil }
        return WalletTransactionSearchToken(kind: .type(id), title: option.searchTitle, subtitle: option.groupTitle, systemImage: "tag")
    }

    private func tokenForCategoryFilter(_ id: String) -> WalletTransactionSearchToken? {
        guard let option = categoryFilterOptions.first(where: { $0.id == id }) else { return nil }
        return WalletTransactionSearchToken(kind: .category(id), title: option.searchTitle, subtitle: option.groupTitle, systemImage: "folder")
    }

    private func handleSearchTokensChanged(from oldTokens: [WalletTransactionSearchToken], to newTokens: [WalletTransactionSearchToken]) {
        guard !isUpdatingSearchTokens else { return }

        let deduplicatedTokens = deduplicatedSearchTokens(newTokens)
        if deduplicatedTokens != newTokens {
            setSearchTokens(deduplicatedTokens)
            return
        }

        let oldSet = Set(oldTokens)
        let newSet = Set(newTokens)

        for token in oldSet.subtracting(newSet) {
            removeSearchTokenEffect(token)
        }

        for token in newSet.subtracting(oldSet) {
            applySearchTokenEffect(token)
        }

        if !newSet.subtracting(oldSet).isEmpty {
            searchText = ""
        }

        syncFilterSearchTokens()
        refreshSearchSuggestions()
    }

    private func applySearchTokenEffect(_ token: WalletTransactionSearchToken) {
        switch token.kind {
        case .card(let id):
            selectedCardFilterID = id
        case .plaidInstitution(let institutionName):
            selectedPlaidInstitutionFilterName = institutionName
            selectedPlaidAccountFilterID = nil
        case .plaidAccount(let id):
            selectedPlaidAccountFilterID = id
            selectedPlaidInstitutionFilterName = nil
        case .typeGroup(let group):
            selectedTypeGroupFilter = group
            selectedTypeFilter = nil
        case .type(let type):
            selectedTypeFilter = type
            selectedTypeGroupFilter = nil
        case .categoryGroup(let group):
            selectedCategoryGroupFilter = group
            selectedCategoryFilter = nil
        case .category(let category):
            selectedCategoryFilter = category
            selectedCategoryGroupFilter = nil
        case .source(let filter):
            sourceFilter = filter
        case .status(let filter):
            statusFilter = filter
        case .merchant:
            break
        }
    }

    private func removeSearchTokenEffect(_ token: WalletTransactionSearchToken) {
        switch token.kind {
        case .card(let id) where selectedCardFilterID == id:
            selectedCardFilterID = nil
        case .plaidInstitution(let institutionName) where selectedPlaidInstitutionFilterName == institutionName:
            selectedPlaidInstitutionFilterName = nil
        case .plaidAccount(let id) where selectedPlaidAccountFilterID == id:
            selectedPlaidAccountFilterID = nil
        case .typeGroup(let group) where selectedTypeGroupFilter == group:
            selectedTypeGroupFilter = nil
        case .type(let type) where selectedTypeFilter == type:
            selectedTypeFilter = nil
        case .categoryGroup(let group) where selectedCategoryGroupFilter == group:
            selectedCategoryGroupFilter = nil
        case .category(let category) where selectedCategoryFilter == category:
            selectedCategoryFilter = nil
        case .source(let filter) where sourceFilter == filter:
            sourceFilter = .all
        case .status(let filter) where statusFilter == filter:
            statusFilter = .all
        default:
            break
        }
    }

    private func syncFilterSearchTokens() {
        guard !isUpdatingSearchTokens else { return }
        let merchantTokens = searchTokens.filter(\.kind.isMerchant)
        let syncedTokens = deduplicatedSearchTokens(merchantTokens + activeFilterSearchTokens)
        guard syncedTokens != searchTokens else {
            refreshSearchSuggestions()
            return
        }

        setSearchTokens(syncedTokens)
        refreshSearchSuggestions()
    }

    private func removeFilterSearchTokens() {
        let merchantTokens = searchTokens.filter(\.kind.isMerchant)
        setSearchTokens(merchantTokens)
        refreshSearchSuggestions()
    }

    private func setSearchTokens(_ tokens: [WalletTransactionSearchToken]) {
        isUpdatingSearchTokens = true
        searchTokens = tokens
        isUpdatingSearchTokens = false
    }

    private func deduplicatedSearchTokens(_ tokens: [WalletTransactionSearchToken]) -> [WalletTransactionSearchToken] {
        var seenDimensions = Set<String>()
        var result: [WalletTransactionSearchToken] = []

        for token in tokens.reversed() {
            let dimension = token.kind.dimension
            guard seenDimensions.insert(dimension).inserted else { continue }
            result.insert(token, at: 0)
        }

        return result
    }

    private func confirmDelete(_ transaction: Transaction) {
        transactionPendingDeletion = transaction
        showingDeleteConfirmation = true
    }

    private func delete(_ transaction: Transaction) {
        deleteTransactions([transaction])
    }

    private func deleteSelectedTransactions() {
        let transactionsToDelete = selectedTransactions
        guard !transactionsToDelete.isEmpty else { return }
        deleteTransactions(transactionsToDelete)
    }

    private func deleteTransactions(_ transactionsToDelete: [Transaction]) {
        guard !transactionsToDelete.isEmpty else { return }
        let pendingDeletionID = transactionPendingDeletion?.persistentModelID
        let deletedNames = transactionsToDelete.map(transactionTitle(for:))
        let plaidDeleteCount = transactionsToDelete.filter(isPlaidImported).count
        let count = transactionsToDelete.count

        for transaction in transactionsToDelete {
            modelContext.delete(transaction)
        }

        do {
            try modelContext.save()
            deletionErrorMessage = nil
            selectedTransactionIDs.subtract(Set(transactionsToDelete.map(\.persistentModelID)))
            if let pendingDeletionID, transactionsToDelete.contains(where: { $0.persistentModelID == pendingDeletionID }) {
                transactionPendingDeletion = nil
            }
            if isSelecting && selectedTransactionIDs.isEmpty {
                isSelecting = false
            }
            MoneyMapDiagnostics.record(
                count == 1 ? "wallet.transaction.delete" : "wallet.transactions.bulk_delete",
                metadata: [
                    "count": "\(count)",
                    "plaid": "\(plaidDeleteCount)",
                    "names": deletedNames.prefix(4).joined(separator: ", ")
                ]
            )
        } catch {
            let name = count == 1 ? (deletedNames.first ?? "transaction") : "\(count) transactions"
            deletionErrorMessage = "Could not delete \(name): \(error.localizedDescription)"
        }
    }

    private func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting {
            selectedTransactionIDs.removeAll()
        }
    }

    private func toggleSelection(for transaction: Transaction) {
        let id = transaction.persistentModelID
        if selectedTransactionIDs.contains(id) {
            selectedTransactionIDs.remove(id)
        } else {
            selectedTransactionIDs.insert(id)
        }
    }

    private func toggleSelectAllVisibleTransactions() {
        let visibleIDs = Set(visibleTransactions.map(\.persistentModelID))
        if allVisibleTransactionsSelected {
            selectedTransactionIDs.subtract(visibleIDs)
        } else {
            selectedTransactionIDs.formUnion(visibleIDs)
        }
    }

    private func pruneSelectionToVisibleTransactions() {
        guard isSelecting else { return }
        selectedTransactionIDs.formIntersection(Set(visibleTransactions.map(\.persistentModelID)))
    }

    private func pruneSelectionToExistingTransactions() {
        selectedTransactionIDs.formIntersection(Set(transactions.map(\.persistentModelID)))
        if isSelecting && selectedTransactionIDs.isEmpty && visibleTransactions.isEmpty {
            isSelecting = false
        }
    }

    private func clearFilters() {
        selectedCardFilterID = nil
        selectedPlaidInstitutionFilterName = nil
        selectedPlaidAccountFilterID = nil
        selectedTypeGroupFilter = nil
        selectedTypeFilter = nil
        selectedCategoryGroupFilter = nil
        selectedCategoryFilter = nil
        sourceFilter = .all
        statusFilter = .all
        removeFilterSearchTokens()
    }

    private func distinctValues(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func filterHierarchy(for value: String) -> (group: String?, title: String) {
        let parts = value
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else {
            return (nil, value)
        }

        return (parts[0], parts.dropFirst().joined(separator: " / "))
    }

    private func filterGroup(for value: String?) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        return filterHierarchy(for: value).group
    }

    private func plaidAccount(for transaction: Transaction) -> PlaidAccountValue? {
        guard let plaidAccountID = transaction.plaidAccountID?.nilIfBlank else {
            return nil
        }

        return plaidAccounts.first { $0.accountID == plaidAccountID }
    }

    private func plaidAccountDisplayName(for transaction: Transaction) -> String? {
        if let account = plaidAccount(for: transaction) {
            return plaidAccountFilterLabel(for: account)
        }

        if let plaidAccountID = transaction.plaidAccountID?.nilIfBlank {
            return orphanPlaidAccountLabel(for: plaidAccountID)
        }

        return nil
    }

    private func plaidAccountFilterLabel(for account: PlaidAccountValue) -> String {
        [
            account.institutionName?.nilIfBlank,
            accountFilterTitle(for: account).nilIfBlank,
            account.lastFourLabel?.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private func accountFilterTitle(for account: PlaidAccountValue) -> String {
        account.displayName
            .replacingLeadingPhrase(account.institutionName)
            .nilIfBlank
            ?? account.displayName
    }

    private func orphanPlaidAccountLabel(for accountID: String) -> String {
        "Plaid account \(String(accountID.suffix(6)))"
    }

    private func sourceLabel(for transaction: Transaction) -> String {
        isPlaidImported(transaction) ? WalletTransactionSourceFilter.plaid.title : WalletTransactionSourceFilter.other.title
    }

    private func statusLabel(for transaction: Transaction) -> String {
        transaction.plaidIsPending == true ? WalletTransactionStatusFilter.pending.title : WalletTransactionStatusFilter.posted.title
    }

    private func transactionTitle(for transaction: Transaction) -> String {
        transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Transaction"
    }

    private func searchableText(for transaction: Transaction) -> String {
        [
            transactionTitle(for: transaction),
            transaction.category,
            transaction.type,
            transaction.purchasedBy,
            transaction.creditCard?.name,
            plaidAccountDisplayName(for: transaction),
            plaidAccount(for: transaction)?.institutionName,
            sourceLabel(for: transaction),
            statusLabel(for: transaction),
            transaction.amountUSD.map { MoneyMapFormatters.currencyString(for: $0) },
            transactionDate(for: transaction).formatted(date: .abbreviated, time: .omitted)
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " ")
    }
}

private enum WalletTransactionSearchTokenKind: Hashable {
    case card(String)
    case plaidInstitution(String)
    case plaidAccount(String)
    case typeGroup(String)
    case type(String)
    case categoryGroup(String)
    case category(String)
    case source(WalletTransactionSourceFilter)
    case status(WalletTransactionStatusFilter)
    case merchant(String)

    var id: String {
        switch self {
        case .card(let value): return "card:\(value)"
        case .plaidInstitution(let value): return "plaidInstitution:\(value)"
        case .plaidAccount(let value): return "plaidAccount:\(value)"
        case .typeGroup(let value): return "typeGroup:\(value)"
        case .type(let value): return "type:\(value)"
        case .categoryGroup(let value): return "categoryGroup:\(value)"
        case .category(let value): return "category:\(value)"
        case .source(let value): return "source:\(value.rawValue)"
        case .status(let value): return "status:\(value.rawValue)"
        case .merchant(let value): return "merchant:\(value)"
        }
    }

    var dimension: String {
        switch self {
        case .card: return "card"
        case .plaidInstitution, .plaidAccount: return "plaidAccount"
        case .typeGroup, .type: return "type"
        case .categoryGroup, .category: return "category"
        case .source: return "source"
        case .status: return "status"
        case .merchant(let value): return "merchant:\(value)"
        }
    }

    var isMerchant: Bool {
        if case .merchant = self {
            return true
        }
        return false
    }
}

private struct WalletTransactionSearchToken: Identifiable, Hashable {
    let kind: WalletTransactionSearchTokenKind
    let title: String
    var subtitle: String?
    let systemImage: String

    var id: String { kind.id }

    func matches(_ query: String) -> Bool {
        [
            title,
            subtitle
        ]
        .compactMap { $0?.nilIfBlank }
        .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct WalletFilterOption: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String?
    var sectionTitle: String?
    var groupID: String?
    var groupTitle: String?

    var searchTitle: String {
        guard let groupTitle, groupTitle != title else {
            return title
        }
        return "\(groupTitle) / \(title)"
    }
}

private struct WalletFilterOptionSection: Identifiable, Hashable {
    let id: String
    let title: String?
    let groupID: String?
    let groupTitle: String?
    let options: [WalletFilterOption]

    var showsGroupSelection: Bool {
        groupID != nil && options.count > 1
    }
}

private struct WalletTransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCardFilterID: String?
    @Binding var selectedPlaidInstitutionFilterName: String?
    @Binding var selectedPlaidAccountFilterID: String?
    @Binding var selectedTypeGroupFilter: String?
    @Binding var selectedTypeFilter: String?
    @Binding var selectedCategoryGroupFilter: String?
    @Binding var selectedCategoryFilter: String?
    @Binding var sourceFilter: WalletTransactionSourceFilter
    @Binding var statusFilter: WalletTransactionStatusFilter

    let cardOptions: [WalletFilterOption]
    let plaidAccountOptions: [WalletFilterOption]
    let typeOptions: [WalletFilterOption]
    let categoryOptions: [WalletFilterOption]
    let hasActiveFilters: Bool
    let activeFilterSummary: String
    let clearFilters: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if hasActiveFilters {
                    Section {
                        Label {
                            Text(activeFilterSummary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(MoneyMapDesign.calmGreen)
                        }
                    } header: {
                        Text("Active Filters")
                    }
                }

                Section("Filter By") {
                    NavigationLink {
                        WalletTransactionOptionalFilterList(
                            title: "Card",
                            allTitle: "All Cards",
                            selection: $selectedCardFilterID,
                            options: cardOptions
                        )
                    } label: {
                        WalletFilterCategoryRow(
                            systemImage: "creditcard",
                            title: "Card",
                            value: selectedTitle(for: selectedCardFilterID, allTitle: "All Cards", options: cardOptions),
                            isActive: selectedCardFilterID != nil
                        )
                    }

                    NavigationLink {
                        WalletTransactionGroupedFilterList(
                            title: "Bank / Account",
                            allTitle: "All Banks",
                            selection: $selectedPlaidAccountFilterID,
                            groupSelection: $selectedPlaidInstitutionFilterName,
                            options: plaidAccountOptions
                        )
                    } label: {
                        WalletFilterCategoryRow(
                            systemImage: "building.columns",
                            title: "Bank / Account",
                            value: selectedTitle(
                                for: selectedPlaidAccountFilterID,
                                groupSelection: selectedPlaidInstitutionFilterName,
                                allTitle: "All Banks",
                                options: plaidAccountOptions
                            ),
                            isActive: selectedPlaidAccountFilterID != nil || selectedPlaidInstitutionFilterName != nil
                        )
                    }

                    NavigationLink {
                        WalletTransactionGroupedFilterList(
                            title: "Type",
                            allTitle: "All Types",
                            selection: $selectedTypeFilter,
                            groupSelection: $selectedTypeGroupFilter,
                            options: typeOptions
                        )
                    } label: {
                        WalletFilterCategoryRow(
                            systemImage: "tag",
                            title: "Type",
                            value: selectedTitle(
                                for: selectedTypeFilter,
                                groupSelection: selectedTypeGroupFilter,
                                allTitle: "All Types",
                                options: typeOptions
                            ),
                            isActive: selectedTypeFilter != nil || selectedTypeGroupFilter != nil
                        )
                    }

                    NavigationLink {
                        WalletTransactionGroupedFilterList(
                            title: "Category",
                            allTitle: "All Categories",
                            selection: $selectedCategoryFilter,
                            groupSelection: $selectedCategoryGroupFilter,
                            options: categoryOptions
                        )
                    } label: {
                        WalletFilterCategoryRow(
                            systemImage: "folder",
                            title: "Category",
                            value: selectedTitle(
                                for: selectedCategoryFilter,
                                groupSelection: selectedCategoryGroupFilter,
                                allTitle: "All Categories",
                                options: categoryOptions
                            ),
                            isActive: selectedCategoryFilter != nil || selectedCategoryGroupFilter != nil
                        )
                    }

                    NavigationLink {
                        WalletTransactionSourceFilterList(selection: $sourceFilter)
                    } label: {
                        WalletFilterCategoryRow(
                            systemImage: "tray.and.arrow.down",
                            title: "Source",
                            value: sourceFilter.title,
                            isActive: sourceFilter != .all
                        )
                    }

                    NavigationLink {
                        WalletTransactionStatusFilterList(selection: $statusFilter)
                    } label: {
                        WalletFilterCategoryRow(
                            systemImage: "clock",
                            title: "Status",
                            value: statusFilter.title,
                            isActive: statusFilter != .all
                        )
                    }
                }

                if hasActiveFilters {
                    Section {
                        Button {
                            clearFilters()
                        } label: {
                            Label("Clear Filters", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func selectedTitle(for selection: String?, allTitle: String, options: [WalletFilterOption]) -> String {
        guard let selection else { return allTitle }
        return options.first { $0.id == selection }?.title ?? "Selected"
    }

    private func selectedTitle(
        for selection: String?,
        groupSelection: String?,
        allTitle: String,
        options: [WalletFilterOption]
    ) -> String {
        if let groupSelection {
            return groupSelection
        }

        guard let selection else { return allTitle }
        return options.first { $0.id == selection }?.searchTitle ?? "Selected"
    }
}

private struct WalletFilterCategoryRow: View {
    let systemImage: String
    let title: String
    let value: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? MoneyMapDesign.calmGreen : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)

                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(MoneyMapDesign.calmGreen)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WalletTransactionOptionalFilterList: View {
    let title: String
    let allTitle: String
    @Binding var selection: String?
    let options: [WalletFilterOption]

    var body: some View {
        List {
            Section {
                Button {
                    selection = nil
                } label: {
                    WalletFilterChoiceRow(
                        title: allTitle,
                        subtitle: nil,
                        isSelected: selection == nil
                    )
                }
                .buttonStyle(.plain)
            }

            Section {
                if options.isEmpty {
                    Text("No filter options available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(options) { option in
                        Button {
                            selection = option.id
                        } label: {
                            WalletFilterChoiceRow(
                                title: option.title,
                                subtitle: option.subtitle,
                                isSelected: selection == option.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalletTransactionGroupedFilterList: View {
    let title: String
    let allTitle: String
    @Binding var selection: String?
    @Binding var groupSelection: String?
    let options: [WalletFilterOption]

    private var sections: [WalletFilterOptionSection] {
        var sections: [WalletFilterOptionSection] = []

        for option in options {
            let sectionID = option.sectionTitle ?? "__ungrouped__"
            if let index = sections.firstIndex(where: { $0.id == sectionID }) {
                let section = sections[index]
                var updatedOptions = section.options
                updatedOptions.append(option)
                sections[index] = WalletFilterOptionSection(
                    id: section.id,
                    title: section.title,
                    groupID: section.groupID,
                    groupTitle: section.groupTitle,
                    options: updatedOptions
                )
            } else {
                sections.append(
                    WalletFilterOptionSection(
                        id: sectionID,
                        title: option.sectionTitle,
                        groupID: option.groupID,
                        groupTitle: option.groupTitle,
                        options: [option]
                    )
                )
            }
        }

        return sections
    }

    var body: some View {
        List {
            Section {
                Button {
                    selection = nil
                    groupSelection = nil
                } label: {
                    WalletFilterChoiceRow(
                        title: allTitle,
                        subtitle: nil,
                        isSelected: selection == nil && groupSelection == nil
                    )
                }
                .buttonStyle(.plain)
            }

            if options.isEmpty {
                Section {
                    Text("No filter options available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        if section.showsGroupSelection, let groupID = section.groupID, let groupTitle = section.groupTitle {
                            Button {
                                selection = nil
                                groupSelection = groupID
                            } label: {
                                WalletFilterChoiceRow(
                                    title: "All \(groupTitle)",
                                    subtitle: nil,
                                    isSelected: groupSelection == groupID
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(section.options) { option in
                            Button {
                                selection = option.id
                                groupSelection = nil
                            } label: {
                                WalletFilterChoiceRow(
                                    title: option.title,
                                    subtitle: option.subtitle,
                                    isSelected: selection == option.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalletTransactionSourceFilterList: View {
    @Binding var selection: WalletTransactionSourceFilter

    var body: some View {
        List {
            Section {
                ForEach(WalletTransactionSourceFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        WalletFilterChoiceRow(
                            title: filter.title,
                            subtitle: nil,
                            isSelected: selection == filter
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Source")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalletTransactionStatusFilterList: View {
    @Binding var selection: WalletTransactionStatusFilter

    var body: some View {
        List {
            Section {
                ForEach(WalletTransactionStatusFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        WalletFilterChoiceRow(
                            title: filter.title,
                            subtitle: nil,
                            isSelected: selection == filter
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Status")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalletFilterChoiceRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle?.nilIfBlank {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct WalletTransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let transaction: Transaction
    let plaidAccounts: [PlaidAccountValue]

    @State private var showingDeleteConfirmation = false
    @State private var deletionErrorMessage: String?

    var body: some View {
        List {
            headerSection
            detailsSection
            datesSection
            sourceSection
            deleteSection
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Transaction", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete transaction?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Transaction", role: .destructive) {
                deleteTransaction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the transaction from MoneyMap. It does not delete any bill, card, or Plaid connection.")
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(transactionTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(MoneyMapFormatters.currencyString(for: transaction.amountUSD ?? 0))
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle((transaction.amountUSD ?? 0) < 0 ? MoneyMapDesign.calmGreen : .primary)

                if let detail = headerDetail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var detailsSection: some View {
        Section("Details") {
            TransactionDetailLabeledRow(title: "Merchant", value: merchantDetail)
            TransactionDetailLabeledRow(title: "Category", value: transaction.category)
            TransactionDetailLabeledRow(title: "Status", value: transactionStatusText)
            TransactionDetailLabeledRow(title: "Original Description", value: originalDescription)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var datesSection: some View {
        Section("Dates") {
            TransactionDetailLabeledRow(title: "Transaction Date", value: dateText(transaction.transactionDate))
            TransactionDetailLabeledRow(title: "Clearing Date", value: dateText(transaction.clearingDate))
            TransactionDetailLabeledRow(title: "Imported", value: dateTimeText(transaction.plaidImportedAt))
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var sourceSection: some View {
        Section {
            TransactionDetailLabeledRow(title: "Card", value: transaction.creditCard?.name)
            TransactionDetailLabeledRow(title: "Account", value: accountSourceText)
            TransactionDetailLabeledRow(title: "Imported By", value: importerText)
        } header: {
            Text("Source")
        } footer: {
            if transaction.plaidAccountID?.isEmpty == false && plaidAccount == nil {
                Text("MoneyMap has the Plaid account ID, but not the account snapshot for this transaction.")
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var deleteSection: some View {
        Section {
            if let deletionErrorMessage {
                Label(deletionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(MoneyMapDesign.attentionRed)
                    .textSelection(.enabled)
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Transaction", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var transactionTitle: String {
        transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Transaction"
    }

    private var headerDetail: String? {
        [
            transactionStatusAndDateText,
            sourceSummary
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " • ")
        .nilIfBlank
    }

    private var transactionDate: Date? {
        transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt
    }

    private var transactionStatusText: String {
        transaction.plaidIsPending == true ? "Pending" : "Posted"
    }

    private var transactionStatusAndDateText: String? {
        guard let transactionDate else { return transactionStatusText }
        return "\(transactionStatusText) \(MoneyMapFormatters.mediumDateString(for: transactionDate))"
    }

    private var merchantDetail: String? {
        distinctDetailValue(transaction.merchant, excluding: [transactionTitle])
    }

    private var originalDescription: String? {
        distinctDetailValue(
            transaction.transactionDescription,
            excluding: [transactionTitle, transaction.merchant, transaction.friendlyName]
        )
    }

    private var plaidAccount: PlaidAccountValue? {
        guard let plaidAccountID = transaction.plaidAccountID?.nilIfBlank else {
            return nil
        }
        return plaidAccounts.first { $0.accountID == plaidAccountID }
    }

    private var plaidAccountDisplayName: String? {
        if let plaidAccount {
            return [
                plaidAccount.displayName,
                plaidAccount.lastFourLabel
            ]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " - ")
        }

        if let plaidAccountID = transaction.plaidAccountID?.nilIfBlank {
            return "Plaid account \(String(plaidAccountID.suffix(6)))"
        }

        return nil
    }

    private var accountSourceText: String? {
        if let plaidAccount {
            return friendlyAccountName(for: plaidAccount)
        }

        return plaidAccountDisplayName
    }

    private var importerText: String? {
        if hasPlaidDetails {
            return "Plaid"
        }

        return distinctDetailValue(transaction.purchasedBy, excluding: [transactionTitle, transaction.merchant])
    }

    private var sourceSummary: String? {
        accountSourceText
            ?? transaction.creditCard?.name?.nilIfBlank
            ?? transaction.purchasedBy?.nilIfBlank
    }

    private var hasPlaidDetails: Bool {
        transaction.plaidTransactionID?.isEmpty == false
            || transaction.plaidPendingTransactionID?.isEmpty == false
            || transaction.plaidAccountID?.isEmpty == false
            || transaction.plaidImportedAt != nil
            || transaction.plaidIsPending != nil
    }

    private func deleteTransaction() {
        let name = transactionTitle
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            deletionErrorMessage = nil
            dismiss()
        } catch {
            deletionErrorMessage = "Could not delete \(name): \(error.localizedDescription)"
        }
    }

    private func dateText(_ date: Date?) -> String? {
        date.map(MoneyMapFormatters.mediumDateString(for:))
    }

    private func dateTimeText(_ date: Date?) -> String? {
        date?.formatted(date: .abbreviated, time: .shortened)
    }

    private func friendlyAccountName(for account: PlaidAccountValue) -> String {
        let accountName = account.displayName
            .replacingLeadingPhrase(account.institutionName)
            .nilIfBlank
        let institutionName = account.institutionName?.nilIfBlank
        let displayName = accountName ?? account.displayName.nilIfBlank
        let baseName = institutionName ?? displayName
        let lastFour = account.lastFourLabel?.replacingOccurrences(of: "Ending ", with: "ending ")

        let parts = [
            baseName,
            lastFour
        ]
        .compactMap { $0?.nilIfBlank }

        return parts.joined(separator: " ")
    }

    private func distinctDetailValue(_ value: String?, excluding excludedValues: [String?]) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        let excluded = excludedValues.compactMap { $0?.nilIfBlank }
        guard !excluded.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else {
            return nil
        }
        return value
    }
}

private struct TransactionDetailLabeledRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value = value?.nilIfBlank {
            LabeledContent(title, value: value)
                .textSelection(.enabled)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func replacingLeadingPhrase(_ phrase: String?) -> String {
        guard let phrase = phrase?.nilIfBlank else {
            return self
        }

        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.localizedCaseInsensitiveCompare(phrase) != .orderedSame,
              trimmed.localizedCaseInsensitiveContains(phrase) else {
            return trimmed
        }

        let lowercasedTrimmed = trimmed.lowercased()
        let lowercasedPhrase = phrase.lowercased()
        guard lowercasedTrimmed.hasPrefix(lowercasedPhrase) else {
            return trimmed
        }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: phrase.count)
        let remainder = trimmed[startIndex...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return remainder.isEmpty ? trimmed : remainder
    }
}
