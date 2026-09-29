//
//  MacPlaidAPIClient.swift
//  MoneyMapMac
//
//  Created by Codex on 7/6/26.
//

import Foundation

struct MacPlaidAPIClient {
    static let linkCustomizationNameKey = "plaid.linkCustomizationName"
    let credentials: PlaidStoredCredentials
    var session: URLSession = Self.makeSession()
    var linkCustomizationName: String? = UserDefaults.standard.string(forKey: Self.linkCustomizationNameKey)

    func validateCredentials() async throws {
        _ = try await post(
            path: "/institutions/search",
            body: PlaidInstitutionSearchRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                query: credentials.environment == .sandbox ? "First Platypus Bank" : "Bank",
                products: ["transactions"],
                countryCodes: ["US"]
            ),
            responseType: PlaidInstitutionsResponse.self
        )
    }

    func createHostedLinkSession(
        clientUserID: String,
        accessToken: String? = nil,
        watch: Bool = false,
        phone: Bool = false,
        primaryProduct: String = "transactions"
    ) async throws -> PlaidHostedLinkSession {
        // Update-mode consent must be limited to this exact institution's coverage.
        // Requesting an unsupported product can reject the entire reconnect session.
        var additionalProducts: [String]?
        if let accessToken {
            let linkedItem = try await item(accessToken: accessToken)
            guard let institutionID = linkedItem.institutionID else {
                throw PlaidAPIError.transport("Plaid could not identify this bank's supported data. Try reconnecting again later.")
            }
            let bank = try await institution(id: institutionID)
            guard let supported = bank.products else {
                throw PlaidAPIError.transport("Plaid did not return this bank's supported data. Try reconnecting again later.")
            }
            let eligible = ["liabilities", "investments"].filter { supported.contains($0) }
            additionalProducts = eligible.isEmpty ? nil : eligible
        }
        let response = try await post(
            path: "/link/token/create",
            body: PlaidLinkTokenCreateRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                clientName: "MoneyMap",
                countryCodes: ["US"],
                language: "en",
                linkCustomizationName: linkCustomizationName.flatMap { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                },
                products: accessToken == nil ? [primaryProduct] : nil,
                optionalProducts: accessToken == nil ? ["transactions", "liabilities", "investments"].filter { $0 != primaryProduct } : nil,
                additionalConsentedProducts: additionalProducts,
                transactions: accessToken == nil && primaryProduct == "transactions" ? PlaidTransactionsLinkOptions(daysRequested: 730) : nil,
                user: PlaidLinkUser(clientUserID: clientUserID),
                accessToken: accessToken,
                hostedLink: PlaidHostedLinkOptions(urlLifetimeSeconds: (watch || phone) ? 1800 : 3600, isMobileApp: watch ? true : nil, completionRedirectURI: watch ? "moneymap-watch://bank-complete" : nil)
            ),
            responseType: PlaidLinkTokenCreateResponse.self
        )

        guard let hostedLinkURL = response.hostedLinkURL else {
            throw PlaidAPIError.transport("Plaid created a Link token, but did not return a Hosted Link URL. Check that Hosted Link is available for this Plaid account.")
        }

        return PlaidHostedLinkSession(
            linkToken: response.linkToken,
            hostedLinkURL: hostedLinkURL,
            expiration: PlaidAPIDateParsing.dateTime(response.expiration),
            requestID: response.requestID
        )
    }

    func linkTokenStatus(linkToken: String) async throws -> PlaidLinkTokenStatus {
        let data = try await postData(
            path: "/link/token/get",
            body: PlaidLinkTokenGetRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                linkToken: linkToken
            )
        )
        return PlaidLinkTokenStatus(data: data)
    }

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidItemCredentials {
        let exchange = try await post(
            path: "/item/public_token/exchange",
            body: PlaidPublicTokenExchangeRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                publicToken: publicToken
            ),
            responseType: PlaidPublicTokenExchangeResponse.self
        )

        return PlaidItemCredentials(accessToken: exchange.accessToken, itemID: exchange.itemID)
    }

    func createSandboxItem() async throws -> PlaidItemCredentials {
        let publicToken = try await post(
            path: "/sandbox/public_token/create",
            body: PlaidSandboxPublicTokenRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                institutionID: "ins_109508",
                initialProducts: ["transactions", "liabilities"],
                options: PlaidSandboxPublicTokenOptions(
                    webhook: nil,
                    overrideUsername: "user_transactions_dynamic",
                    overridePassword: "test"
                )
            ),
            responseType: PlaidSandboxPublicTokenResponse.self
        )

        return try await exchangePublicToken(publicToken.publicToken)
    }

    func item(accessToken: String) async throws -> PlaidItemDTO {
        let response = try await post(
            path: "/item/get",
            body: PlaidAccessTokenRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                accessToken: accessToken
            ),
            responseType: PlaidItemResponse.self
        )
        return response.item
    }

    func institution(id: String) async throws -> PlaidInstitutionDTO {
        let response = try await post(
            path: "/institutions/get_by_id",
            body: PlaidInstitutionByIDRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                institutionID: id,
                countryCodes: ["US"]
            ),
            responseType: PlaidInstitutionByIDResponse.self
        )
        return response.institution
    }

    // Prefer live balances; callers explicitly label cached fallback when live retrieval fails.
    func accounts(accessToken: String, cached: Bool = false) async throws -> [PlaidAccountDTO] {
        var body: [String: PlaidJSONValue] = [
            "client_id": .string(credentials.clientID), "secret": .string(credentials.secret),
            "access_token": .string(accessToken)
        ]
        if !cached {
            // Capital One non-depository balances require this field and cannot be requested live.
            // Accept its latest reported value and carry the bank's actual timestamp to the UI.
            // Plaid ignores this option for all other institutions and fetches their balances live.
            body["options"] = .object(["min_last_updated_datetime": .string("1970-01-01T00:00:00Z")])
        }
        return try await post(path: cached ? "/accounts/get" : "/accounts/balance/get", body: body, responseType: PlaidAccountsResponse.self).accounts
    }

    func transactions(accessToken: String, cursor: String?) async throws -> PlaidTransactionsSyncResponse {
        try await post(
            path: "/transactions/sync",
            body: PlaidTransactionsSyncRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                accessToken: accessToken,
                cursor: cursor,
                count: 500
            ),
            responseType: PlaidTransactionsSyncResponse.self
        )
    }

    func liabilities(accessToken: String) async throws -> PlaidLiabilitiesResponse {
        try await post(
            path: "/liabilities/get",
            body: PlaidAccessTokenRequest(
                clientID: credentials.clientID,
                secret: credentials.secret,
                accessToken: accessToken
            ),
            responseType: PlaidLiabilitiesResponse.self
        )
    }

    /// Raw product documents retain every field returned by the bank, including new optional fields.
    func productDocument(path: String, accessToken: String, extra: [String: PlaidJSONValue] = [:]) async throws -> [String: PlaidJSONValue] {
        var body = extra
        body["client_id"] = .string(credentials.clientID)
        body["secret"] = .string(credentials.secret)
        body["access_token"] = .string(accessToken)
        return try await post(path: path, body: body, responseType: [String: PlaidJSONValue].self)
    }

    func investmentTransactions(accessToken: String) async throws -> [String: PlaidJSONValue] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let end = Date.now
        let start = Calendar(identifier: .gregorian).date(byAdding: .month, value: -24, to: end) ?? end
        var transactions: [PlaidJSONValue] = []
        var securities: [String: PlaidJSONValue] = [:]
        var result: [String: PlaidJSONValue] = [:]
        while true {
            result = try await productDocument(path: "/investments/transactions/get", accessToken: accessToken, extra: [
                "start_date": .string(formatter.string(from: start)), "end_date": .string(formatter.string(from: end)),
                "options": .object(["count": .number(500), "offset": .number(Double(transactions.count))])
            ])
            let page = result["investment_transactions"]?.array ?? []
            transactions.append(contentsOf: page)
            for security in result["securities"]?.array ?? [] {
                if let id = security.object?["security_id"]?.string { securities[id] = security }
            }
            let total = Int(result["total_investment_transactions"]?.number ?? Double(transactions.count))
            if transactions.count >= total { break }
            guard !page.isEmpty else { throw PlaidAPIError.transport("Plaid returned an incomplete investment transaction page. Try syncing again.") }
        }
        result["investment_transactions"] = .array(transactions)
        result["securities"] = .array(Array(securities.values))
        return result
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let data = try await postData(path: path, body: body)
        do {
            return try PlaidCoding.decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw PlaidAPIError.decoding(error)
        }
    }

    private func postData<RequestBody: Encodable>(
        path: String,
        body: RequestBody
    ) async throws -> Data {
        var request = URLRequest(url: credentials.environment.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try PlaidCoding.encoder.encode(body)

        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaidAPIError.transport("Plaid did not return an HTTP response.")
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            if let plaidError = try? PlaidCoding.decoder.decode(PlaidErrorResponse.self, from: data) {
                throw PlaidAPIError.plaid(plaidError)
            }
            throw PlaidAPIError.transport("Plaid returned HTTP \(httpResponse.statusCode).")
        }

        return data
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let maximumAttempts = 3
        var lastTransportError: Error?

        for attempt in 1...maximumAttempts {
            do {
                return try await session.data(for: request)
            } catch {
                guard Self.isRetryableTransportError(error), attempt < maximumAttempts else {
                    lastTransportError = error
                    break
                }
                lastTransportError = error
                try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds(for: attempt))
            }
        }

        let detail = lastTransportError?.localizedDescription ?? "The request did not complete."
        throw PlaidAPIError.transport("MoneyMap could not reach Plaid after a few attempts. Check the Mac's network connection and try again. \(detail)")
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }

    private static func isRetryableTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .networkConnectionLost,
             .notConnectedToInternet,
             .resourceUnavailable,
             .secureConnectionFailed,
             .timedOut:
            return true
        default:
            return false
        }
    }

    private static func retryDelayNanoseconds(for attempt: Int) -> UInt64 {
        UInt64(attempt) * 1_500_000_000
    }
}

