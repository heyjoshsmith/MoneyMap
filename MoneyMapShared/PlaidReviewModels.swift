//
//  PlaidReviewModels.swift
//  MoneyMapShared
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

public enum PlaidReviewStatus: String, CaseIterable, Codable {
    case ready
    case imported
    case skipped
}

@Model
public class PlaidTransactionReviewItem: Identifiable {
    public var id: UUID = UUID()
    public var plaidTransactionID: String = ""
    public var plaidAccountID: String = ""
    public var plaidItemID: String = ""
    public var name: String = ""
    public var merchantName: String?
    public var category: String?
    public var date: Date?
    public var authorizedDate: Date?
    public var amount: Double = 0
    public var currencyCode: String?
    public var pending: Bool = false
    public var pendingTransactionID: String?
    public var statusRaw: String = PlaidReviewStatus.ready.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        plaidTransactionID: String,
        plaidAccountID: String,
        plaidItemID: String,
        name: String,
        merchantName: String? = nil,
        category: String? = nil,
        date: Date? = nil,
        authorizedDate: Date? = nil,
        amount: Double,
        currencyCode: String? = nil,
        pending: Bool = false,
        pendingTransactionID: String? = nil,
        status: PlaidReviewStatus = .ready,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.plaidTransactionID = plaidTransactionID
        self.plaidAccountID = plaidAccountID
        self.plaidItemID = plaidItemID
        self.name = name
        self.merchantName = merchantName
        self.category = category
        self.date = date
        self.authorizedDate = authorizedDate
        self.amount = amount
        self.currencyCode = currencyCode
        self.pending = pending
        self.pendingTransactionID = pendingTransactionID
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var status: PlaidReviewStatus {
        get { PlaidReviewStatus(rawValue: statusRaw) ?? .ready }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    public var displayName: String {
        let merchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let merchant, !merchant.isEmpty {
            return merchant
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Plaid transaction" : name
    }
}

public enum PlaidSuggestionKind: String, CaseIterable, Codable {
    case paymentMethod
    case creditCardBill
}

@Model
public class PlaidSuggestion: Identifiable {
    public var id: UUID = UUID()
    public var kindRaw: String = PlaidSuggestionKind.paymentMethod.rawValue
    public var plaidAccountID: String = ""
    public var plaidItemID: String = ""
    public var title: String = ""
    public var detail: String?
    public var amount: Double?
    public var dueDate: Date?
    public var statusRaw: String = PlaidReviewStatus.ready.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        kind: PlaidSuggestionKind,
        plaidAccountID: String,
        plaidItemID: String,
        title: String,
        detail: String? = nil,
        amount: Double? = nil,
        dueDate: Date? = nil,
        status: PlaidReviewStatus = .ready,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.plaidAccountID = plaidAccountID
        self.plaidItemID = plaidItemID
        self.title = title
        self.detail = detail
        self.amount = amount
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var kind: PlaidSuggestionKind {
        get { PlaidSuggestionKind(rawValue: kindRaw) ?? .paymentMethod }
        set {
            kindRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    public var status: PlaidReviewStatus {
        get { PlaidReviewStatus(rawValue: statusRaw) ?? .ready }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
