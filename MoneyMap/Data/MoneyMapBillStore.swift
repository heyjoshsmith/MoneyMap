//
//  MoneyMapBillStore.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation
import SwiftData

enum MoneyMapBillStore {
    static func makeContext() throws -> ModelContext {
        let container = try SharedModelContainerFactory.make()
        return ModelContext(container)
    }

    static func fetchBills() throws -> [Bill] {
        let context = try makeContext()
        let bills = try context.fetch(FetchDescriptor<Bill>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let didChange = refreshStatuses(for: bills, transactions: transactions)
        if didChange {
            try context.save()
        }
        return bills
    }

    static func fetchBill(id: UUID) throws -> Bill? {
        let context = try makeContext()
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate<Bill> { $0.id == id })
        return try context.fetch(descriptor).first
    }

    static func fetchNextDueUnpaidBill() throws -> Bill? {
        let today = Calendar.current.startOfDay(for: Date())

        return try fetchBills()
            .filter {
                guard $0.datePaid == nil, let dueDate = $0.dueDate else { return false }
                return Calendar.current.startOfDay(for: dueDate) >= today
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first
    }

    static func fetchMostUtilizedCard() throws -> Bill? {
        return try fetchBills()
            .filter { $0.category == .creditCard }
            .sorted {
                ($0.creditCardDetails?.utilization ?? 0) > ($1.creditCardDetails?.utilization ?? 0)
            }
            .first
    }

    @discardableResult
    static func addBill(
        name: String,
        amount: Double?,
        dueDate: Date,
        category: BillCategory,
        recurrenceInterval: Int,
        recurrenceUnit: RecurrenceUnit,
        autopayEnabled: Bool,
        notes: String? = nil,
        autopaySource: String? = nil,
        gracePeriodDays: Int? = nil,
        paymentURLString: String? = nil,
        creditLimit: Double? = nil,
        cardBalance: Double? = nil,
        annualPercentageRate: Double? = nil,
        minimumPayment: Double? = nil,
        statementBalance: Double? = nil
    ) throws -> Bill {
        let context = try makeContext()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let creditDetails: CreditCardDetails?
        if category == .creditCard {
            creditDetails = CreditCardDetails(
                creditLimit: max(creditLimit ?? 0, 0),
                cardBalance: max(cardBalance ?? 0, 0),
                annualPercentageRate: annualPercentageRate,
                minimumPayment: minimumPayment,
                statementBalance: statementBalance
            )
        } else {
            creditDetails = nil
        }

        let bill = Bill(
            name: trimmedName.isEmpty ? nil : trimmedName,
            amount: amount.map { max($0, 0) },
            dueDate: dueDate,
            category: category,
            recurrenceInterval: max(recurrenceInterval, 1),
            recurrenceUnit: recurrenceUnit,
            creditCardDetails: creditDetails,
            autopayEnabled: autopayEnabled,
            notes: notes,
            autopaySource: autopaySource,
            gracePeriodDays: gracePeriodDays,
            paymentURLString: paymentURLString
        )
        bill.checkStatus()
        context.insert(bill)
        AuditService.logBillCreated(bill, context: context)
        try context.save()
        return bill
    }

    @discardableResult
    static func markPaid(billID: UUID, amount: Double?) throws -> Bill {
        let context = try makeContext()
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate<Bill> { $0.id == billID })
        guard let bill = try context.fetch(descriptor).first else {
            throw NSError(
                domain: "MoneyMap.BillStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Bill not found."]
            )
        }

        if let amount, amount > 0, bill.category == .creditCard {
            let previousBalance = bill.creditCardDetails?.cardBalance
            let previousDatePaid = bill.datePaid
            let previousDueDate = bill.dueDate
            let previousStatus = bill.status
            bill.makePayment(of: amount)
            AuditService.logBillPayment(
                bill: bill,
                previousBalance: previousBalance,
                previousDatePaid: previousDatePaid,
                previousDueDate: previousDueDate,
                previousStatus: previousStatus,
                amount: amount,
                context: context,
                source: .app
            )
        } else {
            let previousDatePaid = bill.datePaid
            let previousDueDate = bill.dueDate
            let previousStatus = bill.status
            bill.datePaid = .now
            bill.status = .paid
            bill.checkStatus()
            AuditService.logBillPayment(
                bill: bill,
                previousBalance: bill.creditCardDetails?.cardBalance,
                previousDatePaid: previousDatePaid,
                previousDueDate: previousDueDate,
                previousStatus: previousStatus,
                amount: amount ?? bill.amount ?? 0,
                context: context,
                source: .app
            )
        }

        try context.save()
        AppRefreshEvents.notifyBillsDidChange()
        return bill
    }

    @discardableResult
    static func payRecommendedAmount(billID: UUID) throws -> Bill {
        let context = try makeContext()
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate<Bill> { $0.id == billID })
        guard let bill = try context.fetch(descriptor).first else {
            throw NSError(
                domain: "MoneyMap.BillStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Bill not found."]
            )
        }

        let recommended = max(bill.creditCardDetails?.recommendedPayment ?? 0, 0)
        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status
        if recommended > 0 {
            bill.makePayment(of: recommended)
        } else {
            bill.datePaid = .now
            bill.status = .paid
            bill.checkStatus()
        }
        AuditService.logBillPayment(
            bill: bill,
            previousBalance: previousBalance,
            previousDatePaid: previousDatePaid,
            previousDueDate: previousDueDate,
            previousStatus: previousStatus,
            amount: recommended > 0 ? recommended : (bill.amount ?? 0),
            context: context,
            source: .app
        )

        try context.save()
        AppRefreshEvents.notifyBillsDidChange()
        return bill
    }

    @discardableResult
    private static func refreshStatuses(for bills: [Bill], transactions: [Transaction]) -> Bool {
        BillPaymentMatcher.refreshStatuses(for: bills, transactions: transactions)
    }
}