private enum PlaidCoding {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}

enum PlaidAPIError: LocalizedError {
    case decoding(Error)
    case plaid(PlaidErrorResponse)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .decoding(let error):
            if let decodingError = error as? DecodingError {
                return "MoneyMap could not read Plaid's response: \(decodingError.readableDescription)"
            }
            return "MoneyMap could not read Plaid's response: \(error.localizedDescription)"
        case .plaid(let error):
            let message = error.displayMessage ?? error.errorMessage ?? "Plaid request failed."
            let detail = [error.errorCode, error.requestID].compactMap { $0 }.joined(separator: " • ")
            return detail.isEmpty ? message : "\(message) (\(detail))"
        case .transport(let message):
            return message
        }
    }

    var isTransactionsSyncMutationDuringPagination: Bool {
        guard case .plaid(let error) = self else { return false }
        return error.errorCode == "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION"
    }
}

struct PlaidErrorResponse: Decodable {
    var errorType: String?
    var errorCode: String?
    var errorMessage: String?
    var displayMessage: String?
    var requestID: String?

    enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case displayMessage = "display_message"
        case requestID = "request_id"
    }
}

struct PlaidItemCredentials {
    var accessToken: String
    var itemID: String
}

struct PlaidHostedLinkSession {
    var linkToken: String
    var hostedLinkURL: URL
    var expiration: Date?
    var requestID: String?
}

