//
//  ExtraMoneyPlan.swift
//  MoneyMapShared
//
//  Created by Codex on 7/22/26.
//

import Foundation
import SwiftData

public enum ExtraMoneyPlanStatus: String, Codable, CaseIterable {
    case active
    case canceled
    case completed
    case undone

    public var title: String {
        switch self {
        case .active:
            return "Active"
        case .canceled:
            return "Canceled"
        case .completed:
            return "Completed"
        case .undone:
            return "Undone"
        }
    }
}

public enum ExtraMoneyPlanSource: String, Codable, CaseIterable {
    case manual
    case linkedAccount
    case manualSavingsAccount
}

public enum ExtraMoneyPlanItemKind: String, Codable, CaseIterable {
    case creditCardPayment
    case goalContribution
    case flexibleCash
}

@Model
public final class ManualSavingsAccount {
    public var id: UUID = UUID()
    public var nameText: String = "Savings Account"
    public var balanceAmount: Double = 0
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String = "Savings Account",
        balance: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.nameText = name
        self.balanceAmount = max(balance, 0)
        self.updatedAt = updatedAt
    }
}

@Model
public final class ExtraMoneyPlan {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var statusRaw: String = ExtraMoneyPlanStatus.active.rawValue
    public var sourceRaw: String = ExtraMoneyPlanSource.manual.rawValue
    public var sourceAccountIDText: String?
    public var sourceAccountNameText: String?
    public var startingBalanceAmount: Double = 0
    public var alreadyAllocatedAmount: Double = 0
    public var availableAmount: Double = 0
    public var plannedCardAmount: Double = 0
    public var plannedGoalAmount: Double = 0
    public var unallocatedAmount: Double = 0
    public var strategyRaw: String = "balanced"
    public var payoffStrategyRaw: String = "balanced"
    public var appliedAt: Date?
    public var canceledAt: Date?
    public var completedAt: Date?
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        status: ExtraMoneyPlanStatus = .active,
        source: ExtraMoneyPlanSource,
        sourceAccountID: String? = nil,
        sourceAccountName: String? = nil,
        startingBalance: Double,
        alreadyAllocated: Double,
        available: Double,
        plannedCardAmount: Double,
        plannedGoalAmount: Double,
        unallocatedAmount: Double,
        strategyRaw: String,
        payoffStrategyRaw: String,
        appliedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.sourceAccountIDText = sourceAccountID
        self.sourceAccountNameText = sourceAccountName
        self.startingBalanceAmount = max(startingBalance, 0)
        self.alreadyAllocatedAmount = max(alreadyAllocated, 0)
        self.availableAmount = max(available, 0)
        self.plannedCardAmount = max(plannedCardAmount, 0)
        self.plannedGoalAmount = max(plannedGoalAmount, 0)
        self.unallocatedAmount = max(unallocatedAmount, 0)
        self.strategyRaw = strategyRaw
        self.payoffStrategyRaw = payoffStrategyRaw
        self.appliedAt = appliedAt
    }

    public var status: ExtraMoneyPlanStatus {
        get { ExtraMoneyPlanStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var source: ExtraMoneyPlanSource {
        get { ExtraMoneyPlanSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
public final class ExtraMoneyPlanItem {
    public var id: UUID = UUID()
    public var planIDString: String = ""
    public var kindRaw: String = ExtraMoneyPlanItemKind.flexibleCash.rawValue
    public var targetIDString: String?
    public var targetNameText: String = ""
    public var amountValue: Double = 0
    public var rationaleText: String?
    public var matchedTransactionIDText: String?
    public var matchedAt: Date?

    public init(
        id: UUID = UUID(),
        planID: UUID,
        kind: ExtraMoneyPlanItemKind,
        targetID: UUID? = nil,
        targetName: String,
        amount: Double,
        rationale: String? = nil,
        matchedTransactionID: String? = nil,
        matchedAt: Date? = nil
    ) {
        self.id = id
        self.planIDString = planID.uuidString
        self.kindRaw = kind.rawValue
        self.targetIDString = targetID?.uuidString
        self.targetNameText = targetName
        self.amountValue = max(amount, 0)
        self.rationaleText = rationale
        self.matchedTransactionIDText = matchedTransactionID
        self.matchedAt = matchedAt
    }

    public var planID: UUID? {
        get { UUID(uuidString: planIDString) }
        set { planIDString = newValue?.uuidString ?? "" }
    }

    public var targetID: UUID? {
        get { targetIDString.flatMap(UUID.init(uuidString:)) }
        set { targetIDString = newValue?.uuidString }
    }

    public var kind: ExtraMoneyPlanItemKind {
        get { ExtraMoneyPlanItemKind(rawValue: kindRaw) ?? .flexibleCash }
        set { kindRaw = newValue.rawValue }
    }
}
