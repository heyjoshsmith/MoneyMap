//
//  AuditService.swift
//  MoneyMap
//
//  Created by Codex on 5/6/26.
//

import Foundation
import SwiftData

enum AuditService {
    static func logGoalCreated(_ goal: Goal, context: ModelContext, source: AuditSource = .app) {
        let title = "Created goal \(goal.name ?? "Goal")"
        let summary = "Target \(MoneyMapFormatters.currencyString(for: goal.targetAmount ?? 0))."
        insert(
            AuditEvent(
                eventType: .goalCreated,
                entityType: .goal,
                source: source,
                entityID: goal.id,
                title: title,
                summary: summary,
                amount: goal.targetAmount,
                undoKind: .deleteGoal
            ),
            into: context
        )
    }

    static func logBillCreated(_ bill: Bill, context: ModelContext, source: AuditSource = .app) {
        let entityType: AuditEntityType = bill.category == .creditCard ? .creditCard : .bill
        let amount = bill.category == .creditCard ? bill.creditCardDetails?.cardBalance : bill.amount
        let title = "Created \(bill.name ?? "Bill")"
        let summary = bill.category == .creditCard
            ? "Starting balance \(MoneyMapFormatters.currencyString(for: bill.creditCardDetails?.cardBalance ?? 0))."
            : "Due amount \(MoneyMapFormatters.currencyString(for: bill.amount ?? 0))."
        insert(
            AuditEvent(
                eventType: .billCreated,
                entityType: entityType,
                source: source,
                entityID: bill.id,
                title: title,
                summary: summary,
                amount: amount,
                undoKind: .deleteBill
            ),
            into: context
        )
    }

    static func logPaydayUpdated(previous: Date?, new: Date, context: ModelContext, source: AuditSource = .app) {
        let summary: String
        if let previous {
            summary = "Changed from \(MoneyMapFormatters.mediumDateString(for: previous)) to \(MoneyMapFormatters.mediumDateString(for: new))."
        } else {
            summary = "Set next payday to \(MoneyMapFormatters.mediumDateString(for: new))."
        }
        insert(
            AuditEvent(
                eventType: .paydayUpdated,
                entityType: .payday,
                source: source,
                title: "Updated next payday",
                summary: summary,
                oldDateValue: previous
            ),
            into: context
        )
    }

    static func logGoalContribution(
        goal: Goal,
        previousAmountSaved: Double,
        contributionAmount: Double,
        context: ModelContext,
        source: AuditSource = .app,
        groupID: UUID? = nil
    ) {
        guard contributionAmount != 0 else { return }
        let summary = contributionAmount >= 0
            ? "Added \(MoneyMapFormatters.currencyString(for: contributionAmount)) to \(goal.name ?? "Goal")."
            : "Removed \(MoneyMapFormatters.currencyString(for: abs(contributionAmount))) from \(goal.name ?? "Goal")."
        insert(
            AuditEvent(
                eventType: .goalContributionApplied,
                entityType: .goal,
                source: source,
                entityID: goal.id,
                groupID: groupID,
                title: "Updated goal savings",
                summary: summary,
                amount: contributionAmount,
                undoKind: .revertGoalAmountSaved,
                oldDoubleValue: previousAmountSaved
            ),
            into: context
        )
    }

    static func logGoalTotalAdjusted(
        goal: Goal,
        previousAmountSaved: Double,
        newAmountSaved: Double,
        context: ModelContext,
        source: AuditSource = .app
    ) {
        let delta = newAmountSaved - previousAmountSaved
        let summary = "Changed saved total from \(MoneyMapFormatters.currencyString(for: previousAmountSaved)) to \(MoneyMapFormatters.currencyString(for: newAmountSaved))."
        insert(
            AuditEvent(
                eventType: .goalTotalAdjusted,
                entityType: .goal,
                source: source,
                entityID: goal.id,
                title: "Adjusted goal total",
                summary: summary,
                amount: delta,
                undoKind: .revertGoalAmountSaved,
                oldDoubleValue: previousAmountSaved
            ),
            into: context
        )
    }

