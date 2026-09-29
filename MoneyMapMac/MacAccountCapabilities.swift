import Foundation

/// Account-level evidence, rather than a successful bank-level request, determines availability.
struct MacAccountCapability: Identifiable {
    enum Kind: String, CaseIterable {
        case balance, payments, transactions, recurring, holdings, investmentActivity
        var title: String {
            switch self {
            case .balance: "Balance"; case .payments: "Payments & interest"; case .transactions: "Transactions"
            case .recurring: "Recurring activity"; case .holdings: "Holdings"; case .investmentActivity: "Investment activity"
            }
        }
        var symbol: String {
            switch self {
            case .balance: "dollarsign.circle"; case .payments: "calendar.badge.clock"; case .transactions: "list.bullet.rectangle"
            case .recurring: "repeat"; case .holdings: "chart.pie"; case .investmentActivity: "chart.line.uptrend.xyaxis"
            }
        }
        var product: String {
            switch self {
            case .balance: "balance"; case .payments: "liabilities"; case .transactions: "transactions"
            case .recurring: "recurring"; case .holdings: "holdings"; case .investmentActivity: "investment_transactions"
            }
        }
    }
    enum Availability: String {
        case available = "Available", upgrade = "Permission needed", notShared = "Not shared"
        case unsupported = "Not supported", waiting = "Not checked yet", delayed = "Update delayed", empty = "None reported"
    }
    let kind: Kind
    let availability: Availability
    let detail: String
    let checkedAt: Date?
    let dataAt: Date?
    let diagnostic: String?
    var id: String { kind.rawValue }

    static func make(type: String, balance: Double?, accountJSON: String?, connectionJSON: String?, transactionCount: Int) -> [Self] {
        let data = BankDataPresentation.object(accountJSON)
        let connection = PlaidConnectionEnrichment.decode(connectionJSON)
        let statuses = connection?.productStatuses ?? []
        let supportedProducts = connection?.item["institution_supported_products"]?.array?.compactMap(\.string)
        var kinds: [Kind] = [.balance]
        if ["credit", "loan"].contains(type) { kinds.append(.payments) }
        if ["credit", "depository"].contains(type) { kinds += [.transactions, .recurring] }
        if type == "investment" { kinds += [.holdings, .investmentActivity] }
        return kinds.map { kind in
            let status = statuses.first { $0.product == kind.product }
            let diagnostic = status?.diagnosticMessage ?? ""
            let dates = data["productUpdatedAt"] as? [String: Double] ?? [:]
            let dataAt = dates[kind.product].map(Date.init(timeIntervalSinceReferenceDate:))
            let count: Int
            switch kind {
            case .balance: count = balance == nil ? 0 : 1
            case .payments: count = ["creditLiability", "mortgageLiability", "studentLoanLiability"].reduce(0) { $0 + BankDataPresentation.rows(data[$1] as? [String: Any] ?? [:]).count }
            case .transactions: count = transactionCount
            case .recurring: count = (data["recurringInflows"] as? [[String: Any]] ?? []).count + (data["recurringOutflows"] as? [[String: Any]] ?? []).count
            case .holdings: count = (data["holdings"] as? [[String: Any]] ?? []).count
            case .investmentActivity: count = (data["investmentTransactions"] as? [[String: Any]] ?? []).count
            }
            let availability: Availability
            let detail: String
            let optionalProduct = kind == .payments ? "liabilities" : [.holdings, .investmentActivity].contains(kind) ? "investments" : nil
            let institutionUnsupported = optionalProduct.map { product in supportedProducts.map { !$0.contains(product) } ?? false } ?? false
            if institutionUnsupported || diagnostic.contains("PRODUCT_NOT_SUPPORTED") || diagnostic.contains("PRODUCTS_NOT_SUPPORTED") {
                availability = .unsupported; detail = "This bank does not offer this data through Plaid."
            } else if diagnostic.contains("ADDITIONAL_CONSENT_REQUIRED") {
                availability = .upgrade; detail = "Approve additional access to request this data. Your bank stays connected."
            } else if status?.state == "failed" || (kind == .balance && data["balanceSource"] as? String == "cached") {
                availability = .delayed; detail = count > 0 ? "Showing saved data while the next update is unavailable." : "The latest request did not finish. Try a bank refresh."
            } else if count > 0 {
                availability = .available
                switch kind {
                case .balance: detail = "The bank's reported balance."
                case .payments: detail = "Payment and interest details shared for this account."
                default: detail = "\(count) \(kind == .transactions ? "transactions" : kind == .recurring ? "recurring items" : kind == .holdings ? "holdings" : "investment transactions") received."
                }
            } else if status?.state == "available" {
                availability = [.balance, .payments].contains(kind) ? .notShared : .empty
                detail = "The bank was checked, but did not return this data for this account."
            } else if status?.state == "unavailable" {
                availability = .notShared; detail = status?.message ?? "The bank has not shared this data. More permission may not change that."
            } else {
                availability = .waiting; detail = "Refresh this bank to check what it can share."
            }
            return Self(kind: kind, availability: availability, detail: detail, checkedAt: status?.updatedAt, dataAt: dataAt, diagnostic: status?.diagnosticMessage)
        }
    }
}

enum MacBankAccessPresentation {
    static func needsReconnect(status: String?, error: String?, enrichmentJSON: String?) -> Bool {
        let metadata = PlaidConnectionEnrichment.decode(enrichmentJSON)
        let itemError = metadata?.item["error"]?.object?["error_code"]?.string ?? ""
        let diagnostics = ([error ?? "", itemError] + (metadata?.productStatuses.compactMap(\.diagnosticMessage) ?? [])).joined(separator: " ")
        // Product permissions and temporary network failures are not broken authentication.
        return status == "needs_credentials" || ["ITEM_LOGIN_REQUIRED", "INVALID_ACCESS_TOKEN", "ITEM_NOT_FOUND", "ITEM_ACCESS_REVOKED", "USER_PERMISSION_REVOKED"].contains { diagnostics.contains($0) }
    }
}
