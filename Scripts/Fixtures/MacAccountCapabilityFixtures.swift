import Foundation

@main struct MacAccountCapabilityFixtures {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: message, code: 1) }
        }
        func metadata(_ product: String, _ state: String, _ diagnostic: String? = nil) throws -> String {
            var value = PlaidConnectionEnrichment()
            value.productStatuses = [.init(product: product, state: state, diagnosticMessage: diagnostic)]
            return try value.encoded()
        }
        func capabilities(_ type: String = "credit", _ balance: Double? = 0, _ json: String? = nil, _ bank: String? = nil) -> [MacAccountCapability] {
            MacAccountCapability.make(type: type, balance: balance, accountJSON: json, connectionJSON: bank, transactionCount: 0)
        }
        let credit = capabilities()
        try check(credit.first?.availability == .available, "Zero bank balance remains available")
        try check(!credit.contains { $0.kind == .holdings }, "Credit cards do not show irrelevant investment products")
        let investment = capabilities("investment")
        try check(investment.contains { $0.kind == .holdings } && !investment.contains { $0.kind == .payments }, "Investments show relevant capabilities")
        let consent = try metadata("liabilities", "unavailable", "ADDITIONAL_CONSENT_REQUIRED")
        try check(capabilities("credit", 0, nil, consent).first { $0.kind == .payments }?.availability == .upgrade, "Missing consent offers upgrade")
        try check(!MacBankAccessPresentation.needsReconnect(status: "active", error: nil, enrichmentJSON: consent), "Missing consent is not broken authentication")
        let shared = try metadata("liabilities", "available")
        try check(capabilities("credit", 0, #"{"creditLiability":{"account_id":"a","minimum_payment_amount":null}}"#, shared).first { $0.kind == .payments }?.availability == .notShared, "Bank-wide success and null fields do not imply account data")
        try check(capabilities("credit", 0, #"{"creditLiability":{"minimum_payment_amount":0,"is_overdue":false}}"#, shared).first { $0.kind == .payments }?.availability == .available, "Zero payment and false overdue are real data")
        let cached = capabilities("credit", 25, #"{"balanceSource":"cached"}"#)
        try check(cached.first?.availability == .delayed, "Cached balance is labeled delayed")
        let unsupported = try metadata("liabilities", "unavailable", "PRODUCT_NOT_SUPPORTED")
        try check(capabilities("credit", 0, nil, unsupported).first { $0.kind == .payments }?.availability == .unsupported, "Unsupported products do not offer an upgrade")
        let transactions = try metadata("transactions", "available")
        try check(capabilities("credit", 0, nil, transactions).first { $0.kind == .transactions }?.availability == .empty, "No transactions is not an access failure")
        try check(!MacBankAccessPresentation.needsReconnect(status: "needs_attention", error: "Network timed out", enrichmentJSON: nil), "Temporary failures do not require reconnect")
        try check(MacBankAccessPresentation.needsReconnect(status: "needs_attention", error: "ITEM_LOGIN_REQUIRED", enrichmentJSON: nil), "Expired authentication requires reconnect")
        var limitedBank = PlaidConnectionEnrichment()
        limitedBank.item["institution_supported_products"] = .array([.string("transactions")])
        limitedBank.productStatuses = [.init(product: "liabilities", state: "unavailable", diagnosticMessage: "ADDITIONAL_CONSENT_REQUIRED")]
        let limitedJSON = try limitedBank.encoded()
        try check(capabilities("credit", 0, nil, limitedJSON).first { $0.kind == .payments }?.availability == .unsupported, "Institution coverage prevents impossible upgrades")
        print("PASS: 13 account capability and connection-intent checks")
    }
}
