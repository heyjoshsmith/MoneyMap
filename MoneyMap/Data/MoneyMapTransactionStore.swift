//
//  MoneyMapTransactionStore.swift
//  MoneyMap
//
//  Created by Codex on 6/16/26.
//

import Foundation
import SwiftData

struct MoneyMapTransactionSearchOptions {
    var merchant: String?
    var category: String?
    var cardID: UUID?
    var since: Date?
    var limit: Int?
}

enum MoneyMapTransactionStore {
    static func makeContext() throws -> ModelContext {
        let container = try SharedModelContainerFactory.make()
        return ModelContext(container)
    }

    static func fetchTransactions() throws -> [Transaction] {
        let context = try makeContext()
        return try context.fetch(FetchDescriptor<Transaction>())
    }

    static func fetchTransactions(matching options: MoneyMapTransactionSearchOptions) throws -> [Transaction] {
        let normalizedMerchant = options.merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = options.category?.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = try fetchTransactions()
            .filter { transaction in
                if let cardID = options.cardID, transaction.creditCard?.id != cardID {
                    return false
                }

                if let since = options.since {
                    let comparisonDate = transaction.transactionDate ?? transaction.clearingDate ?? .distantPast
                    if comparisonDate < since {
                        return false
                    }
                }

                if let normalizedMerchant, !normalizedMerchant.isEmpty {
                    let haystacks = [
                        transaction.friendlyName,
                        transaction.merchant,
                        transaction.transactionDescription
                    ]
                    let matchesMerchant = haystacks
                        .compactMap { $0?.lowercased() }
                        .contains { $0.contains(normalizedMerchant.lowercased()) }
                    if !matchesMerchant {
                        return false
                    }
                }

                if let normalizedCategory, !normalizedCategory.isEmpty {
                    guard let category = transaction.category?.lowercased(),
                          category.contains(normalizedCategory.lowercased()) else {
                        return false
                    }
                }

                return true
            }
            .sorted(by: mostRecentFirst)

        if let limit = options.limit {
            return Array(filtered.prefix(max(limit, 0)))
        }

        return filtered
    }

    static func totalSpent(matching options: MoneyMapTransactionSearchOptions) throws -> Double {
        try fetchTransactions(matching: options).reduce(0) { total, transaction in
            total + abs(transaction.amountUSD ?? 0)
        }
    }

    static func mostRecentFirst(lhs: Transaction, rhs: Transaction) -> Bool {
        let leftDate = lhs.transactionDate ?? lhs.clearingDate ?? .distantPast
        let rightDate = rhs.transactionDate ?? rhs.clearingDate ?? .distantPast

        if leftDate != rightDate {
            return leftDate > rightDate
        }

        let leftMerchant = lhs.friendlyName ?? lhs.merchant ?? lhs.transactionDescription ?? ""
        let rightMerchant = rhs.friendlyName ?? rhs.merchant ?? rhs.transactionDescription ?? ""
        return leftMerchant.localizedCaseInsensitiveCompare(rightMerchant) == .orderedAscending
    }
}
