//
//  RecurringBillDetectorTests.swift
//  MoneyMapTests
//
//  Created by Codex on 7/7/26.
//

import XCTest
@testable import MoneyMap

final class RecurringBillDetectorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDetectsStableMonthlySubscription() {
        let transactions = [
            transaction("StreamBox", amount: 15.99, date: date(2026, 1, 5), category: "Entertainment / Streaming"),
            transaction("StreamBox", amount: 15.99, date: date(2026, 2, 5), category: "Entertainment / Streaming"),
            transaction("StreamBox", amount: 15.99, date: date(2026, 3, 5), category: "Entertainment / Streaming")
        ]

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [],
            today: date(2026, 3, 10),
            calendar: calendar
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.title, "StreamBox")
        XCTAssertEqual(suggestions.first?.amount, 15.99)
        XCTAssertEqual(suggestions.first?.category, .streaming)
        XCTAssertEqual(suggestions.first?.cadence, .monthly)
        XCTAssertEqual(suggestions.first?.nextDueDate, date(2026, 4, 5))
        XCTAssertEqual(suggestions.first?.evidence.count, 3)
    }

    func testEvidenceIncludesTransactionSourceDetails() {
        let card = Bill(
            name: "Apple Card",
            amount: nil,
            dueDate: nil,
            category: .creditCard,
            recurrenceInterval: nil,
            recurrenceUnit: nil,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5_000,
                cardBalance: 200,
                issuerName: "Goldman Sachs",
                lastFourDigits: "1234"
            ),
            plaidAccountID: "account-1"
        )
        let transactions = [
            transaction("StreamBox", amount: 15.99, date: date(2026, 1, 5), category: "Entertainment / Streaming", purchasedBy: "Plaid", creditCard: card, plaidTransactionID: "plaid-tx-1", plaidAccountID: "account-1"),
            transaction("StreamBox", amount: 16.99, date: date(2026, 2, 5), category: "Entertainment / Streaming", purchasedBy: "Plaid", creditCard: card, plaidTransactionID: "plaid-tx-2", plaidAccountID: "account-1"),
            transaction("StreamBox", amount: 15.99, date: date(2026, 3, 5), category: "Entertainment / Streaming", purchasedBy: "Plaid", creditCard: card, plaidTransactionID: "plaid-tx-3", plaidAccountID: "account-1")
        ]

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [card],
            today: date(2026, 3, 10),
            calendar: calendar
        )

        let suggestion = suggestions.first
        XCTAssertEqual(suggestion?.evidence.first?.sourceLabel, "Plaid")
        XCTAssertEqual(suggestion?.evidence.first?.plaidTransactionID, "plaid-tx-1")
        XCTAssertEqual(suggestion?.evidence.first?.plaidAccountID, "account-1")
        XCTAssertEqual(suggestion?.evidence.first?.linkedCardName, "Apple Card")
        XCTAssertEqual(suggestion?.evidence.first?.linkedCardInstitutionName, "Goldman Sachs")
        XCTAssertEqual(suggestion?.evidence.first?.linkedCardLastFourDigits, "1234")
        XCTAssertTrue(suggestion?.amountVaries == true)
        XCTAssertEqual(suggestion?.minimumEvidenceAmount, 15.99)
        XCTAssertEqual(suggestion?.maximumEvidenceAmount, 16.99)
    }

    func testSkipsMerchantsThatAlreadyHaveBills() {
        let transactions = [
            transaction("Cloud Storage", amount: 2.99, date: date(2026, 1, 12)),
            transaction("Cloud Storage", amount: 2.99, date: date(2026, 2, 12)),
            transaction("Cloud Storage", amount: 2.99, date: date(2026, 3, 12))
        ]
        let existingBill = Bill(
            name: "Cloud Storage",
            amount: 2.99,
            dueDate: date(2026, 4, 12),
            category: .software,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [existingBill],
            today: date(2026, 3, 20),
            calendar: calendar
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testCanceledExistingBillStaysReviewableForRestore() {
        let transactions = [
            transaction("Cloud Storage", amount: 2.99, date: date(2026, 1, 12)),
            transaction("Cloud Storage", amount: 2.99, date: date(2026, 2, 12)),
            transaction("Cloud Storage", amount: 2.99, date: date(2026, 3, 12))
        ]
        let existingBill = Bill(
            name: "Cloud Storage",
            amount: 2.99,
            dueDate: date(2026, 1, 12),
            category: .software,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            lifecycleState: .canceled
        )

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [existingBill],
            today: date(2026, 3, 20),
            calendar: calendar
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.matchedBillID, existingBill.id)
        XCTAssertTrue(suggestions.first?.hasCanceledMatch == true)
    }

    func testSkipsAmountMatchedActiveRecurringBill() {
        let transactions = [
            transaction("WELLS FARGO AUTO", amount: 496.13, date: date(2026, 1, 22)),
            transaction("WELLS FARGO AUTO", amount: 496.13, date: date(2026, 2, 22)),
            transaction("WELLS FARGO AUTO", amount: 496.13, date: date(2026, 3, 22))
        ]
        let existingBill = Bill(
            name: "Car Payment",
            amount: 496.13,
            dueDate: date(2026, 4, 22),
            category: .loans,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [existingBill],
            today: date(2026, 3, 25),
            calendar: calendar
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testIgnoresUnstableAmountsAndPayments() {
        let transactions = [
            transaction("Grocery Mart", amount: 42.10, date: date(2026, 1, 6), category: "Groceries"),
            transaction("Grocery Mart", amount: 87.44, date: date(2026, 2, 6), category: "Groceries"),
            transaction("Grocery Mart", amount: 61.20, date: date(2026, 3, 6), category: "Groceries"),
            transaction("Online Payment", amount: 125.00, date: date(2026, 1, 10), category: "Payment"),
            transaction("Online Payment", amount: 125.00, date: date(2026, 2, 10), category: "Payment"),
            transaction("Online Payment", amount: 125.00, date: date(2026, 3, 10), category: "Payment")
        ]

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [],
            today: date(2026, 3, 20),
            calendar: calendar
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testDetectsWeeklyRecurringChargeWithThreeOccurrences() {
        let transactions = [
            transaction("Fitness Club", amount: 9.99, date: date(2026, 3, 1), category: "Membership"),
            transaction("Fitness Club", amount: 9.99, date: date(2026, 3, 8), category: "Membership"),
            transaction("Fitness Club", amount: 9.99, date: date(2026, 3, 15), category: "Membership")
        ]

        let suggestions = RecurringBillDetector.detect(
            transactions: transactions,
            existingBills: [],
            today: date(2026, 3, 16),
            calendar: calendar
        )

        XCTAssertEqual(suggestions.first?.cadence, .weekly)
        XCTAssertEqual(suggestions.first?.nextDueDate, date(2026, 3, 22))
    }

    private func transaction(
        _ merchant: String,
        amount: Double,
        date: Date,
        category: String? = nil,
        purchasedBy: String = "Plaid",
        creditCard: Bill? = nil,
        plaidTransactionID: String? = nil,
        plaidAccountID: String? = nil
    ) -> Transaction {
        Transaction(
            transactionDate: date,
            clearingDate: nil,
            transactionDescription: merchant,
            merchant: merchant,
            category: category,
            type: "Posted",
            amountUSD: amount,
            purchasedBy: purchasedBy,
            creditCard: creditCard,
            friendlyName: merchant,
            plaidTransactionID: plaidTransactionID,
            plaidAccountID: plaidAccountID,
            plaidIsPending: false
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
