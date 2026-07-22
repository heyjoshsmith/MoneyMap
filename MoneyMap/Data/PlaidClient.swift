//
//  PlaidClient.swift
//  MoneyMap
//
//  Created by Codex on 7/5/26.
//

import Foundation

struct PlaidHostedLinkSession: Decodable {
    let linkToken: String
    let hostedLinkUrl: String
    let expiration: String?
    let requestId: String?

    var hostedURL: URL? {
        URL(string: hostedLinkUrl)
    }
}

struct PlaidExchangeResult: Decodable {
    let itemId: String
    let institutionId: String?
    let institutionName: String?
    let requestId: String?
}

struct PlaidSyncResponse: Decodable {
    let results: [PlaidItemSyncResult]
    let snapshot: PlaidSnapshot
}

struct PlaidItemSyncResult: Decodable {
    let itemId: String
    let accountCount: Int?
    let addedTransactions: Int?
    let modifiedTransactions: Int?
    let removedTransactions: Int?
    let liabilityCount: Int?
    let liabilityError: String?
    let error: String?
}

struct PlaidSnapshot: Decodable {
    let connections: [PlaidConnectionDTO]
    let accounts: [PlaidAccountDTO]
    let transactions: [PlaidTransactionDTO]
    let liabilities: [PlaidLiabilityDTO]
}

struct PlaidConnectionDTO: Decodable, Identifiable {
    var id: String { itemId }

    let itemId: String
    let institutionId: String?
    let institutionName: String?
    let transactionsCursor: String?
    let status: String?
    let errorMessage: String?
    let createdAt: String?
    let updatedAt: String?
    let lastSyncAt: String?
}

struct PlaidAccountDTO: Decodable, Identifiable {
    var id: String { accountId }

    let accountId: String
    let itemId: String
    let institutionName: String?
    let name: String?
    let officialName: String?
    let mask: String?
    let type: String?
    let subtype: String?
    let currentBalance: Double?
    let availableBalance: Double?
    let currencyCode: String?
    let updatedAt: String?

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (officialName ?? "Plaid Account") : trimmed
    }

    var paymentMethodType: PaymentMethodType {
        switch subtype {
        case "checking":
            return .checking
        case "savings", "money market":
            return .savings
        case "credit card":
            return .creditCard
        default:
            switch type {
            case "depository":
                return .checking
            case "credit":
                return .creditCard
            default:
                return .other
            }
        }
    }
}

struct PlaidTransactionDTO: Decodable, Identifiable {
    var id: String { transactionId }

    let transactionId: String
    let itemId: String
    let accountId: String
    let pendingTransactionId: String?
    let date: String?
    let authorizedDate: String?
    let name: String?
    let merchantName: String?
    let category: String?
    let amount: Double?
    let pending: Bool
    let paymentChannel: String?
    let currencyCode: String?
    let updatedAt: String?

    var displayMerchant: String {
        let merchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let merchant, !merchant.isEmpty {
            return merchant
        }

        return name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : "Plaid Transaction"
    }
}

struct PlaidLiabilityDTO: Decodable, Identifiable {
    var id: String { liabilityId }

    let liabilityId: String
    let itemId: String
    let accountId: String
    let type: String
    let currentBalance: Double?
    let creditLimit: Double?
    let minimumPaymentAmount: Double?
    let nextPaymentDueDate: String?
    let lastStatementBalance: Double?
    let lastStatementIssueDate: String?
    let aprPercentage: Double?
    let updatedAt: String?
}

struct PlaidClient {
    var baseURL: URL

    func createHostedLinkToken() async throws -> PlaidHostedLinkSession {
        try await post("/api/plaid/link-token", body: EmptyRequest())
    }

    func completeHostedLink(linkToken: String) async throws -> PlaidExchangeResult {
        try await post("/api/plaid/complete-hosted-link", body: HostedLinkCompletionRequest(linkToken: linkToken))
    }

    func createSandboxConnection() async throws -> PlaidExchangeResult {
        try await post("/api/plaid/sandbox-public-token", body: EmptyRequest())
    }

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidExchangeResult {
        try await post("/api/plaid/exchange-public-token", body: PublicTokenExchangeRequest(publicToken: publicToken))
    }

    func sync() async throws -> PlaidSyncResponse {
        try await post("/api/plaid/sync", body: EmptyRequest())
    }

    func snapshot(limit: Int = 200) async throws -> PlaidSnapshot {
        try await get("/api/plaid/snapshot?limit=\(limit)")
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "GET"
        return try await run(request)
    }

    private func post<Response: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await run(request)
    }

    private func run<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaidClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let serverError = try? JSONDecoder().decode(PlaidServerError.self, from: data)
            throw PlaidClientError.server(serverError?.error ?? "Plaid server returned HTTP \(httpResponse.statusCode).")
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(trimmedBase)/\(trimmedPath)")!
    }
}

private struct EmptyRequest: Encodable {}

private struct HostedLinkCompletionRequest: Encodable {
    let linkToken: String
}

private struct PublicTokenExchangeRequest: Encodable {
    let publicToken: String
}

private struct PlaidServerError: Decodable {
    let error: String
}

enum PlaidClientError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Plaid server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}
