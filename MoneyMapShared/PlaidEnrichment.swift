import Foundation

/// Lossless product metadata: optional bank fields survive transport and future API additions.
public enum PlaidJSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: PlaidJSONValue]), array([PlaidJSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: PlaidJSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([PlaidJSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var object: [String: PlaidJSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var array: [PlaidJSONValue]? { if case .array(let v) = self { return v }; return nil }
}

public protocol PlaidEnrichmentPayload: Codable {}
public extension PlaidEnrichmentPayload {
    static func decode(_ json: String?) -> Self? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func encoded() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
}

public struct PlaidProductSyncStatus: Codable, Equatable, Sendable {
    public var product: String
    /// available, unavailable, or failed. Failed/unavailable never erases previously retrieved data.
    public var state: String
    public var message: String?
    public var diagnosticMessage: String?
    public var updatedAt: Date
    public init(product: String, state: String, message: String? = nil, updatedAt: Date = .now, diagnosticMessage: String? = nil) {
        self.product = product; self.state = state; self.message = message; self.updatedAt = updatedAt
        self.diagnosticMessage = diagnosticMessage
    }
}

public struct PlaidConnectionEnrichment: PlaidEnrichmentPayload, Equatable, Sendable {
    public var item: [String: PlaidJSONValue] = [:]
    public var productStatuses: [PlaidProductSyncStatus] = []
    public init() {}
}

public struct PlaidAccountEnrichment: PlaidEnrichmentPayload, Equatable, Sendable {
    public var balanceSource: String?
    public var creditLimit: Double?
    public var creditLiability: [String: PlaidJSONValue]?
    public var mortgageLiability: [String: PlaidJSONValue]?
    public var studentLoanLiability: [String: PlaidJSONValue]?
    public var recurringInflows: [[String: PlaidJSONValue]] = []
    public var recurringOutflows: [[String: PlaidJSONValue]] = []
    public var holdings: [[String: PlaidJSONValue]] = []
    public var securities: [[String: PlaidJSONValue]] = []
    public var investmentTransactions: [[String: PlaidJSONValue]] = []
    public var productUpdatedAt: [String: Date] = [:]
    public init() {}
}

public struct PlaidTransactionEnrichment: PlaidEnrichmentPayload, Equatable, Sendable {
    public var details: [String: PlaidJSONValue] = [:]
    public init(details: [String: PlaidJSONValue] = [:]) { self.details = details }
    public var primaryCategory: String? { details["personal_finance_category"]?.object?["primary"]?.string }
    public var detailedCategory: String? { details["personal_finance_category"]?.object?["detailed"]?.string }
    public var categoryConfidence: String? { details["personal_finance_category"]?.object?["confidence_level"]?.string }
    public var merchantLogoURL: String? { details["logo_url"]?.string }
    public var merchantWebsite: String? { details["website"]?.string }
    public var paymentChannel: String? { details["payment_channel"]?.string }
}
