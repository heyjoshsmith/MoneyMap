//
//  BillPaymentMatcherTests.swift
//  MoneyMapTests
//
//  Created by Codex on 7/22/26.
//

import XCTest
@testable import MoneyMap

final class BillPaymentMatcherTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCurrentCycleTransactionMarksBillPaid() {
        let bill = Bill(
            name: "StreamBox",
            amount: 15.99,
            dueDate: date(2026, 4, 5),
            category: .streaming,
            recurrenceInterval: nil,
            recurrenceUnit: nil
        )
        let transaction = paymentTransaction(
            merchant: "StreamBox",
            amount: 15.99,
            date: date(2026, 4, 5)
        )

        let didChange = BillPaymentMatcher.refreshStatuses(
            for: [bill],
            transactions: [transaction],
            today: date(2026, 4, 6),
            calendar: calendar
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(bill.status, .paid)
        XCTAssertEqual(bill.datePaid, date(2026, 4, 5))
    }

    func testCurrentCycleMatchRequiresNameOverlap() {
        let bill = Bill(
            name: "StreamBox",
            amount: 15.99,
            dueDate: date(2026, 4, 5),
            category: .streaming,
            recurrenceInterval: nil,
            recurrenceUnit: nil
        )
        let transaction = paymentTransaction(
            merchant: "Corner Grocery",
            amount: 15.99,
            date: date(2026, 4, 5)
        )

        let match = BillPaymentMatcher.currentCyclePaymentTransaction(
            for: bill,
            in: [transaction],
            today: date(2026, 4, 6),
            calendar: calendar
        )

        XCTAssertNil(match)
    }

    func testMatchedHistoryIncludesImportedPaymentWithoutRelationship() {
        let bill = Bill(
            name: "Electric Utility",
            amount: 83.50,
            dueDate: date(2026, 4, 12),
            category: .utilities,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )
        let transaction = paymentTransaction(
            merchant: "Electric Utility",
            amount: 83.50,
            date: date(2026, 4, 12),
            plaidTransactionID: "plaid-utility-1"
        )

        let history = BillPaymentMatcher.matchedHistoryTransactions(
            for: bill,
            in: [transaction],
            calendar: calendar
        )

        XCTAssertEqual(history.map(\.plaidTransactionID), ["plaid-utility-1"])
    }

    func testConnectedHistoryTeachesFutureInPersonTransactionMatch() {
        let bill = Bill(
            name: "Haircut",
            amount: 30,
            dueDate: date(2026, 8, 5),
            category: .personalCare,
            recurrenceInterval: nil,
            recurrenceUnit: nil,
            paymentMode: .inPerson
        )
        let historicalTransaction = paymentTransaction(
            merchant: "Great Clips",
            amount: 30,
            date: date(2026, 7, 5),
            plaidTransactionID: "plaid-haircut-history"
        )
        historicalTransaction.creditCard = bill
        bill.transactions = [historicalTransaction]

        let futureTransaction = paymentTransaction(
            merchant: "Great Clips",
            amount: 30,
            date: date(2026, 8, 5),
            plaidTransactionID: "plaid-haircut-current"
        )

        let didChange = BillPaymentMatcher.refreshStatuses(
            for: [bill],
            transactions: [futureTransaction],
            today: date(2026, 8, 6),
            calendar: calendar
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(bill.status, .paid)
        XCTAssertEqual(bill.datePaid, date(2026, 8, 5))
    }

    private func paymentTransaction(
        merchant: String,
        amount: Double,
        date: Date,
        plaidTransactionID: String? = nil
    ) -> Transaction {
        Transaction(
            transactionDate: date,
            clearingDate: nil,
            transactionDescription: merchant,
            merchant: merchant,
            category: "Bills",
            type: "Posted",
            amountUSD: amount,
            purchasedBy: "Plaid",
            friendlyName: merchant,
            plaidTransactionID: plaidTransactionID,
            plaidIsPending: false
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