struct PlaidLinkTokenCreateRequest: Encodable {
    var clientID: String
    var secret: String
    var clientName: String
    var countryCodes: [String]
    var language: String
    var linkCustomizationName: String?
    var products: [String]?
    var optionalProducts: [String]?
    var additionalConsentedProducts: [String]?
    var transactions: PlaidTransactionsLinkOptions?
    var user: PlaidLinkUser
    var accessToken: String?
    var hostedLink: PlaidHostedLinkOptions

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case clientName = "client_name"
        case countryCodes = "country_codes"
        case language
        case linkCustomizationName = "link_customization_name"
        case products
        case optionalProducts = "optional_products"
        case additionalConsentedProducts = "additional_consented_products"
        case transactions
        case user
        case accessToken = "access_token"
        case hostedLink = "hosted_link"
    }
}

struct PlaidTransactionsLinkOptions: Encodable {
    var daysRequested: Int

    enum CodingKeys: String, CodingKey {
        case daysRequested = "days_requested"
    }
}

struct PlaidLinkUser: Encodable {
    var clientUserID: String

    enum CodingKeys: String, CodingKey {
        case clientUserID = "client_user_id"
    }
}

struct PlaidHostedLinkOptions: Encodable {
    var urlLifetimeSeconds: Int
    var isMobileApp: Bool? = nil
    var completionRedirectURI: String? = nil

