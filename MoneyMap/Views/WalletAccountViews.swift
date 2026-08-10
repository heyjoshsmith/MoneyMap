//
//  WalletAccountViews.swift
//  MoneyMap
//
//  Created by Codex on 7/8/26.
//

import SwiftData
import SwiftUI

struct WalletAccountsView: View {
    let accounts: [PlaidAccountValue]
    let plaidAccounts: [PlaidAccountValue]

    @Query private var transactions: [Transaction]
    @AppStorage(WalletAccountPreferences.appStorageKey) private var preferencesData = WalletAccountPreferences.emptyJSON
    @State private var iconPickerAccount: PlaidAccountValue?
    @State private var transactionCountsByPlaidAccountID: [String: Int] = [:]

    var body: some View {
        List {
            if sortedAccounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "building.columns",
                    description: Text("Checking, debit, savings, investment, and other synced accounts will appear here after Bank Sync.")
                )
            } else {
                accountTotalsSection

                ForEach(accountGroups) { group in
                    Section {
                        ForEach(group.accounts) { account in
                            NavigationLink {
                                WalletAccountDetailView(
                                    account: account,
                                    plaidAccounts: plaidAccounts
                                )
                            } label: {
                                WalletAccountRow(
                                    account: account,
                                    transactionCount: transactionCount(for: account),
                                    preferences: preferences
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    setHidden(true, for: account)
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    iconPickerAccount = account
                                } label: {
                                    Label("Change Icon", systemImage: "square.grid.2x2")
                                }

                                Picker("Balance Role", selection: contributionModeBinding(for: account)) {
                                    ForEach(WalletAccountContributionMode.allCases) { mode in
                                        Label(mode.title, systemImage: mode.systemImage)
                                            .tag(mode)
                                    }
                                }

                                Button(role: .destructive) {
                                    setHidden(true, for: account)
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                            }
                        }
                        .onMove { source, destination in
                            moveAccounts(in: group, from: source, to: destination)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group.id == accountGroups.last?.id {
                            Text("Credit cards remain in Cards. These accounts are synced account snapshots, not bills.")
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }
                .onMove(perform: moveGroups)

                hiddenAccountsSection
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            EditButton()

            Menu {
                Toggle(isOn: walletTileBalanceBinding) {
                    Label("Available on Wallet Tile", systemImage: "dollarsign.circle")
                }
            } label: {
                Label("Account Options", systemImage: "slider.horizontal.3")
            }
        }
        .sheet(item: $iconPickerAccount) { account in
            WalletAccountIconPickerView(
                account: account,
                selectedIconName: preferences.customIconName(for: account) ?? WalletAccountDisplay.iconName(for: account),
                save: { iconName in
                    updatePreferences { $0.setIconName(iconName, for: account) }
                },
                reset: {
                    updatePreferences { $0.setIconName(nil, for: account) }
                }
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .onAppear {
            refreshTransactionCountCache()
        }
        .onChange(of: transactions.count) { _, _ in
            refreshTransactionCountCache()
        }
    }

    private var sortedAccounts: [PlaidAccountValue] {
        accounts.sorted(by: WalletAccountDisplay.sortAccounts)
    }

    private var accountGroups: [WalletAccountInstitutionGroup] {
        WalletAccountGrouping.groups(for: visibleAccounts, preferences: preferences)
    }

    private var visibleAccounts: [PlaidAccountValue] {
        sortedAccounts.filter { !preferences.isHidden($0) }
    }

    private var hiddenAccounts: [PlaidAccountValue] {
        sortedAccounts.filter { preferences.isHidden($0) }
    }

    private var preferences: WalletAccountPreferences {
        WalletAccountPreferences.decode(from: preferencesData)
    }

    private var walletTileBalanceBinding: Binding<Bool> {
        Binding {
            preferences.showsAvailableMoneyOnWalletTile
        } set: { newValue in
            updatePreferences { $0.showsAvailableMoneyOnWalletTile = newValue }
        }
    }

    private var accountTotalsSection: some View {
        Section {
            WalletAccountTotalsCard(accounts: sortedAccounts, preferences: preferences)
        } footer: {
            Text("Set each account as available cash, an owned asset, an owed balance, or ignored.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var hiddenAccountsSection: some View {
        if !hiddenAccounts.isEmpty {
            Section {
                ForEach(hiddenAccounts) { account in
                    HStack(spacing: 12) {
                        WalletAccountRow(
                            account: account,
                            transactionCount: transactionCount(for: account),
                            preferences: preferences
                        )
                        .opacity(0.62)

                        Button {
                            setHidden(false, for: account)
                        } label: {
                            Label("Unhide", systemImage: "eye")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Hidden")
            } footer: {
                Text("Hidden accounts stay synced and can be restored here.")
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
    }

    private func transactionCount(for account: PlaidAccountValue) -> Int {
        transactionCountsByPlaidAccountID[account.accountID, default: 0]
    }

    private func refreshTransactionCountCache() {
        var countsByAccountID: [String: Int] = [:]
        for transaction in transactions {
            if let accountID = transaction.plaidAccountID?.nilIfBlank {
                countsByAccountID[accountID, default: 0] += 1
            }
        }
        transactionCountsByPlaidAccountID = countsByAccountID
    }

    private func contributionModeBinding(for account: PlaidAccountValue) -> Binding<WalletAccountContributionMode> {
        Binding {
            preferences.contributionMode(for: account)
        } set: { newValue in
            updatePreferences { $0.setContributionMode(newValue, for: account) }
        }
    }

    private func setHidden(_ hidden: Bool, for account: PlaidAccountValue) {
        updatePreferences { $0.setHidden(hidden, for: account) }
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        let currentGroups = accountGroups
        updatePreferences { $0.moveGroups(from: source, to: destination, currentGroups: currentGroups) }
    }

    private func moveAccounts(in group: WalletAccountInstitutionGroup, from source: IndexSet, to destination: Int) {
        updatePreferences { $0.moveAccounts(in: group, from: source, to: destination) }
    }

    private func updatePreferences(_ update: (inout WalletAccountPreferences) -> Void) {
        var updatedPreferences = preferences
        update(&updatedPreferences)
        preferencesData = updatedPreferences.encoded()
    }
}

struct WalletAccountDetailView: View {
    let account: PlaidAccountValue
    let plaidAccounts: [PlaidAccountValue]

    @Query private var transactions: [Transaction]
    @AppStorage(WalletAccountPreferences.appStorageKey) private var preferencesData = WalletAccountPreferences.emptyJSON
    @State private var isShowingIconPicker = false
    @State private var accountTransactions: [Transaction] = []

    var body: some View {
        List {
            headerSection
            personalizationSection
            balanceSection
            transactionsSection
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button {
                    isShowingIconPicker = true
                } label: {
                    Label("Change Icon", systemImage: "square.grid.2x2")
                }

                Toggle(isOn: walletTileBalanceBinding) {
                    Label("Available on Wallet Tile", systemImage: "dollarsign.circle")
                }

                if preferences.isHidden(account) {
                    Button {
                        updatePreferences { $0.setHidden(false, for: account) }
                    } label: {
                        Label("Unhide Account", systemImage: "eye")
                    }
                } else {
                    Button(role: .destructive) {
                        updatePreferences { $0.setHidden(true, for: account) }
                    } label: {
                        Label("Hide Account", systemImage: "eye.slash")
                    }
                }
            } label: {
                Label("Account Options", systemImage: "slider.horizontal.3")
            }
        }
        .sheet(isPresented: $isShowingIconPicker) {
            WalletAccountIconPickerView(
                account: account,
                selectedIconName: preferences.customIconName(for: account) ?? WalletAccountDisplay.iconName(for: account),
                save: { iconName in
                    updatePreferences { $0.setIconName(iconName, for: account) }
                },
                reset: {
                    updatePreferences { $0.setIconName(nil, for: account) }
                }
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .onAppear {
            refreshAccountTransactions()
        }
        .onChange(of: transactions.count) { _, _ in
            refreshAccountTransactions()
        }
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WalletAccountDisplay.tint(for: account).opacity(0.16))
                    Image(systemName: WalletAccountDisplay.iconName(for: account, preferences: preferences))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WalletAccountDisplay.tint(for: account))
                }
                .frame(width: 46, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(account.displayName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = WalletAccountDisplay.subtitle(for: account) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var personalizationSection: some View {
        Section("Display") {
            Button {
                isShowingIconPicker = true
            } label: {
                LabeledContent {
                    Image(systemName: WalletAccountDisplay.iconName(for: account, preferences: preferences))
                        .foregroundStyle(WalletAccountDisplay.tint(for: account))
                } label: {
                    Text("Icon")
                }
            }

            Picker("Balance Role", selection: contributionModeBinding) {
                ForEach(WalletAccountContributionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }

            Text(preferences.contributionMode(for: account).detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var balanceSection: some View {
        Section("Balance") {
            if showsSeparateAvailableBalance {
                AccountBalanceRow(
                    title: "Current",
                    value: WalletAccountDisplay.currencyText(account.currentBalance, code: account.currencyCode),
                    systemImage: "dollarsign.circle",
                    tint: WalletAccountDisplay.tint(for: account)
                )

                AccountBalanceRow(
                    title: "Available",
                    value: WalletAccountDisplay.currencyText(account.availableBalance, code: account.currencyCode),
                    systemImage: "checkmark.circle",
                    tint: MoneyMapDesign.calmGreen
                )
            } else {
                AccountBalanceRow(
                    title: primaryBalanceTitle,
                    value: WalletAccountDisplay.currencyText(primaryBalance, code: account.currencyCode),
                    systemImage: "dollarsign.circle",
                    tint: WalletAccountDisplay.tint(for: account)
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var transactionsSection: some View {
        Section {
            if accountTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Imported transactions for this account will appear here after Bank Sync review.")
                )
            } else {
                ForEach(accountTransactions, id: \.persistentModelID) { transaction in
                    NavigationLink {
                        WalletTransactionDetailView(
                            transaction: transaction,
                            plaidAccounts: plaidAccounts
                        )
                    } label: {
                        WalletAccountTransactionRow(transaction: transaction)
                    }
                }
            }
        } header: {
            Text("\(accountTransactions.count) Transaction\(accountTransactions.count == 1 ? "" : "s")")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var primaryBalance: Double? {
        account.availableBalance ?? account.currentBalance
    }

    private var primaryBalanceTitle: String {
        account.availableBalance == nil ? "Current" : "Available"
    }

    private var showsSeparateAvailableBalance: Bool {
        guard let current = account.currentBalance,
              let available = account.availableBalance else {
            return false
        }

        return abs(current - available) >= 0.01
    }

    private var preferences: WalletAccountPreferences {
        WalletAccountPreferences.decode(from: preferencesData)
    }

    private var contributionModeBinding: Binding<WalletAccountContributionMode> {
        Binding {
            preferences.contributionMode(for: account)
        } set: { newValue in
            updatePreferences { $0.setContributionMode(newValue, for: account) }
        }
    }

    private var walletTileBalanceBinding: Binding<Bool> {
        Binding {
            preferences.showsAvailableMoneyOnWalletTile
        } set: { newValue in
            updatePreferences { $0.showsAvailableMoneyOnWalletTile = newValue }
        }
    }

    private func updatePreferences(_ update: (inout WalletAccountPreferences) -> Void) {
        var updatedPreferences = preferences
        update(&updatedPreferences)
        preferencesData = updatedPreferences.encoded()
    }

    private func refreshAccountTransactions() {
        accountTransactions = transactions
            .filter { $0.plaidAccountID?.nilIfBlank == account.accountID }
            .sorted { transactionDate(for: $0) > transactionDate(for: $1) }
    }

    private func transactionDate(for transaction: Transaction) -> Date {
        transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt ?? .distantPast
    }
}

struct WalletAccountRow: View {
    let account: PlaidAccountValue
    let transactionCount: Int
    let preferences: WalletAccountPreferences

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: WalletAccountDisplay.iconName(for: account, preferences: preferences))
                .foregroundStyle(WalletAccountDisplay.tint(for: account))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle = WalletAccountDisplay.rowSubtitle(for: account) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(WalletAccountDisplay.currencyText(account.currentBalance, code: account.currencyCode))
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var rowDetail: String {
        let transactionText = "\(transactionCount) transaction\(transactionCount == 1 ? "" : "s")"
        return "\(preferences.contributionMode(for: account).title) - \(transactionText)"
    }
}

private struct WalletAccountTotalsCard: View {
    let accounts: [PlaidAccountValue]
    let preferences: WalletAccountPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                WalletAccountTotalMetric(
                    title: "Available",
                    value: MoneyMapFormatters.currencyString(for: preferences.availableMoneyTotal(in: accounts)),
                    systemImage: "checkmark.circle",
                    tint: MoneyMapDesign.calmGreen
                )

                WalletAccountTotalMetric(
                    title: "Assets",
                    value: MoneyMapFormatters.currencyString(for: preferences.ownedAssetTotal(in: accounts)),
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .purple
                )
            }

            WalletAccountTotalMetric(
                title: "Owed",
                value: MoneyMapFormatters.currencyString(for: preferences.owedTotal(in: accounts)),
                systemImage: "minus.circle",
                tint: MoneyMapDesign.warningGold
            )
        }
        .padding(.vertical, 2)
    }
}

private struct WalletAccountTotalMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountBalanceRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(value)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct WalletAccountTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.plaidIsPending == true ? "clock" : "arrow.down.circle")
                .foregroundStyle(transaction.plaidIsPending == true ? MoneyMapDesign.warningGold : MoneyMapDesign.calmGreen)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(transactionTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

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

    private var transactionTitle: String {
        transaction.friendlyName?.nilIfBlank
            ?? transaction.merchant?.nilIfBlank
            ?? transaction.transactionDescription?.nilIfBlank
            ?? "Transaction"
    }

    private var detail: String {
        [
            transaction.category?.nilIfBlank,
            transaction.type?.nilIfBlank,
            transactionDateText,
            transaction.plaidIsPending == true ? "Pending" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private var transactionDateText: String? {
        (transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt)
            .map(MoneyMapFormatters.mediumDateString(for:))
    }
}

struct WalletAccountInstitutionGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let accounts: [PlaidAccountValue]
}

enum WalletAccountGrouping {
    static func groups(for accounts: [PlaidAccountValue], preferences: WalletAccountPreferences? = nil) -> [WalletAccountInstitutionGroup] {
        let grouped = Dictionary(grouping: accounts, by: institutionTitle(for:))
        let groups = grouped
            .map { title, accounts in
                let id = title.lowercased()
                return WalletAccountInstitutionGroup(
                    id: id,
                    title: title,
                    accounts: preferences?.orderedAccounts(accounts, inGroupID: id) ?? accounts.sorted(by: WalletAccountDisplay.sortAccounts)
                )
            }

        return preferences?.orderedGroups(groups) ?? groups.sorted(by: sortGroups)
    }

    private static let unknownInstitutionTitle = "Unknown Institution"

    static func sortGroups(lhs: WalletAccountInstitutionGroup, rhs: WalletAccountInstitutionGroup) -> Bool {
        if lhs.title == unknownInstitutionTitle {
            return false
        }
        if rhs.title == unknownInstitutionTitle {
            return true
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func institutionTitle(for account: PlaidAccountValue) -> String {
        account.institutionName?.nilIfBlank ?? unknownInstitutionTitle
    }
}

enum WalletAccountDisplay {
    static func sortAccounts(lhs: PlaidAccountValue, rhs: PlaidAccountValue) -> Bool {
        let lhsInstitution = lhs.institutionName ?? ""
        let rhsInstitution = rhs.institutionName ?? ""
        if lhsInstitution.localizedCaseInsensitiveCompare(rhsInstitution) == .orderedSame {
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return lhsInstitution.localizedCaseInsensitiveCompare(rhsInstitution) == .orderedAscending
    }

    static func subtitle(for account: PlaidAccountValue) -> String? {
        [
            account.institutionName?.nilIfBlank,
            typeLabel(for: account),
            account.lastFourLabel?.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        .nilIfBlank
    }

    static func rowSubtitle(for account: PlaidAccountValue) -> String? {
        let displayName = account.displayName.nilIfBlank
        let type = distinctLabel(typeLabel(for: account), excluding: [displayName])
        let lastFour = distinctLabel(account.lastFourLabel, excluding: [displayName, type])

        return [
            type,
            lastFour
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        .nilIfBlank
    }

    static func typeLabel(for account: PlaidAccountValue) -> String? {
        if let subtype = account.subtype?.nilIfBlank {
            return subtype.capitalized
        }

        let type = account.type.trimmingCharacters(in: .whitespacesAndNewlines)
        if type.isEmpty {
            return nil
        }

        switch type.lowercased() {
        case "depository":
            return "Bank Account"
        default:
            return type.capitalized
        }
    }

    static func iconName(for account: PlaidAccountValue, preferences: WalletAccountPreferences) -> String {
        preferences.customIconName(for: account) ?? iconName(for: account)
    }

    static func iconName(for account: PlaidAccountValue) -> String {
        let key = (account.subtype?.nilIfBlank ?? account.type)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch key {
        case "checking", "cash management", "depository":
            return "building.columns"
        case "savings", "money market":
            return "banknote"
        case "debit card", "prepaid":
            return "rectangle.connected.to.line.below"
        case "brokerage", "investment", "401k", "403b", "ira", "roth", "roth ira", "sep ira":
            return "chart.line.uptrend.xyaxis"
        case "loan", "student", "mortgage", "auto":
            return "banknote.fill"
        default:
            return "wallet.pass"
        }
    }

    static func tint(for account: PlaidAccountValue) -> Color {
        let key = (account.subtype?.nilIfBlank ?? account.type)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch key {
        case "brokerage", "investment", "401k", "403b", "ira", "roth", "roth ira", "sep ira":
            return .purple
        case "debit card", "prepaid":
            return .blue
        case "savings", "money market":
            return Color(red: 0.32, green: 0.54, blue: 0.30)
        case "loan", "student", "mortgage", "auto":
            return MoneyMapDesign.warningGold
        default:
            return MoneyMapDesign.calmGreen
        }
    }

    static func currencyText(_ value: Double?, code: String?) -> String {
        guard let value else { return "Not available" }
        return value.formatted(.currency(code: code ?? "USD"))
    }

    private static func distinctLabel(_ value: String?, excluding excludedValues: [String?]) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        let excludedValues = excludedValues.compactMap { $0?.nilIfBlank }
        guard !excludedValues.contains(where: { value.localizedCaseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }
        return value
    }
}

private struct WalletAccountIconPickerView: View {
    let account: PlaidAccountValue
    let selectedIconName: String
    let save: (String) -> Void
    let reset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var iconName: String

    private let columns = [
        GridItem(.adaptive(minimum: 74), spacing: 10)
    ]

    private let suggestedIcons = [
        "building.columns",
        "banknote",
        "wallet.pass",
        "rectangle.connected.to.line.below",
        "chart.line.uptrend.xyaxis",
        "chart.pie",
        "house",
        "car",
        "graduationcap",
        "creditcard",
        "dollarsign.circle",
        "safe",
        "briefcase",
        "lock.shield"
    ]

    init(
        account: PlaidAccountValue,
        selectedIconName: String,
        save: @escaping (String) -> Void,
        reset: @escaping () -> Void
    ) {
        self.account = account
        self.selectedIconName = selectedIconName
        self.save = save
        self.reset = reset
        _iconName = State(initialValue: selectedIconName)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("SF Symbol", text: $iconName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(account.displayName)
                }

                Section("Suggestions") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(suggestedIcons, id: \.self) { symbolName in
                            Button {
                                iconName = symbolName
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: symbolName)
                                        .font(.title3.weight(.semibold))
                                    Text(symbolName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .foregroundStyle(symbolName == iconName ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(symbolName == iconName ? WalletAccountDisplay.tint(for: account) : Color.primary.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Use Default Icon", role: .destructive) {
                        reset()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(iconName)
                        dismiss()
                    }
                    .disabled(iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