    static func logBillPayment(
        bill: Bill,
        previousBalance: Double?,
        previousDatePaid: Date?,
        previousDueDate: Date?,
        previousStatus: Status?,
        amount: Double,
        context: ModelContext,
        source: AuditSource = .app,
        groupID: UUID? = nil
    ) {
        guard amount != 0 else { return }
        let entityType: AuditEntityType = bill.category == .creditCard ? .creditCard : .bill
        let title = bill.category == .creditCard ? "Paid down \(bill.name ?? "Card")" : "Marked \(bill.name ?? "Bill") paid"
        let summary = "Applied \(MoneyMapFormatters.currencyString(for: amount)) to \(bill.name ?? "item")."
        insert(
            AuditEvent(
                eventType: .billPaymentApplied,
                entityType: entityType,
                source: source,
                entityID: bill.id,
                groupID: groupID,
                title: title,
                summary: summary,
                amount: amount,
                undoKind: .revertBillPayment,
                oldDoubleValue: previousBalance,
                oldDateValue: previousDatePaid,
                oldAuxDateValue: previousDueDate,
                oldStatusRaw: statusRaw(previousStatus),
                oldStatusDateValue: statusDate(previousStatus)
            ),
            into: context
        )
    }

    static func logRecommendationBatch(
        cardCount: Int,
        goalCount: Int,
        totalAmount: Double,
        context: ModelContext,
        groupID: UUID
    ) {
        insert(
            AuditEvent(
                eventType: .recommendationBatchApplied,
                entityType: .recommendations,
                source: .recommendations,
                groupID: groupID,
                title: "Applied recommendation plan",
                summary: "Updated \(cardCount) card\(cardCount == 1 ? "" : "s") and \(goalCount) goal\(goalCount == 1 ? "" : "s").",
                amount: totalAmount
            ),
            into: context
        )
    }

    static func undo(_ event: AuditEvent, context: ModelContext) throws {
        guard event.canUndo, let undoKind = event.undoKind else { return }

        switch undoKind {
        case .deleteBill:
            guard let billID = event.entityID,
                  let bill = try fetchBill(id: billID, context: context) else { return }
            context.delete(bill)
        case .deleteGoal:
            guard let goalID = event.entityID,
                  let goal = try fetchGoal(id: goalID, context: context) else { return }
            context.delete(goal)
        case .revertGoalAmountSaved:
            guard let goalID = event.entityID,
                  let goal = try fetchGoal(id: goalID, context: context),
                  let previousAmountSaved = event.oldDoubleValue else { return }
            goal.amountSaved = previousAmountSaved
        case .revertBillPayment:
            guard let billID = event.entityID,
                  let bill = try fetchBill(id: billID, context: context) else { return }
            if let previousBalance = event.oldDoubleValue, bill.category == .creditCard {
                bill.creditCardDetails?.cardBalance = previousBalance
            }
            bill.datePaid = event.oldDateValue
            bill.dueDate = event.oldAuxDateValue
            bill.status = status(fromRaw: event.oldStatusRaw, date: event.oldStatusDateValue)
        }

        event.undoneAt = Date()
        insert(
            AuditEvent(
                eventType: .undoPerformed,
                entityType: event.entityType,
                source: .app,
                entityID: event.entityID,
                groupID: event.groupID,
                title: "Undid \(event.titleText.lowercased())",
                summary: event.summaryText
            ),
            into: context
        )
        try context.save()
    }

    private static func insert(_ event: AuditEvent, into context: ModelContext) {
        context.insert(event)
    }

    private static func fetchBill(id: UUID, context: ModelContext) throws -> Bill? {
        try context.fetch(FetchDescriptor<Bill>(predicate: #Predicate<Bill> { $0.id == id })).first
    }

    private static func fetchGoal(id: UUID, context: ModelContext) throws -> Goal? {
        try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate<Goal> { $0.id == id })).first
    }

    private static func statusRaw(_ status: Status?) -> String? {
        switch status {
        case .paid:
            return "paid"
        case .overdue:
            return "overdue"
        case .upcoming:
            return "upcoming"
        case nil:
            return nil
        }
    }

    private static func statusDate(_ status: Status?) -> Date? {
        if case .upcoming(let date) = status {
            return date
        }
        return nil
    }

    private static func status(fromRaw rawValue: String?, date: Date?) -> Status? {
        switch rawValue {
        case "paid":
            return .paid
        case "overdue":
            return .overdue
        case "upcoming":
            return date.map(Status.upcoming)
        default:
            return nil
        }
    }
}
