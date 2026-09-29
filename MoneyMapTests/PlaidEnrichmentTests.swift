import XCTest
@testable import MoneyMap

@MainActor
final class PlaidEnrichmentTests: XCTestCase {
    func testRichBankMetadataSurvivesCloudJSONRoundTrip() throws {
        let raw = #"{"personal_finance_category":{"primary":"FOOD_AND_DRINK","detailed":"FOOD_AND_DRINK_COFFEE","confidence_level":"VERY_HIGH"},"counterparties":[{"name":"Cafe","type":"merchant"}],"location":{"lat":40.2,"lon":-73.9},"payment_channel":"in store","website":"example.com","future_field":null}"#
        let details = try JSONDecoder().decode([String: PlaidJSONValue].self, from: Data(raw.utf8))
        let payload = PlaidTransactionEnrichment(details: details)
        let decoded = try XCTUnwrap(PlaidTransactionEnrichment.decode(payload.encoded()))
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.categoryConfidence, "VERY_HIGH")
        XCTAssertEqual(decoded.paymentChannel, "in store")
        XCTAssertEqual(decoded.details["location"]?.object?["lat"]?.number, 40.2)
        XCTAssertEqual(decoded.details["future_field"], .null)
    }

    func testIndependentProductFreshnessAndLiabilityValuesRoundTrip() throws {
        var account = PlaidAccountEnrichment()
        account.creditLimit = 12_000
        account.creditLiability = ["minimum_payment_amount": .number(25), "is_overdue": .bool(false), "aprs": .array([.object(["apr_percentage": .number(19.99), "apr_type": .string("purchase_apr")])])]
        account.productUpdatedAt["liabilities"] = Date(timeIntervalSince1970: 100)
        account.productUpdatedAt["holdings"] = Date(timeIntervalSince1970: 200)
        let decoded = try XCTUnwrap(PlaidAccountEnrichment.decode(account.encoded()))
        XCTAssertEqual(decoded, account)
        XCTAssertEqual(decoded.creditLiability?["is_overdue"]?.bool, false)
        XCTAssertNotEqual(decoded.productUpdatedAt["liabilities"], decoded.productUpdatedAt["holdings"])
    }
}
