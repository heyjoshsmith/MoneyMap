import Foundation

private struct FixtureError: Error, CustomStringConvertible {
    let description: String
}
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FixtureError(description: message) }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var supportedProducts = ["transactions", "liabilities", "investments"]
    static var responder: ((URLRequest, [String: Any]) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data: Data
            if let body = request.httpBody { data = body }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var output = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; output.append(buffer, count: count)
                }
                data = output
            } else { data = Data("{}".utf8) }
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let status: Int
            let json: String
            if request.url?.path == "/item/get" {
                status = 200
                json = #"{"item":{"item_id":"fixture-item","institution_id":"fixture-bank"}}"#
            } else if request.url?.path == "/institutions/get_by_id" {
                try expect(body["institution_id"] as? String == "fixture-bank", "Coverage lookup uses linked institution")
                status = 200
                let data = try JSONSerialization.data(withJSONObject: ["institution": ["institution_id": "fixture-bank", "name": "Fixture Bank", "products": Self.supportedProducts]])
                json = String(decoding: data, as: UTF8.self)
            } else {
                (status, json) = try Self.responder(request, body)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
private struct PlaidAPIFixtures {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = MacPlaidAPIClient(credentials: .init(clientID: "fixture-client", secret: "fixture-secret", environment: .sandbox), session: session, linkCustomizationName: nil)
        var checks = 0
        for name in ["  moneymap-consent  ", "   "] {
            var configuredClient = client
            configuredClient.linkCustomizationName = name
            FixtureProtocol.responder = { _, body in
                try expect(body["link_customization_name"] as? String == (name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "moneymap-consent"), "Customization is trimmed and blank values are omitted")
                try expect(body["additional_consented_products"] as? [String] == ["liabilities", "investments"], "Customized reconnect retains product consent")
                return (200, #"{"link_token":"fixture-link","hosted_link_url":"https://example.com/link"}"#)
            }
            _ = try await configuredClient.createHostedLinkSession(clientUserID: "fixture-user", accessToken: "fixture-access")
            checks += 1
        }


        for primary in ["transactions", "investments", "liabilities"] {
            FixtureProtocol.responder = { request, body in
                try expect(request.url?.path == "/link/token/create", "Link endpoint")
                try expect(body["products"] as? [String] == [primary], "Primary product")
                let optional = Set(body["optional_products"] as? [String] ?? [])
                try expect(optional == Set(["transactions", "investments", "liabilities"].filter { $0 != primary }), "Optional products must not overlap primary")
                try expect(body["additional_consented_products"] == nil, "Initial Link must not request duplicate consent")
                return (200, #"{"link_token":"fixture-link","hosted_link_url":"https://example.com/link"}"#)
            }
            _ = try await client.createHostedLinkSession(clientUserID: "fixture-user", primaryProduct: primary)
            checks += 1
        }
        FixtureProtocol.responder = { _, body in
            try expect(body["products"] == nil && body["optional_products"] == nil && body["transactions"] == nil, "Update mode must omit initial product parameters")
            try expect(Set(body["additional_consented_products"] as? [String] ?? []) == Set(["investments", "liabilities"]), "Update consent products")
            return (200, #"{"link_token":"fixture-link","hosted_link_url":"https://example.com/link"}"#)
        }
        _ = try await client.createHostedLinkSession(clientUserID: "fixture-user", accessToken: "fixture-access")
        checks += 1

        FixtureProtocol.responder = { _, body in
            let hosted = body["hosted_link"] as? [String: Any] ?? [:]
            try expect(hosted["is_mobile_app"] == nil && hosted["completion_redirect_uri"] == nil, "iPhone external Safari reconnect must not require a Dashboard redirect")
            try expect((hosted["url_lifetime_seconds"] as? NSNumber)?.intValue == 1800, "Phone link lifetime")
            try expect(body["products"] == nil && Set(body["additional_consented_products"] as? [String] ?? []) == Set(["liabilities", "investments"]), "Phone reconnect expanded consent")
            return (200, #"{"link_token":"fixture-phone-link","hosted_link_url":"https://secure.plaid.com/hl/fixture"}"#)
        }
        _ = try await client.createHostedLinkSession(clientUserID: "fixture-user", accessToken: "fixture-access", phone: true)
        checks += 1

        for supported in [["transactions", "liabilities"], ["investments"], ["transactions"]] {
            FixtureProtocol.supportedProducts = supported
            FixtureProtocol.responder = { _, body in
                let expected = ["liabilities", "investments"].filter { supported.contains($0) }
                try expect(body["additional_consented_products"] as? [String] == (expected.isEmpty ? nil : expected), "Reconnect only requests supported products, omitting empty consent")
                return (200, #"{"link_token":"fixture-link","hosted_link_url":"https://secure.plaid.com/hl/fixture"}"#)
            }
            _ = try await client.createHostedLinkSession(clientUserID: "fixture-user", accessToken: "fixture-access", phone: true)
            checks += 1
        }
        FixtureProtocol.supportedProducts = ["transactions", "liabilities", "investments"]

        let accounts = #"{"accounts":[{"account_id":"a","name":"Card","type":"credit","balances":{"available":null,"current":null,"limit":1000,"last_updated_datetime":"2026-09-18T12:00:00Z"}}]}"#
        FixtureProtocol.responder = { request, body in
            try expect(request.url?.path == "/accounts/balance/get", "Live Balance endpoint")
            let options = body["options"] as? [String: Any]
            try expect(options?["min_last_updated_datetime"] as? String == "1970-01-01T00:00:00Z", "Capital One required timestamp option")
            return (200, accounts)
        }
        let live = try await client.accounts(accessToken: "fixture-access")
        try expect(live.count == 1 && live[0].balances.current == nil && live[0].balances.limit == 1000, "Nullable balances / actual limit")
        try expect(live[0].balances.lastUpdatedDateTime == "2026-09-18T12:00:00Z", "Bank source timestamp retained")
        checks += 1

        FixtureProtocol.responder = { request, body in
            if request.url?.path == "/accounts/balance/get" {
                return (400, #"{"error_code":"PRODUCT_NOT_SUPPORTED","error_message":"Balance not available"}"#)
            }
            try expect(request.url?.path == "/accounts/get" && body["options"] == nil, "Cached accounts endpoint must omit Balance options")
            return (200, accounts)
        }
        do { _ = try await client.accounts(accessToken: "fixture-access"); throw FixtureError(description: "Expected Balance error") }
        catch let error as PlaidAPIError {
            guard case .plaid(let details) = error else { throw error }
            try expect(details.errorCode == "PRODUCT_NOT_SUPPORTED", "Plaid failure detail retained")
            _ = try await client.accounts(accessToken: "fixture-access", cached: true)
        }
        checks += 1

        var offsets: [Int] = []
        FixtureProtocol.responder = { request, body in
            try expect(request.url?.path == "/investments/transactions/get", "Investment endpoint")
            let options = body["options"] as? [String: Any] ?? [:]
            let offset = (options["offset"] as? NSNumber)?.intValue ?? -1
            offsets.append(offset)
            try expect((options["count"] as? NSNumber)?.intValue == 500, "Investment page size")
            try expect(body["start_date"] != nil && body["end_date"] != nil, "Investment window")
            return (200, "{\"investment_transactions\":[{\"investment_transaction_id\":\"t\(offset)\",\"account_id\":\"a\",\"security_id\":\"s\(offset)\"}],\"securities\":[{\"security_id\":\"s\(offset)\",\"name\":\"Security\"}],\"total_investment_transactions\":2}")
        }
        let investments = try await client.investmentTransactions(accessToken: "fixture-access")
        try expect(offsets == [0, 1], "Pagination offsets use actual page length")
        try expect(investments["investment_transactions"]?.array?.count == 2 && investments["securities"]?.array?.count == 2, "Investment pages and securities merged")
        checks += 1
        FixtureProtocol.responder = { _, _ in (200, #"{"investment_transactions":[],"securities":[],"total_investment_transactions":2}"#) }
        do { _ = try await client.investmentTransactions(accessToken: "fixture-access"); throw FixtureError(description: "Expected incomplete pagination failure") }
        catch let error as PlaidAPIError {
            guard case .transport = error else { throw error }
        }
        checks += 1

        FixtureProtocol.responder = { _, _ in
            (200, #"{"added":[{"transaction_id":"t","account_id":"a","name":"Cafe","date":"2026-09-19","amount":2.5,"pending":false,"personal_finance_category":{"primary":"FOOD","confidence_level":"VERY_HIGH"},"counterparties":[{"name":"Cafe"}],"location":{"lat":40.1},"payment_channel":"in store"}],"modified":[],"removed":[],"next_cursor":"cursor","has_more":false}"#)
        }
        let transactions = try await client.transactions(accessToken: "fixture-access", cursor: nil)
        let metadata = PlaidTransactionEnrichment(details: transactions.added[0].details)
        try expect(metadata.categoryConfidence == "VERY_HIGH" && metadata.paymentChannel == "in store", "Rich fields retained")
        try expect(transactions.added[0].merchantName == nil, "Missing optional transaction fields decode")
        let serialized = try metadata.encoded()
        try expect(PlaidTransactionEnrichment.decode(serialized) == metadata, "Cloud enrichment round trip")
        checks += 1
        var cursorRequests: [String?] = []
        FixtureProtocol.responder = { request, body in
            try expect(request.url?.path == "/transactions/sync", "Backfill uses transaction sync")
            cursorRequests.append(body["cursor"] as? String)
            return (200, #"{"added":[],"modified":[],"removed":[{"transaction_id":"removed-since-old-cursor"}],"next_cursor":"committed-cursor","has_more":false}"#)
        }
        let delta = try await client.transactions(accessToken: "fixture-access", cursor: "old-cursor")
        let full = try await client.transactions(accessToken: "fixture-access", cursor: nil)
        try expect(cursorRequests.count == 2 && cursorRequests[0] == "old-cursor" && cursorRequests[1] == nil, "Incremental and backfill request cursor encoding")
        try expect(delta.removed.first?.transactionID == "removed-since-old-cursor" && full.nextCursor == "committed-cursor", "Removal and replacement cursor decoded")
        checks += 1
        // Shapes and stable event names follow /link/token/get and Link Web documentation.
        let linkCases: [(String, String, Bool, Bool)] = [
            ("update HANDOFF", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","finished_at":"2026-09-19T10:01:00Z","events":[{"event_name":"ERROR","event_metadata":{"error_code":"INVALID_CREDENTIALS"}},{"event_name":"HANDOFF","timestamp":"2026-09-19T10:01:00Z"}]}]}"#, true, false),
            ("legacy update on_success", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","finished_at":"2026-09-19T10:01:00Z","on_success":{"public_token":"","metadata":{}}}]}"#, true, false),
            ("modern add results", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","results":{"item_add_results":[{"public_token":"public-fixture"}]}}]}"#, true, false),
            ("canceled exit", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","finished_at":"2026-09-19T10:01:00Z","exit":{"error":null,"metadata":{"status":"requires_oauth"}}}]}"#, false, true),
            ("still open", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","finished_at":null,"events":[{"event_name":"OPEN"}]}]}"#, false, false),
            ("finished without outcome yet", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","finished_at":"2026-09-19T10:01:00Z"}]}"#, false, false),
            ("new session after old success", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","on_success":{"public_token":"old-token"}},{"started_at":"2026-09-19T11:00:00Z","finished_at":null}]}"#, false, false),
            ("success after earlier session exit", #"{"link_sessions":[{"started_at":"2026-09-19T10:00:00Z","exit":{"metadata":{"status":"requires_credentials"}}},{"started_at":"2026-09-19T11:00:00Z","events":[{"event_name":"HANDOFF","timestamp":"2026-09-19T11:01:00Z"}]}]}"#, true, false)
        ]
        for (name, response, succeeded, exited) in linkCases {
            FixtureProtocol.responder = { request, _ in
                try expect(request.url?.path == "/link/token/get", "Link status endpoint")
                return (200, response)
            }
            let status = try await client.linkTokenStatus(linkToken: "fixture-link")
            try expect(status.hasSuccessfulCompletion == succeeded, "\(name): success state")
            try expect(status.finishedWithoutPublicToken == exited, "\(name): exit state")
            if name == "new session after old success" { try expect(status.publicTokens.isEmpty, "Old public token must not leak into current session") }
            checks += 1
        }
        print("PASS: \(checks) Mac Plaid API fixture scenarios (actual API source; intercepted URLSession; no live credentials).")
    }
}
