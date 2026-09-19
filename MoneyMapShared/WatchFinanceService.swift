import Foundation
import SwiftData

public enum BillMutationKind: String, Codable { case payment, delay, skip }

public enum FinanceActionError: LocalizedError {
    case invalidAmount, changed, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Enter a valid amount greater than zero."
        case .changed: return "This item changed. Review its current details and try again."
        case .unavailable: return "This action is no longer available."
        }
    }
}

/// A persisted receipt prevents retried Watch actions from being applied twice.
@Model public final class FinanceActionReceipt {
    public var id: UUID = UUID()
    public var entityID: UUID = UUID()
    public var kind: String = ""
    public var amount: Double = 0
    public var createdAt: Date = Date()
    public var beforeData: Data?
    public var afterData: Data?
    public var undoneAt: Date?
    public init(id: UUID, entityID: UUID, kind: String, amount: Double, before: Data?, after: Data?) {
        self.id = id; self.entityID = entityID; self.kind = kind; self.amount = amount
        beforeData = before; afterData = after
    }
}

public struct BillActionState: Codable, Equatable {
    var name: String?
    var category: BillCategory?
    var recurrenceInterval: Int?
    var recurrenceUnit: RecurrenceUnit?
    var amount: Double?
    var paid: Date?
    var due: Date?
    var status: Status?
    var credit: CreditCardDetails?
    var lifecycle: String?
    public init(_ bill: Bill) {
        name = bill.name; category = bill.category; recurrenceInterval = bill.recurrenceInterval; recurrenceUnit = bill.recurrenceUnit
        amount = bill.amount; paid = bill.datePaid; due = bill.dueDate; status = bill.status
        credit = bill.currentCreditCardDetails; lifecycle = bill.lifecycleStateRaw
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // CreditCardDetails has no Equatable conformance; use deterministic encoding.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
    }
    func restore(_ bill: Bill) {
        bill.amount = amount; bill.datePaid = paid; bill.dueDate = due; bill.status = status
        bill.currentCreditCardDetails = credit; bill.lifecycleStateRaw = lifecycle
    }
}

@MainActor public enum WatchFinanceService {
    public static func refreshRecurringBills(context: ModelContext) throws {
        let today = Calendar.current.startOfDay(for: .now)
        var changed = false
        for bill in try context.fetch(FetchDescriptor<Bill>()) where bill.lifecycleState == .active && (bill.dueDate ?? .distantFuture) < today && (bill.datePaid != nil || bill.autopayEnabled) {
            let before = BillActionState(bill)
            bill.checkStatus()
            changed = changed || before != BillActionState(bill)
        }
        if changed { try context.save() }
    }
    public static func validAmount(_ amount: Double) throws {
        guard amount.isFinite, amount > 0, amount <= 1_000_000_000, abs(amount * 100 - (amount * 100).rounded()) < 0.00001 else { throw FinanceActionError.invalidAmount }
    }
    public static func contains(_ id: UUID, context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<FinanceActionReceipt>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
    @discardableResult public static func billAction(_ bill: Bill, kind: BillMutationKind, amount: Double = 0,
        date: Date? = nil, expected: BillActionState, operationID: UUID, context: ModelContext) throws -> UUID {
        if try contains(operationID, context: context) { return operationID }
        guard BillActionState(bill) == expected else { throw FinanceActionError.changed }
        guard bill.lifecycleState == .active else { throw FinanceActionError.unavailable }
        let encoder = JSONEncoder()
        let before = try encoder.encode(expected)
        switch kind {
        case .payment:
            try validAmount(amount)
            guard bill.datePaid == nil else { throw FinanceActionError.unavailable }
            bill.makePayment(of: amount, operationID: operationID)
        case .delay:
            guard let date, date >= Calendar.current.startOfDay(for: .now) else { throw FinanceActionError.unavailable }
            bill.delay(to: date)
        case .skip:
            guard bill.recurrenceInterval != nil else { throw FinanceActionError.unavailable }
            bill.skipNextOccurrence()
        }
        context.insert(FinanceActionReceipt(id: operationID, entityID: bill.id, kind: kind.rawValue, amount: amount,
            before: before, after: try encoder.encode(BillActionState(bill))))
        context.insert(AuditEvent(eventType: .billPaymentApplied, entityType: .bill, source: .app,
            entityID: bill.id, title: kind == .payment ? "Payment recorded" : "Bill rescheduled",
            summary: bill.name ?? "Bill", amount: kind == .payment ? amount : nil))
        do { try context.save() } catch { context.rollback(); throw error }
        return operationID
    }
    @discardableResult public static func contribute(_ amount: Double, to goal: Goal, expected: Double,
        operationID: UUID, context: ModelContext) throws -> UUID {
        if try contains(operationID, context: context) { return operationID }
        try validAmount(amount)
        guard goal.totalSavedAmount == expected else { throw FinanceActionError.changed }
        guard amount <= goal.remainingAmount else { throw FinanceActionError.unavailable }
        goal.addContribution(amount, operationID: operationID)
        let encoder = JSONEncoder()
        context.insert(FinanceActionReceipt(id: operationID, entityID: goal.id, kind: "contribution", amount: amount,
            before: try encoder.encode(expected), after: try encoder.encode(goal.totalSavedAmount)))
        context.insert(AuditEvent(eventType: .goalContributionApplied, entityType: .goal, source: .app,
            entityID: goal.id, title: "Contribution recorded", summary: goal.name ?? "Goal", amount: amount))
        do { try context.save() } catch { context.rollback(); throw error }
        return operationID
    }
    public static func undo(_ id: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<FinanceActionReceipt>(predicate: #Predicate { $0.id == id })
        guard let receipt = try context.fetch(descriptor).first, receipt.undoneAt == nil,
              let before = receipt.beforeData, let after = receipt.afterData else { throw FinanceActionError.unavailable }
        let entityID = receipt.entityID
        let decoder = JSONDecoder()
        if receipt.kind == "contribution" {
            guard let goal = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == entityID })).first,
                  goal.totalSavedAmount == (try decoder.decode(Double.self, from: after)) else { throw FinanceActionError.changed }
            goal.addContribution(-receipt.amount, operationID: UUID())
        } else {
            guard let bill = try context.fetch(FetchDescriptor<Bill>(predicate: #Predicate { $0.id == entityID })).first,
                  BillActionState(bill) == (try decoder.decode(BillActionState.self, from: after)) else { throw FinanceActionError.changed }
            try decoder.decode(BillActionState.self, from: before).restore(bill)
        }
        receipt.undoneAt = .now
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
