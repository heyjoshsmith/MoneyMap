//
//  Transaction.swift
//  MoneyMap
//
//  Created by Josh Smith on 7/11/25.
//

import Foundation
import SwiftData
import SwiftUI

/// Models a credit card transaction based on the provided CSV export.
/// Includes an optional relationship to a credit card (Bill).
@Model public class Transaction {
    
    public var manualAccountID: UUID?
    public var operationID: UUID?
    public var transactionDate: Date?
    public var clearingDate: Date?
    public var transactionDescription: String?
    public var merchant: String?
    public var category: String?
    public var type: String?
    public var amountUSD: Double?
    public var purchasedBy: String?
    public var friendlyName: String?
    public var plaidTransactionID: String?
    public var plaidAccountID: String?
    public var plaidPendingTransactionID: String?
    public var plaidImportedAt: Date?
    public var plaidIsPending: Bool?
    public var linkedBillID: UUID?
    public var plaidEnrichmentJSON: String?
    public var plaidCurrencyCode: String?
    public var plaidOriginalAmount: Double?
    public var plaidBankRemovedAt: Date?
    public var plaidBankSnapshotJSON: String?
    public var plaidBankUpdatedAt: Date?

    /// Source values remain available without treating foreign currency as dollars.
    public var displayAmount: Double? { plaidOriginalAmount ?? amountUSD }
    public var displayCurrencyCode: String {
        plaidCurrencyCode ?? (plaidTransactionID == nil || (amountUSD != nil && plaidOriginalAmount == nil) ? "USD" : "XXX")
    }
    public var displayAmountText: String {
        guard let amount = displayAmount else { return "—" }
        if displayCurrencyCode == "XXX" { return "\(amount.formatted()) (currency unavailable)" }
        return amount.formatted(.currency(code: displayCurrencyCode))
    }

    
    @Relationship public var creditCard: Bill?
    
    public init(transactionDate: String?, clearingDate: String?, transactionDescription: String?, merchant: String?, category: String?, type: String?, amountUSD: Double?, purchasedBy: String?, creditCard: Bill? = nil, friendlyName: String? = nil, plaidTransactionID: String? = nil, plaidAccountID: String? = nil, plaidPendingTransactionID: String? = nil, plaidImportedAt: Date? = nil, plaidIsPending: Bool? = nil, linkedBillID: UUID? = nil) {
        if let transactionDate = transactionDate { self.transactionDate = Transaction.dateFormatter.date(from: transactionDate) } else { self.transactionDate = nil }
        if let clearingDate = clearingDate { self.clearingDate = Transaction.dateFormatter.date(from: clearingDate) } else { self.clearingDate = nil }
        self.transactionDescription = transactionDescription
        self.merchant = merchant
        self.category = category
        self.type = type
        self.amountUSD = amountUSD
        self.purchasedBy = purchasedBy
        self.creditCard = creditCard
        self.friendlyName = friendlyName
        self.plaidTransactionID = plaidTransactionID
        self.plaidAccountID = plaidAccountID
        self.plaidPendingTransactionID = plaidPendingTransactionID
        self.plaidImportedAt = plaidImportedAt
        self.plaidIsPending = plaidIsPending
        self.linkedBillID = linkedBillID
    }

    public init(transactionDate: Date?, clearingDate: Date?, transactionDescription: String?, merchant: String?, category: String?, type: String?, amountUSD: Double?, purchasedBy: String?, creditCard: Bill? = nil, friendlyName: String? = nil, plaidTransactionID: String? = nil, plaidAccountID: String? = nil, plaidPendingTransactionID: String? = nil, plaidImportedAt: Date? = nil, plaidIsPending: Bool? = nil, linkedBillID: UUID? = nil) {
        self.transactionDate = transactionDate
        self.clearingDate = clearingDate
        self.transactionDescription = transactionDescription
        self.merchant = merchant
        self.category = category
        self.type = type
        self.amountUSD = amountUSD
        self.purchasedBy = purchasedBy
        self.creditCard = creditCard
        self.friendlyName = friendlyName
        self.plaidTransactionID = plaidTransactionID
        self.plaidAccountID = plaidAccountID
        self.plaidPendingTransactionID = plaidPendingTransactionID
        self.plaidImportedAt = plaidImportedAt
        self.plaidIsPending = plaidIsPending
        self.linkedBillID = linkedBillID
    }
    
    public static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy" // Adjust as needed for your CSV date format
        return formatter
    }()
}
