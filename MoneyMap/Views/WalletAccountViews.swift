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

    var body: some View {
        List {
            if sortedAccounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "building.columns",
                    description: Text("Checking, debit, savings, investment, and other synced accounts will appear here after Bank Sync.")
                )
            } else {
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
                                    transactionCount: transactionCount(for: account)
                                )
                            }
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
            }
        }
        .navigationTitle("Accounts")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }

    private var sortedAccounts: [PlaidAccountValue] {
        accounts.sorted(by: WalletAccountDisplay.sortAccounts)
    }

    private var accountGroups: [WalletAccountInstitutionGroup] {
        WalletAccountGrouping.groups(for: sortedAccounts)
    }

    private func transactionCount(for account: PlaidAccountValue) -> Int {
        transactions.filter { $0.plaidAccountID?.nilIfBlank == account.accountID }.count
    }
}

struct WalletAccountDetailView: View {
    let account: PlaidAccountValue
    let plaidAccounts: [PlaidAccountValue]

    @Query private var transactions: [Transaction]

    var body: some View {
        List {
            headerSection
            balanceSection
            transactionsSection
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WalletAccountDisplay.tint(for: account).opacity(0.16))
                    Image(systemName: WalletAccountDisplay.iconName(for: account))
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

    private var accountTransactions: [Transaction] {
        transactions
            .filter { $0.plaidAccountID?.nilIfBlank == account.accountID }
            .sorted { transactionDate(for: $0) > transactionDate(for: $1) }
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

    private func transactionDate(for transaction: Transaction) -> Date {
        transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt ?? .distantPast
    }
}

struct WalletAccountRow: View {
    let account: PlaidAccountValue
    let transactionCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: WalletAccountDisplay.iconName(for: account))
                .foregroundStyle(WalletAccountDisplay.tint(for: account))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle = WalletAccountDisplay.subtitle(for: account) {
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

                Text("\(transactionCount) transaction\(transactionCount == 1 ? "" : "s")")
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
    static func groups(for accounts: [PlaidAccountValue]) -> [WalletAccountInstitutionGroup] {
        let grouped = Dictionary(grouping: accounts, by: institutionTitle(for:))
        return grouped
            .map { title, accounts in
                WalletAccountInstitutionGroup(
                    id: title.lowercased(),
                    title: title,
                    accounts: accounts.sorted(by: WalletAccountDisplay.sortAccounts)
                )
            }
            .sorted { lhs, rhs in
                if lhs.title == unknownInstitutionTitle {
                    return false
                }
                if rhs.title == unknownInstitutionTitle {
                    return true
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static let unknownInstitutionTitle = "Unknown Institution"

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
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
