import XCTest
@testable import MoneyMap

@MainActor
final class BankDataPresentationTests: XCTestCase {
    func testStatementFormattingDoesNotExposeIdentifiersOrNulls() {
        let rows = BankDataPresentation.rows([
            "account_id": "private-account",
            "minimum_payment_amount": 45.75,
            "is_overdue": false,
            "last_payment_date": NSNull(),
            "aprs": [["apr_percentage": 19.5, "apr_type": "purchase_apr"]]
        ])
        XCTAssertFalse(rows.contains { $0.1 == "private-account" })
        XCTAssertFalse(rows.contains { $0.0 == "Last Payment Date" })
        XCTAssertEqual(rows.first?.0, "Minimum Payment")
        XCTAssertEqual(rows.first?.1, 45.75.formatted(.currency(code: "USD")))
        XCTAssertEqual(rows.first { $0.0 == "Overdue" }?.1, "No")
        XCTAssertEqual(rows.first { $0.0.contains("APR") }?.1, 19.5.formatted(.number.precision(.fractionLength(0...6))) + "%")
    }

    func testStatusTimestampUsesCodableReferenceDate() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let rows = BankDataPresentation.rows(["updatedAt": date.timeIntervalSinceReferenceDate])
        XCTAssertEqual(rows.first?.1, date.formatted(date: .abbreviated, time: .shortened))
    }

    func testRecurringDraftUsesAverageAndPreservesForeignCurrency() {
        let draft = BankRecurringDraft(object: [
            "stream_id": "stream", "description": "Payroll", "frequency": "BIWEEKLY",
            "average_amount": ["amount": -1234.56, "iso_currency_code": "CAD"],
            "last_amount": ["amount": -999.0, "iso_currency_code": "USD"]
        ], income: true, currency: "USD")
        XCTAssertEqual(draft.amount, 1234.56)
        XCTAssertEqual(draft.currency, "CAD")
        XCTAssertEqual(draft.frequency, "BIWEEKLY")
        XCTAssertNil(draft.date)
    }

    func testRecurringDraftUsesLastAmountWhenAverageMissing() {
        let draft = BankRecurringDraft(object: [
            "stream_id": "stream", "merchant_name": "Internet", "frequency": "MONTHLY",
            "last_amount": ["amount": 65.0], "predicted_next_date": "2026-10-01"
        ], income: false, currency: "USD")
        XCTAssertEqual(draft.amount, 65)
        XCTAssertEqual(draft.name, "Internet")
        XCTAssertEqual(draft.date.map { Calendar.current.component(.day, from: $0) }, 1)
    }
}
