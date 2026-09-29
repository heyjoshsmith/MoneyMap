//
//  ExtraMoneyPlanMatcher.swift
//  MoneyMap
//
//  Created by Codex on 7/22/26.
//

import Foundation
import SwiftData

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

        var usedTransactionKeys = Set(items.compactMap(\.matchedTransactionIDText))
        var matches: [ExtraMoneyPlanTransactionMatch] = []

        for item in items {
            guard
                item.matchedTransactionIDText == nil,
                item.kind != .flexibleCash,
                let planID = item.planID,
                let plan = activePlansByID[planID],
                let match = bestTransactionMatch(for: item, plan: plan, transactions: transactions, calendar: calendar)
            else {
                continue
            }

            let transactionID = transactionKey(for: match)
            guard usedTransactionKeys.insert(transactionID).inserted else {
                continue
            }

            matches.append(ExtraMoneyPlanTransactionMatch(
                planID: planID,
                itemID: item.id,
                transactionID: transactionID,
                transactionName: match.friendlyName ?? match.merchant ?? match.transactionDescription ?? "Transaction",
                matchedAmount: abs(match.amountUSD ?? 0),
                transactionDate: match.transactionDate ?? match.clearingDate
            ))
        }

        return matches
    }

    private static func bestTransactionMatch(
        for item: ExtraMoneyPlanItem,
        plan: ExtraMoneyPlan,
        transactions: [Transaction],
        calendar: Calendar
    ) -> Transaction? {
        transactions
            .filter { transaction in
                guard transaction.plaidIsPending != true, transaction.plaidBankRemovedAt == nil else { return false }
                guard matchesSource(transaction, plan: plan) else { return false }
                guard matchesPaymentPurpose(transaction, item: item) else { return false }
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

    private static func matchesPaymentPurpose(_ transaction: Transaction, item: ExtraMoneyPlanItem) -> Bool {
        guard item.kind == .creditCardPayment else { return true }
        // Plaid represents money leaving a checking account as positive. A refund
        // or incoming transfer must never pay off a plan merely because abs(amount) matches.
        if transaction.plaidTransactionID != nil {
            guard let amount = transaction.amountUSD, amount > 0 else { return false }
        }
        let description = [transaction.transactionDescription, transaction.merchant,
                           transaction.category, transaction.friendlyName]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        let paymentTerms = ["payment", "pymt", "pmt", "autopay"]
        guard paymentTerms.contains(where: description.contains) else { return false }
        if let targetID = item.targetID,
           transaction.linkedBillID == targetID || transaction.creditCard?.id == targetID { return true }
        let target = item.targetNameText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !target.isEmpty && description.contains(target)
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

    static func transactionKey(for transaction: Transaction) -> String {
        if let plaidTransactionID = transaction.plaidTransactionID, !plaidTransactionID.isEmpty {
            return plaidTransactionID
        }

        let dateValue = (transaction.transactionDate ?? transaction.clearingDate)?.timeIntervalSince1970 ?? 0
        let amountValue = transaction.amountUSD ?? 0
        let name = transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "transaction"
        return "\(dateValue)|\(amountValue)|\(name)"
    }
}

struct ExtraMoneyPlanSettlementSummary: Equatable {
    var matchedItemCount: Int = 0
    var paidCardCount: Int = 0
    var completedPlanCount: Int = 0

    var didSettlePayments: Bool {
        matchedItemCount > 0 || paidCardCount > 0 || completedPlanCount > 0
    }
}

enum ExtraMoneyPlanSettlementService {
    @discardableResult
    static func settlePendingPayments(
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> ExtraMoneyPlanSettlementSummary {
        let plans = try context.fetch(FetchDescriptor<ExtraMoneyPlan>())
        let items = try context.fetch(FetchDescriptor<ExtraMoneyPlanItem>())
        let bills = try context.fetch(FetchDescriptor<Bill>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        let summary = settlePendingPayments(
            plans: plans,
            items: items,
            bills: bills,
            transactions: transactions,
            context: context,
            calendar: calendar
        )

        if summary.didSettlePayments {
            try context.save()
        }

        return summary
    }

    @discardableResult
    static func settlePendingPayments(
        plans: [ExtraMoneyPlan],
        items: [ExtraMoneyPlanItem],
        bills: [Bill],
        transactions: [Transaction],
        context: ModelContext? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ExtraMoneyPlanSettlementSummary {
        let appliedPlans = plans.filter { plan in
            plan.status == .active && plan.appliedAt != nil
        }
        guard !appliedPlans.isEmpty else {
            return ExtraMoneyPlanSettlementSummary()
        }

        let cardItems = items.filter { $0.kind == .creditCardPayment }
        let matches = ExtraMoneyPlanMatcher.likelyMatches(
            plans: appliedPlans,
            items: cardItems,
            transactions: transactions,
            calendar: calendar
        )
        let itemsByID = Dictionary(cardItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let transactionsByKey = Dictionary(
            transactions.map { (ExtraMoneyPlanMatcher.transactionKey(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let billsByID = Dictionary(bills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var summary = ExtraMoneyPlanSettlementSummary()

        for match in matches {
            guard
                let item = itemsByID[match.itemID],
                item.matchedTransactionIDText == nil,
                let targetID = item.targetID,
                let bill = billsByID[targetID],
                bill.category == .creditCard,
                let transaction = transactionsByKey[match.transactionID]
            else {
                continue
            }

            let previousBalance = bill.currentCreditCardDetails?.cardBalance
            let previousDatePaid = bill.datePaid
            let previousDueDate = bill.dueDate
            let previousStatus = bill.status

            // A linked bank balance is authoritative. Recording the payment must not
            // subtract a debit that the latest bank snapshot may already include.
            let bankDetails = !bill.plaidUnavailable &&
                bill.plaidAccountID?.isEmpty == false && bill.plaidUpdatedAt != nil
                ? bill.currentCreditCardDetails : nil
            bill.makePayment(of: match.matchedAmount, operationID: item.id)
            if let bankDetails { bill.currentCreditCardDetails = bankDetails }
            if previousStatus == .paid {
                // Keep an explicit earlier paid choice intact; imported corrections
                // cannot tell us whether that choice came from a separate payment.
                bill.datePaid = previousDatePaid
                bill.dueDate = previousDueDate
                bill.status = previousStatus
            } else if let transactionDate = match.transactionDate {
                bill.datePaid = calendar.startOfDay(for: transactionDate)
                bill.status = .paid
            }

            item.matchedTransactionIDText = match.transactionID
            item.matchedAt = now

            if transaction.creditCard == nil {
                transaction.creditCard = bill
            }

            if let context {
                AuditService.logBillPayment(
                    bill: bill,
                    previousBalance: previousBalance,
                    previousDatePaid: previousDatePaid,
                    previousDueDate: previousDueDate,
                    previousStatus: previousStatus,
                    amount: match.matchedAmount,
                    context: context,
                    source: .recommendations,
                    groupID: match.planID
                )
            }

            summary.matchedItemCount += 1
            summary.paidCardCount += 1
        }

        for plan in appliedPlans {
            let planCardItems = cardItems.filter { $0.planID == plan.id }
            guard !planCardItems.isEmpty,
                  planCardItems.allSatisfy({ $0.matchedTransactionIDText != nil }),
                  plan.status == .active else {
                continue
            }

            plan.status = .completed
            plan.completedAt = now
            summary.completedPlanCount += 1
        }

        return summary
    }
}
