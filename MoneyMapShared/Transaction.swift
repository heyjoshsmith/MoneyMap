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
    
    public var transactionDate: Date?
    public var clearingDate: Date?
    public var transactionDescription: String?
    public var merchant: String?
    public var category: String?
    public var type: String?
    public var amountUSD: Double?
    public var purchasedBy: String?
    public var friendlyName: String?
    
    @Relationship public var creditCard: Bill?
    
    public init(transactionDate: String?, clearingDate: String?, transactionDescription: String?, merchant: String?, category: String?, type: String?, amountUSD: Double?, purchasedBy: String?, creditCard: Bill? = nil, friendlyName: String? = nil) {
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
    }
    
    public static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy" // Adjust as needed for your CSV date format
        return formatter
    }()
}