    enum CodingKeys: String, CodingKey {
        case urlLifetimeSeconds = "url_lifetime_seconds"
        case isMobileApp = "is_mobile_app"
        case completionRedirectURI = "completion_redirect_uri"
    }
}

struct PlaidLinkTokenCreateResponse: Decodable {
    var linkToken: String
    var hostedLinkURL: URL?
    var expiration: String?
    var requestID: String?

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
        case hostedLinkURL = "hosted_link_url"
        case expiration
        case requestID = "request_id"
    }
}

struct PlaidLinkTokenGetRequest: Encodable {
    var clientID: String
    var secret: String
    var linkToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case linkToken = "link_token"
    }
}

struct PlaidLinkTokenStatus {
    var publicTokens: [String]
    var institutionIDs: [String]
    var requestID: String?
    var completedAt: String?
    var finishedAt: String?
    var exitStatus: String?
    var errorCode: String?
    var errorMessage: String?
    var displayMessage: String?
    var rawSummary: String

    var hasSuccessfulCompletion: Bool
    var hasExited: Bool

    init(data: Data) {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        // A token can have more than one session. An earlier exit or success must not determine
        // the result of the session the user has most recently opened.
        let sessions = root["link_sessions"] as? [[String: Any]] ?? []
        let session = sessions.enumerated().max {
            let lhs = $0.element["started_at"] as? String ?? ""
            let rhs = $1.element["started_at"] as? String ?? ""
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }?.element ?? [:]
        let events = session["events"] as? [[String: Any]] ?? []
        let handoff = events.first { $0["event_name"] as? String == "HANDOFF" }
        let exitEvent = events.first { $0["event_name"] as? String == "EXIT" }
        let exit = session["exit"] as? [String: Any] ?? session["on_exit"] as? [String: Any]
        let exitMetadata = exit?["metadata"] as? [String: Any] ?? exitEvent?["event_metadata"] as? [String: Any] ?? [:]
        let error = exit?["error"] as? [String: Any] ?? exitEvent?["event_metadata"] as? [String: Any] ?? [:]
        let results = session["results"] as? [String: Any] ?? [:]
        let itemResults = results["item_add_results"] as? [[String: Any]] ?? []
        // HANDOFF is a documented stable success event; finished_at by itself merely says ended.
        hasSuccessfulCompletion = session["on_success"] is [String: Any] || !itemResults.isEmpty || handoff != nil
        hasExited = exit != nil || exitEvent != nil
        institutionIDs = Self.collectStrings(named: "institution_id", in: session)
        publicTokens = Self.collectStrings(named: "public_token", in: session)
        requestID = root["request_id"] as? String
        finishedAt = session["finished_at"] as? String
        completedAt = hasSuccessfulCompletion ? (finishedAt ?? handoff?["timestamp"] as? String) : nil
        exitStatus = exitMetadata["status"] as? String ?? exitMetadata["exit_status"] as? String
        errorCode = error["error_code"] as? String
        errorMessage = error["error_message"] as? String
        displayMessage = error["display_message"] as? String
        rawSummary = String(data: data, encoding: .utf8) ?? ""
    }

