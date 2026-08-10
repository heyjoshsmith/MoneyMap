//
//  WalletAccountPreferences.swift
//  MoneyMap
//
//  Created by Codex on 8/9/26.
//

import Foundation
import SwiftUI

struct WalletAccountPreferences: Codable, Equatable {
    static let appStorageKey = "walletAccountPreferences.v1"
    static let emptyJSON = "{}"

    var hiddenAccountIDs: [String] = []
    var groupOrder: [String] = []
    var accountOrderByGroupID: [String: [String]] = [:]
    var iconNameByAccountID: [String: String] = [:]
    var contributionModeByAccountID: [String: WalletAccountContributionMode] = [:]
    var showsAvailableMoneyOnWalletTile = false

    static func decode(from value: String) -> WalletAccountPreferences {
        guard let data = value.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(WalletAccountPreferences.self, from: data) else {
            return WalletAccountPreferences()
        }

        return preferences
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8) else {
            return Self.emptyJSON
        }

        return value
    }

    func isHidden(_ account: PlaidAccountValue) -> Bool {
        hiddenAccountIDs.contains(account.accountID)
    }

    func customIconName(for account: PlaidAccountValue) -> String? {
        iconNameByAccountID[account.accountID]?.trimmedNonEmpty
    }

    func contributionMode(for account: PlaidAccountValue) -> WalletAccountContributionMode {
        contributionModeByAccountID[account.accountID] ?? .defaultMode(for: account)
    }

    mutating func setHidden(_ hidden: Bool, for account: PlaidAccountValue) {
        if hidden {
            appendUnique(account.accountID, to: &hiddenAccountIDs)
        } else {
            hiddenAccountIDs.removeAll { $0 == account.accountID }
        }
    }

    mutating func setIconName(_ iconName: String?, for account: PlaidAccountValue) {
        guard let iconName = iconName?.trimmedNonEmpty else {
            iconNameByAccountID[account.accountID] = nil
            return
        }

        iconNameByAccountID[account.accountID] = iconName
    }

    mutating func setContributionMode(_ mode: WalletAccountContributionMode, for account: PlaidAccountValue) {
        contributionModeByAccountID[account.accountID] = mode == .defaultMode(for: account) ? nil : mode
    }

    mutating func moveGroups(from source: IndexSet, to destination: Int, currentGroups: [WalletAccountInstitutionGroup]) {
        var ids = currentGroups.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        groupOrder = ids
    }

    mutating func moveAccounts(in group: WalletAccountInstitutionGroup, from source: IndexSet, to destination: Int) {
        var ids = group.accounts.map(\.accountID)
        ids.move(fromOffsets: source, toOffset: destination)
        accountOrderByGroupID[group.id] = ids
    }

    func orderedGroups(_ groups: [WalletAccountInstitutionGroup]) -> [WalletAccountInstitutionGroup] {
        let order = orderMap(for: groupOrder)
        return groups.sorted { lhs, rhs in
            switch (order[lhs.id], order[rhs.id]) {
            case let (lhsIndex?, rhsIndex?):
                return lhsIndex < rhsIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return WalletAccountGrouping.sortGroups(lhs: lhs, rhs: rhs)
            }
        }
    }

    func orderedAccounts(_ accounts: [PlaidAccountValue], inGroupID groupID: String) -> [PlaidAccountValue] {
        guard let accountOrder = accountOrderByGroupID[groupID], !accountOrder.isEmpty else {
            return accounts.sorted(by: WalletAccountDisplay.sortAccounts)
        }

        let order = orderMap(for: accountOrder)
        return accounts.sorted { lhs, rhs in
            switch (order[lhs.accountID], order[rhs.accountID]) {
            case let (lhsIndex?, rhsIndex?):
                return lhsIndex < rhsIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return WalletAccountDisplay.sortAccounts(lhs: lhs, rhs: rhs)
            }
        }
    }

    func availableMoneyTotal(in accounts: [PlaidAccountValue]) -> Double {
        accounts.reduce(0) { total, account in
            guard !isHidden(account), contributionMode(for: account) == .availableCash else {
                return total
            }

            return total + max(account.availableBalance ?? account.currentBalance ?? 0, 0)
        }
    }

    func ownedAssetTotal(in accounts: [PlaidAccountValue]) -> Double {
        accounts.reduce(0) { total, account in
            guard !isHidden(account) else { return total }
            let mode = contributionMode(for: account)
            guard mode == .availableCash || mode == .ownedAsset else { return total }
            return total + max(account.currentBalance ?? account.availableBalance ?? 0, 0)
        }
    }

    func owedTotal(in accounts: [PlaidAccountValue]) -> Double {
        accounts.reduce(0) { total, account in
            guard !isHidden(account), contributionMode(for: account) == .owedBalance else {
                return total
            }

            return total + abs(account.currentBalance ?? account.availableBalance ?? 0)
        }
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private func orderMap(for values: [String]) -> [String: Int] {
        values.enumerated().reduce(into: [:]) { result, pair in
            if result[pair.element] == nil {
                result[pair.element] = pair.offset
            }
        }
    }
}

enum WalletAccountContributionMode: String, Codable, CaseIterable, Identifiable {
    case availableCash
    case ownedAsset
    case owedBalance
    case excluded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .availableCash:
            return "Available Cash"
        case .ownedAsset:
            return "Owned Asset"
        case .owedBalance:
            return "Owed Balance"
        case .excluded:
            return "Ignore"
        }
    }

    var detail: String {
        switch self {
        case .availableCash:
            return "Counts toward available money."
        case .ownedAsset:
            return "Counts as yours, but not spendable cash."
        case .owedBalance:
            return "Tracks money you owe."
        case .excluded:
            return "Hides from account totals."
        }
    }

    var systemImage: String {
        switch self {
        case .availableCash:
            return "checkmark.circle"
        case .ownedAsset:
            return "chart.line.uptrend.xyaxis"
        case .owedBalance:
            return "minus.circle"
        case .excluded:
            return "eye.slash"
        }
    }

    static func defaultMode(for account: PlaidAccountValue) -> WalletAccountContributionMode {
        let key = (account.subtype?.trimmedNonEmpty ?? account.type)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch key {
        case "checking", "savings", "cash management", "money market", "depository":
            return .availableCash
        case "brokerage", "investment", "401k", "403b", "ira", "roth", "roth ira", "sep ira":
            return .ownedAsset
        case "loan", "student", "mortgage", "auto":
            return .owedBalance
        default:
            return .ownedAsset
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
