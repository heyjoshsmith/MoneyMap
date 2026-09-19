//
//  RecommendationPreferences.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import Foundation

enum CreditCardPayoffStrategy: String, CaseIterable, Codable, Identifiable {
    case balanced
    case avalanche
    case snowball
    case dueDate
    case utilization
    case statementBalance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .avalanche:
            return "Avalanche"
        case .snowball:
            return "Snowball"
        case .dueDate:
            return "Due Date"
        case .utilization:
            return "Utilization"
        case .statementBalance:
            return "Statement"
        }
    }

    var description: String {
        switch self {
        case .balanced:
            return "Blend due dates, utilization, APR, and minimums."
        case .avalanche:
            return "Prioritize the highest APR cards first."
        case .snowball:
            return "Prioritize the smallest balances first."
        case .dueDate:
            return "Prioritize bills due the soonest."
        case .utilization:
            return "Reduce cards with the highest utilization first."
        case .statementBalance:
            return "Target current statement balances first."
        }
    }
}

enum PaycheckAllocationStrategy: String, CaseIterable, Codable, Identifiable {
    case balanced
    case debtFirst
    case goalsFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .debtFirst:
            return "Debt First"
        case .goalsFirst:
            return "Goals First"
        }
    }

    var description: String {
        switch self {
        case .balanced:
            return "Cover urgent cards and keep goals moving."
        case .debtFirst:
            return "Lean more cash toward cards before goals."
        case .goalsFirst:
            return "Protect goal progress before extra debt payoff."
        }
    }
}

enum PaycheckCashSource: String, CaseIterable, Codable, Identifiable {
    case manual
    case linkedAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .linkedAccount:
            return "Bank Account"
        }
    }

    var description: String {
        switch self {
        case .manual:
            return "Type the money you have available to allocate right now."
        case .linkedAccount:
            return "Use the balance from the account where your extra money lands."
        }
    }
}

struct PaycheckCashAccount: Identifiable, Hashable {
    let id: UUID
    let accountID: String
    let itemID: String
    let institutionName: String?
    let displayName: String
    let lastFourLabel: String?
    let currentBalance: Double?
    let availableBalance: Double?
    let updatedAt: Date

    init(_ account: PlaidAccountSnapshot) {
        id = account.id
        accountID = account.accountID
        itemID = account.itemID
        institutionName = account.institutionName
        displayName = account.displayName
        lastFourLabel = account.lastFourLabel
        currentBalance = account.currentBalance
        availableBalance = account.availableBalance
        updatedAt = account.updatedAt
    }
}

enum PaycheckCashResolver {
    static func availableCash(
        source: PaycheckCashSource,
        manualAmount: Double,
        selectedAccountID: String?,
        accounts: [PaycheckCashAccount]
    ) -> Double {
        switch source {
        case .manual:
            return max(manualAmount, 0)
        case .linkedAccount:
            guard
                let selectedAccountID,
                let account = accounts.first(where: { $0.accountID == selectedAccountID })
            else {
                return 0
            }

            return balance(for: account)
        }
    }

    static func balance(for account: PaycheckCashAccount) -> Double {
        max(account.availableBalance ?? account.currentBalance ?? 0, 0)
    }
}

enum RecommendationPreferencesStore {
    private static let suiteName = "group.com.heyjoshsmith.MoneyMap"
    private static let cardStrategyKey = "recommendation_card_strategy"
    private static let paycheckStrategyKey = "recommendation_paycheck_strategy"
    private static let paycheckCashSourceKey = "recommendation_paycheck_cash_source"
    private static let paycheckCashAccountIDKey = "recommendation_paycheck_cash_account_id"
    private static let manualSavingsBalanceKey = "recommendation_manual_savings_balance"
    private static let manualSavingsUpdatedAtKey = "recommendation_manual_savings_updated_at"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static var cardStrategy: CreditCardPayoffStrategy {
        get {
            guard
                let rawValue = defaults.string(forKey: cardStrategyKey),
                let strategy = CreditCardPayoffStrategy(rawValue: rawValue)
            else {
                return .balanced
            }
            return strategy
        }
        set {
            defaults.set(newValue.rawValue, forKey: cardStrategyKey)
        }
    }

    static var paycheckStrategy: PaycheckAllocationStrategy {
        get {
            guard
                let rawValue = defaults.string(forKey: paycheckStrategyKey),
                let strategy = PaycheckAllocationStrategy(rawValue: rawValue)
            else {
                return .balanced
            }
            return strategy
        }
        set {
            defaults.set(newValue.rawValue, forKey: paycheckStrategyKey)
        }
    }

    static var paycheckCashSource: PaycheckCashSource {
        get {
            guard
                let rawValue = defaults.string(forKey: paycheckCashSourceKey),
                let source = PaycheckCashSource(rawValue: rawValue)
            else {
                return .manual
            }
            return source
        }
        set {
            defaults.set(newValue.rawValue, forKey: paycheckCashSourceKey)
        }
    }

    static var paycheckCashAccountID: String? {
        get {
            let value = defaults.string(forKey: paycheckCashAccountIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: paycheckCashAccountIDKey)
            } else {
                defaults.removeObject(forKey: paycheckCashAccountIDKey)
            }
        }
    }

    static var manualSavingsBalance: Double {
        get {
            max(defaults.double(forKey: manualSavingsBalanceKey), 0)
        }
        set {
            defaults.set(max(newValue, 0), forKey: manualSavingsBalanceKey)
        }
    }

    static var manualSavingsUpdatedAt: Date? {
        get {
            defaults.object(forKey: manualSavingsUpdatedAtKey) as? Date
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: manualSavingsUpdatedAtKey)
            } else {
                defaults.removeObject(forKey: manualSavingsUpdatedAtKey)
            }
        }
    }
}