    var hasPublicToken: Bool { !publicTokens.isEmpty }

    var finishedWithoutPublicToken: Bool {
        !hasSuccessfulCompletion && (hasExited || errorCode != nil)
    }

    var userFacingStatusMessage: String {
        if let displayMessage, !displayMessage.isEmpty {
            return displayMessage
        }
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if let errorCode, !errorCode.isEmpty {
            return "Plaid Link finished without a bank token. Error: \(errorCode)."
        }
        if let exitStatus, !exitStatus.isEmpty {
            return "Plaid Link was closed before a bank was connected. Exit status: \(exitStatus)."
        }
        return "Plaid Link finished, but Plaid did not return a public token. Start a new bank connection and try again."
    }

    private static func collectStrings(named key: String, in object: Any) -> [String] {
        var values: [String] = []
        collectStrings(named: key, in: object, into: &values)
        return NSOrderedSet(array: values).compactMap { $0 as? String }
    }

    private static func collectStrings(named key: String, in object: Any, into values: inout [String]) {
        if let dictionary = object as? [String: Any] {
            for (field, value) in dictionary {
                if field == key, let string = value as? String, !string.isEmpty {
                    values.append(string)
                }
                collectStrings(named: key, in: value, into: &values)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectStrings(named: key, in: value, into: &values)
            }
        }
    }
}

struct PlaidInstitutionSearchRequest: Encodable {
    var clientID: String
    var secret: String
    var query: String
    var products: [String]
    var countryCodes: [String]

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case query
        case products
        case countryCodes = "country_codes"
    }
}

struct PlaidInstitutionsResponse: Decodable {
    var institutions: [PlaidInstitutionDTO]
}

struct PlaidInstitutionByIDRequest: Encodable {
    var clientID: String
    var secret: String
    var institutionID: String
    var countryCodes: [String]

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case institutionID = "institution_id"
        case countryCodes = "country_codes"
    }
}

struct PlaidInstitutionByIDResponse: Decodable {
    var institution: PlaidInstitutionDTO
}

struct PlaidInstitutionDTO: Decodable {
    var institutionID: String
    var name: String
    var products: [String]?

    enum CodingKeys: String, CodingKey {
        case institutionID = "institution_id"
        case name, products
    }
}

struct PlaidSandboxPublicTokenRequest: Encodable {
    var clientID: String
    var secret: String
    var institutionID: String
    var initialProducts: [String]
    var options: PlaidSandboxPublicTokenOptions

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case institutionID = "institution_id"
        case initialProducts = "initial_products"
        case options
    }
}

struct PlaidSandboxPublicTokenOptions: Encodable {
    var webhook: String?
    var overrideUsername: String?
    var overridePassword: String?

    enum CodingKeys: String, CodingKey {
        case webhook
        case overrideUsername = "override_username"
        case overridePassword = "override_password"
    }
}

struct PlaidSandboxPublicTokenResponse: Decodable {
    var publicToken: String

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
    }
}

struct PlaidPublicTokenExchangeRequest: Encodable {
    var clientID: String
    var secret: String
    var publicToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case publicToken = "public_token"
    }
}

struct PlaidPublicTokenExchangeResponse: Decodable {
    var accessToken: String
    var itemID: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case itemID = "item_id"
    }
}

struct PlaidAccessTokenRequest: Encodable {
    var clientID: String
    var secret: String
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case accessToken = "access_token"
    }
}

struct PlaidItemResponse: Decodable {
    var item: PlaidItemDTO
}

struct PlaidItemDTO: Decodable {
    var itemID: String
    var institutionID: String?
    var details: [String: PlaidJSONValue]
    init(from decoder: Decoder) throws {
        details = try [String: PlaidJSONValue](from: decoder)
        guard let id = details["item_id"]?.string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing item_id"))
        }
        itemID = id
        institutionID = details["institution_id"]?.string
    }
}

