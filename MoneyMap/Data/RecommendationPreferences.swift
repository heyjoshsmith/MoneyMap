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

enum RecommendationPreferencesStore {
    private static let suiteName = "group.com.heyjoshsmith.MoneyMap"
    private static let cardStrategyKey = "recommendation_card_strategy"
    private static let paycheckStrategyKey = "recommendation_paycheck_strategy"

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
}
