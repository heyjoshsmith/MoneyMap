//
//  TransactionImportTests.swift
//  MoneyMapTests
//
//  Created by Codex on 4/27/26.
//

import XCTest
import SwiftData
@testable import MoneyMapShared

final class TransactionImportTests: XCTestCase {
    func testImportSkipsDuplicateRowsAndReimports() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Bill.self, Transaction.self, configurations: config)
        let context = ModelContext(container)

        let bill = Bill(
            name: "Test Card",
            amount: 100,
            dueDate: .now,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(creditLimit: 1000, cardBalance: 100)
        )
        context.insert(bill)

        let csvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")

        let csv = """
        Transaction Date,Clearing Date,Description,Merchant,Category,Type,Amount (USD),Purchased By
        04-20-2026,04-21-2026,Coffee Shop,Local Cafe,Food,Purchase,5.25,Josh
        04-20-2026,04-21-2026,Coffee Shop,Local Cafe,Food,Purchase,5.25,Josh
        """
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: csvURL) }

        let firstImportCount = try importTransactions(fromCSVAt: csvURL, to: bill, context: context)
        let secondImportCount = try importTransactions(fromCSVAt: csvURL, to: bill, context: context)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        XCTAssertEqual(firstImportCount, 1)
        XCTAssertEqual(secondImportCount, 0)
        XCTAssertEqual(transactions.count, 1)
    }

    func testRecurringAutopayBillRollsForwardToFutureCycle() {
        let calendar = Calendar.current
        let pastDueDate = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now

        let bill = Bill(
            name: "Autopay Utility",
            amount: 80,
            dueDate: pastDueDate,
            category: .utilities,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            autopayEnabled: true
        )

        bill.checkStatus()

        XCTAssertNotNil(bill.dueDate)
        XCTAssertNil(bill.datePaid)
        if case .upcoming(let dueDate) = bill.status {
            XCTAssertGreaterThanOrEqual(calendar.startOfDay(for: dueDate), calendar.startOfDay(for: .now))
        } else {
            XCTFail("Expected recurring autopay bill to be marked upcoming.")
        }
    }

    func testRecurringManualBillMarkedPaidRollsForwardToNextCycle() {
        let calendar = Calendar.current
        let pastDueDate = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now

        let bill = Bill(
            name: "Internet",
            amount: 60,
            dueDate: pastDueDate,
            category: .internet,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )

        bill.datePaid = .now
        bill.status = .paid
        bill.checkStatus()

        XCTAssertNil(bill.datePaid)
        if case .upcoming(let dueDate) = bill.status {
            XCTAssertGreaterThanOrEqual(calendar.startOfDay(for: dueDate), calendar.startOfDay(for: .now))
        } else {
            XCTFail("Expected recurring paid bill to roll forward to an upcoming cycle.")
        }
    }

    func testPaidNonRecurringOverdueBillStaysPaid() {
        let calendar = Calendar.current
        let pastDueDate = calendar.date(byAdding: .day, value: -10, to: .now) ?? .now

        let bill = Bill(
            name: "One-Time Fee",
            amount: 120,
            dueDate: pastDueDate,
            category: .other,
            recurrenceInterval: nil,
            recurrenceUnit: nil
        )

        bill.datePaid = .now
        bill.status = .paid
        bill.checkStatus()

        XCTAssertEqual(bill.status, .paid)
        XCTAssertNotNil(bill.datePaid)
        XCTAssertEqual(calendar.startOfDay(for: bill.dueDate ?? .distantPast), calendar.startOfDay(for: pastDueDate))
    }
}
