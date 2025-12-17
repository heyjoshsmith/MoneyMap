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
@Model class Transaction {
    
    var transactionDate: Date?
    var clearingDate: Date?
    var transactionDescription: String?
    var merchant: String?
    var category: String?
    var type: String?
    var amountUSD: Double?
    var purchasedBy: String?
    var friendlyName: String?
    
    @Relationship var creditCard: Bill?
    
    init(transactionDate: String?, clearingDate: String?, transactionDescription: String?, merchant: String?, category: String?, type: String?, amountUSD: Double?, purchasedBy: String?, creditCard: Bill? = nil, friendlyName: String? = nil) {
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
    
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy" // Adjust as needed for your CSV date format
        return formatter
    }()
}
