import XCTest
@testable import MoneyMap

@MainActor
final class BankPresentationConsistencyTests: XCTestCase {
    func testFreshBankDateAndStatusOverrideLocallyPaidPlanningDate() throws {
        let bill = makeLinkedCard()
        let original = bill.dueDate
        bill.datePaid = .now
        bill.status = .paid
        let future = Calendar.current.date(byAdding: .day, value: 12, to: Calendar.current.startOfDay(for: .now))!
        try attachLiability(to: bill, due: future, overdue: false)
        XCTAssertEqual(bill.displayDueDate, future)
        XCTAssertFalse(bill.displayPaymentIsPaid)
        XCTAssertEqual(bill.dueDate, original, "Bank presentation must not rewrite the planning date")
        XCTAssertNotNil(bill.datePaid, "Local payment history is preserved")
    }

    func testFreshBankOverdueUsesBankDateWithoutInventingPaidStatus() throws {
        let bill = makeLinkedCard()
        bill.datePaid = .now
        bill.status = .paid
        let past = Calendar.current.date(byAdding: .day, value: -3, to: Calendar.current.startOfDay(for: .now))!
        try attachLiability(to: bill, due: past, overdue: true)
        XCTAssertEqual(bill.displayDueDate, past)
        XCTAssertFalse(bill.displayPaymentIsPaid)
        XCTAssertEqual(bill.effectiveStatus, .overdue)
    }

    func testStaleOrManualFactsKeepUserPlanningPresentation() throws {
        let bill = makeLinkedCard()
        bill.datePaid = .now
        bill.status = .paid
        let future = Calendar.current.date(byAdding: .day, value: 12, to: .now)!
        try attachLiability(to: bill, due: future, overdue: false, updated: .now.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(bill.displayDueDate, bill.dueDate)
        XCTAssertTrue(bill.displayPaymentIsPaid)
        bill.plaidAccountID = nil
        try attachLiability(to: bill, due: future, overdue: false)
        XCTAssertEqual(bill.displayDueDate, bill.dueDate)
        XCTAssertTrue(bill.displayPaymentIsPaid)
    }

    func testWalletDebtExcludesCreditBalancesAndUnusedAvailableCredit() {
        let values = [Optional(120.0), Optional(0.0), Optional(-50.0), nil].enumerated().map { index, balance in
            PlaidAccountValue(PlaidAccountSnapshot(accountID: "sample-\(index)", itemID: "sample-bank", accountName: "Card", type: "credit", currentBalance: balance, availableBalance: 5000))
        }
        XCTAssertEqual(WalletAccountContributionMode.defaultMode(for: values[0]), .owedBalance)
        XCTAssertEqual(WalletAccountPreferences().owedTotal(in: values), 120)
        XCTAssertEqual(WalletAccountPreferences().ownedAssetTotal(in: values), 0)
    }

    private func makeLinkedCard() -> Bill {
        Bill(name: "Sample Card", amount: 50, dueDate: .now.addingTimeInterval(-20 * 86400), category: .creditCard, recurrenceInterval: nil, recurrenceUnit: nil, creditCardDetails: CreditCardDetails(creditLimit: 1000, cardBalance: 250), plaidAccountID: "sample-card")
    }
    private func attachLiability(to bill: Bill, due: Date, overdue: Bool, updated: Date = .now) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        var enrichment = PlaidAccountEnrichment()
        enrichment.creditLiability = ["next_payment_due_date": .string(formatter.string(from: due)), "is_overdue": .bool(overdue)]
        enrichment.productUpdatedAt["liabilities"] = updated
        bill.plaidEnrichmentJSON = try enrichment.encoded()
    }
}