struct PlaidAccountsResponse: Decodable {
    var accounts: [PlaidAccountDTO]
}

struct PlaidAccountDTO: Decodable {
    var accountID: String
    var balances: PlaidBalancesDTO
    var mask: String?
    var name: String
    var officialName: String?
    var subtype: String?
    var type: String

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case balances
        case mask
        case name
        case officialName = "official_name"
        case subtype
        case type
    }
}

struct PlaidBalancesDTO: Decodable {
    var available: Double?
    var current: Double?
    var isoCurrencyCode: String?
    var limit: Double?
    var lastUpdatedDateTime: String?

    enum CodingKeys: String, CodingKey {
        case available
        case current
        case limit
        case lastUpdatedDateTime = "last_updated_datetime"
        case isoCurrencyCode = "iso_currency_code"
    }
}

struct PlaidTransactionsSyncRequest: Encodable {
    var clientID: String
    var secret: String
    var accessToken: String
    var cursor: String?
    var count: Int

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case accessToken = "access_token"
        case cursor
        case count
    }
}

struct PlaidTransactionsSyncResponse: Decodable {
    var added: [PlaidTransactionDTO]
    var modified: [PlaidTransactionDTO]
    var removed: [PlaidRemovedTransactionDTO]
    var nextCursor: String
    var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case added
        case modified
        case removed
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct PlaidTransactionDTO: Decodable {
    var transactionID: String
    var accountID: String
    var name: String
    var merchantName: String?
    var category: [String]?
    var date: String
    var authorizedDate: String?
    var amount: Double
    var isoCurrencyCode: String?
    var pending: Bool
    var pendingTransactionID: String?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case accountID = "account_id"
        case name
        case merchantName = "merchant_name"
        case category
        case date
        case authorizedDate = "authorized_date"
        case amount
        case isoCurrencyCode = "iso_currency_code"
        case pending
        case pendingTransactionID = "pending_transaction_id"
    }
    var details: [String: PlaidJSONValue]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try c.decode(String.self, forKey: .transactionID)
        accountID = try c.decode(String.self, forKey: .accountID)
        name = try c.decode(String.self, forKey: .name)
        merchantName = try c.decodeIfPresent(String.self, forKey: .merchantName)
        category = try c.decodeIfPresent([String].self, forKey: .category)
        date = try c.decode(String.self, forKey: .date)
        authorizedDate = try c.decodeIfPresent(String.self, forKey: .authorizedDate)
        amount = try c.decode(Double.self, forKey: .amount)
        isoCurrencyCode = try c.decodeIfPresent(String.self, forKey: .isoCurrencyCode)
        pending = try c.decode(Bool.self, forKey: .pending)
        pendingTransactionID = try c.decodeIfPresent(String.self, forKey: .pendingTransactionID)
        details = try [String: PlaidJSONValue](from: decoder)
    }

}

struct PlaidRemovedTransactionDTO: Decodable {
    var transactionID: String

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
    }
}

struct PlaidLiabilitiesResponse: Decodable {
    var liabilities: PlaidLiabilitiesDTO
}

struct PlaidLiabilitiesDTO: Decodable {
    var credit: [PlaidCreditLiabilityDTO]?
}

struct PlaidCreditLiabilityDTO: Decodable {
    var accountID: String
    var lastPaymentAmount: Double?
    var lastStatementBalance: Double?
    var nextPaymentDueDate: String?
    var minimumPaymentAmount: Double?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case lastPaymentAmount = "last_payment_amount"
        case lastStatementBalance = "last_statement_balance"
        case nextPaymentDueDate = "next_payment_due_date"
        case minimumPaymentAmount = "minimum_payment_amount"
    }
}

private extension DecodingError {
    var readableDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            let path = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "missing key '\(path)'"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return localizedDescription
        }
    }
}

private enum PlaidAPIDateParsing {
    private static let isoFormatter = ISO8601DateFormatter()

    static func dateTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFormatter.date(from: value)
    }
}
