//
//  ExtraMoneyPlanMatcher.swift
//  MoneyMap
//
//  Created by Codex on 7/22/26.
//

import Foundation

struct ExtraMoneyPlanTransactionMatch: Equatable {
    let planID: UUID
    let itemID: UUID
    let transactionID: String
    let transactionName: String
    let matchedAmount: Double
    let transactionDate: Date?
}

enum ExtraMoneyPlanMatcher {
    static func likelyMatches(
        plans: [ExtraMoneyPlan],
        items: [ExtraMoneyPlanItem],
        transactions: [Transaction],
        calendar: Calendar = .current
    ) -> [ExtraMoneyPlanTransactionMatch] {
        let activePlansByID = Dictionary(
            uniqueKeysWithValues: plans.compactMap { plan -> (UUID, ExtraMoneyPlan)? in
                guard plan.status == .active else { return nil }
                return (plan.id, plan)
            }
        )

        return items.compactMap { item in
            guard
                item.matchedTransactionIDText == nil,
                item.kind != .flexibleCash,
                let planID = item.planID,
                let plan = activePlansByID[planID],
                let match = bestTransactionMatch(for: item, plan: plan, transactions: transactions, calendar: calendar)
            else {
                return nil
            }

            return ExtraMoneyPlanTransactionMatch(
                planID: planID,
                itemID: item.id,
                transactionID: transactionKey(for: match),
                transactionName: match.friendlyName ?? match.merchant ?? match.transactionDescription ?? "Transaction",
                matchedAmount: abs(match.amountUSD ?? 0),
                transactionDate: match.transactionDate ?? match.clearingDate
            )
        }
    }

    private static func bestTransactionMatch(
        for item: ExtraMoneyPlanItem,
        plan: ExtraMoneyPlan,
        transactions: [Transaction],
        calendar: Calendar
    ) -> Transaction? {
        transactions
            .filter { transaction in
                guard matchesSource(transaction, plan: plan) else { return false }
                guard matchesAmount(transaction.amountUSD, plannedAmount: item.amountValue) else { return false }
                guard matchesDate(transaction.transactionDate ?? transaction.clearingDate, planCreatedAt: plan.createdAt, calendar: calendar) else { return false }
                return true
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.transactionDate ?? lhs.clearingDate ?? .distantPast
                let rhsDate = rhs.transactionDate ?? rhs.clearingDate ?? .distantPast
                return lhsDate > rhsDate
            }
            .first
    }

    private static func matchesSource(_ transaction: Transaction, plan: ExtraMoneyPlan) -> Bool {
        guard plan.source == .linkedAccount else { return true }
        guard let sourceAccountID = plan.sourceAccountIDText else { return false }
        return transaction.plaidAccountID == sourceAccountID
    }

    private static func matchesAmount(_ transactionAmount: Double?, plannedAmount: Double) -> Bool {
        guard let transactionAmount else { return false }
        let actual = abs(transactionAmount)
        let tolerance = max(1, plannedAmount * 0.05)
        return abs(actual - plannedAmount) <= tolerance
    }

    private static func matchesDate(_ transactionDate: Date?, planCreatedAt: Date, calendar: Calendar) -> Bool {
        guard let transactionDate else { return false }
        let earliest = calendar.date(byAdding: .day, value: -1, to: planCreatedAt) ?? planCreatedAt
        return transactionDate >= earliest
    }

    private static func transactionKey(for transaction: Transaction) -> String {
        if let plaidTransactionID = transaction.plaidTransactionID, !plaidTransactionID.isEmpty {
            return plaidTransactionID
        }

        let dateValue = (transaction.transactionDate ?? transaction.clearingDate)?.timeIntervalSince1970 ?? 0
        let amountValue = transaction.amountUSD ?? 0
        let name = transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "transaction"
        return "\(dateValue)|\(amountValue)|\(name)"
    }
}
