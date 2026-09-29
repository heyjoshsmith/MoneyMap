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

    func testBatchRefreshMatchesIndividualSelectionWithLargeHistory() {
        let bills = (0..<32).map { index in
            Bill(name: "Utility vendor \(index)", amount: Double(100 + index), dueDate: date(2026, 4, 5),
                 category: .utilities, recurrenceInterval: nil, recurrenceUnit: nil)
        }
        var transactions = (0..<3400).map { _ in
            paymentTransaction(merchant: "Old merchant", amount: 10, date: date(2025, 4, 5))
        }
        for bill in bills {
            let payment = paymentTransaction(merchant: "Direct", amount: bill.amount!, date: date(2026, 4, 5))
            payment.linkedBillID = bill.id
            transactions.append(payment)
        }
        let start = Date()
        XCTAssertTrue(BillPaymentMatcher.refreshStatuses(for: bills, transactions: transactions,
                                                        today: date(2026, 4, 6), calendar: calendar))
        XCTAssertTrue(bills.allSatisfy { $0.status == .paid && $0.datePaid == date(2026, 4, 5) })
        print("PERFORMANCE: 32 bills against 3432 payments: \(Date().timeIntervalSince(start)) seconds")
    }

    func testNewestDirectPaymentWinsOverNewerTextMatchAndOldHistory() {
        let bill = Bill(name: "StreamBox", amount: 15.99, dueDate: date(2026, 4, 5),
                        category: .streaming, recurrenceInterval: nil, recurrenceUnit: nil)
        let old = paymentTransaction(merchant: "StreamBox", amount: 15.99, date: date(2025, 4, 5))
        let direct = paymentTransaction(merchant: "Custom label", amount: 15.99, date: date(2026, 4, 4))
        direct.linkedBillID = bill.id
        let newerDirect = paymentTransaction(merchant: "Custom label", amount: 15.99, date: date(2026, 4, 5))
        newerDirect.linkedBillID = bill.id
        let inferred = paymentTransaction(merchant: "StreamBox", amount: 15.99, date: date(2026, 4, 6))
        XCTAssertTrue(BillPaymentMatcher.currentCyclePaymentTransaction(
            for: bill, in: [inferred, direct, old, newerDirect],
            today: date(2026, 4, 6), calendar: calendar) === newerDirect)
        XCTAssertTrue(BillPaymentMatcher.currentCyclePaymentTransaction(
            for: bill, in: [old, inferred], today: date(2026, 4, 6), calendar: calendar) === inferred)
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

    func testBankRemovedTransactionCannotMarkBillPaidEvenIfAmountRemains() {
        let bill = Bill(name: "StreamBox", amount: 15.99, dueDate: date(2026, 4, 5),
                        category: .streaming, recurrenceInterval: nil, recurrenceUnit: nil)
        let transaction = paymentTransaction(merchant: "StreamBox", amount: 15.99, date: date(2026, 4, 5))
        transaction.plaidBankRemovedAt = date(2026, 4, 6)
        XCTAssertNil(BillPaymentMatcher.currentCyclePaymentTransaction(
            for: bill, in: [transaction], today: date(2026, 4, 6), calendar: calendar))
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
