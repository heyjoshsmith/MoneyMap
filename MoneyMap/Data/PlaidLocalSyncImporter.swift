//
//  PlaidLocalSyncImporter.swift
//  MoneyMap
//
//  Created by Codex on 7/5/26.
//

import Foundation
import SwiftData

struct PlaidSnapshotRefreshSummary {
    let connectionCount: Int
    let accountCount: Int
}

struct PlaidTransactionImportSummary {
    let importedCount: Int
    let skippedCount: Int
}

enum PlaidLocalSyncImporter {
    @discardableResult
    static func refreshSnapshots(_ snapshot: PlaidSnapshot, context: ModelContext) throws -> PlaidSnapshotRefreshSummary {
        let existingConnections = try context.fetch(FetchDescriptor<PlaidConnection>())
        let connectionsByItemID = Dictionary(existingConnections.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })

        for connectionDTO in snapshot.connections {
            let connection = connectionsByItemID[connectionDTO.itemId] ?? PlaidConnection(itemID: connectionDTO.itemId)
            connection.institutionID = connectionDTO.institutionId
            connection.institutionName = connectionDTO.institutionName
            connection.status = connectionDTO.status
            connection.errorMessage = connectionDTO.errorMessage
            connection.lastSyncAt = PlaidDateParsing.dateTime(connectionDTO.lastSyncAt)
            connection.updatedAt = PlaidDateParsing.dateTime(connectionDTO.updatedAt) ?? .now
            if connectionsByItemID[connectionDTO.itemId] == nil {
                connection.createdAt = PlaidDateParsing.dateTime(connectionDTO.createdAt) ?? .now
                context.insert(connection)
            }
        }

        let existingAccounts = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        let accountsByID = Dictionary(existingAccounts.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })

        for accountDTO in snapshot.accounts {
            let account = accountsByID[accountDTO.accountId] ?? PlaidAccountSnapshot(
                accountID: accountDTO.accountId,
                itemID: accountDTO.itemId,
                accountName: accountDTO.displayName,
                type: accountDTO.type ?? "unknown"
            )
            account.itemID = accountDTO.itemId
            account.institutionName = accountDTO.institutionName
            account.accountName = accountDTO.displayName
            account.officialName = accountDTO.officialName
            account.mask = accountDTO.mask
            account.type = accountDTO.type ?? "unknown"
            account.subtype = accountDTO.subtype
            account.currentBalance = accountDTO.currentBalance
            account.availableBalance = accountDTO.availableBalance
            account.currencyCode = accountDTO.currencyCode
            account.updatedAt = PlaidDateParsing.dateTime(accountDTO.updatedAt) ?? .now
            if accountsByID[accountDTO.accountId] == nil {
                context.insert(account)
            }
        }

        try context.save()
        return PlaidSnapshotRefreshSummary(
            connectionCount: snapshot.connections.count,
            accountCount: snapshot.accounts.count
        )
    }

    @discardableResult
    static func importReviewedTransactions(
        _ transactions: [PlaidTransactionDTO],
        context: ModelContext,
        bills: [Bill]
    ) throws -> PlaidTransactionImportSummary {
        let existingTransactions = try context.fetch(FetchDescriptor<Transaction>())
        var knownPlaidIDs = Set(existingTransactions.compactMap(\.plaidTransactionID))
        var knownFallbackSignatures = Set(existingTransactions.map(TransactionFallbackSignature.init))
        let linkedBillsByAccountID = Dictionary(
            bills.compactMap { bill -> (String, Bill)? in
                guard let plaidAccountID = bill.plaidAccountID else { return nil }
                return (plaidAccountID, bill)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var importedCount = 0
        var skippedCount = 0

        for transactionDTO in transactions {
            guard knownPlaidIDs.insert(transactionDTO.transactionId).inserted else {
                skippedCount += 1
                continue
            }

            let transaction = makeTransaction(from: transactionDTO, bill: linkedBillsByAccountID[transactionDTO.accountId])
            let fallbackSignature = TransactionFallbackSignature(transaction)
            guard knownFallbackSignatures.insert(fallbackSignature).inserted else {
                skippedCount += 1
                continue
            }

            context.insert(transaction)
            importedCount += 1
        }

        try context.save()
        return PlaidTransactionImportSummary(importedCount: importedCount, skippedCount: skippedCount)
    }

    @discardableResult
    static func importReviewedItems(
        _ reviewItems: [PlaidTransactionReviewItem],
        context: ModelContext,
        bills: [Bill]
    ) throws -> PlaidTransactionImportSummary {
        let readyItems = reviewItems.filter { $0.status == .ready }
        let existingTransactions = try context.fetch(FetchDescriptor<Transaction>())
        var knownPlaidIDs = Set(existingTransactions.compactMap(\.plaidTransactionID))
        var knownFallbackSignatures = Set(existingTransactions.map(TransactionFallbackSignature.init))
        let linkedBillsByAccountID = Dictionary(
            bills.compactMap { bill -> (String, Bill)? in
                guard let plaidAccountID = bill.plaidAccountID else { return nil }
                return (plaidAccountID, bill)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var importedCount = 0
        var skippedCount = 0

        for reviewItem in readyItems {
            guard knownPlaidIDs.insert(reviewItem.plaidTransactionID).inserted else {
                reviewItem.status = .skipped
                skippedCount += 1
                continue
            }

            let transaction = makeTransaction(from: reviewItem, bill: linkedBillsByAccountID[reviewItem.plaidAccountID])
            let fallbackSignature = TransactionFallbackSignature(transaction)
            guard knownFallbackSignatures.insert(fallbackSignature).inserted else {
                reviewItem.status = .skipped
                skippedCount += 1
                continue
            }

            context.insert(transaction)
            reviewItem.status = .imported
            importedCount += 1
        }

        try context.save()
        return PlaidTransactionImportSummary(importedCount: importedCount, skippedCount: skippedCount)
    }

    private static func makeTransaction(from dto: PlaidTransactionDTO, bill: Bill?) -> Transaction {
        Transaction(
            transactionDate: PlaidDateParsing.day(dto.date),
            clearingDate: PlaidDateParsing.day(dto.authorizedDate),
            transactionDescription: dto.name,
            merchant: dto.merchantName ?? dto.name,
            category: dto.category,
            type: dto.pending ? "Pending" : "Posted",
            amountUSD: dto.amount,
            purchasedBy: "Plaid",
            creditCard: bill,
            friendlyName: dto.merchantName,
            plaidTransactionID: dto.transactionId,
            plaidAccountID: dto.accountId,
            plaidPendingTransactionID: dto.pendingTransactionId,
            plaidImportedAt: .now,
            plaidIsPending: dto.pending
        )
    }

    private static func makeTransaction(from reviewItem: PlaidTransactionReviewItem, bill: Bill?) -> Transaction {
        Transaction(
            transactionDate: reviewItem.date,
            clearingDate: reviewItem.authorizedDate,
            transactionDescription: reviewItem.name,
            merchant: reviewItem.merchantName ?? reviewItem.name,
            category: reviewItem.category,
            type: reviewItem.pending ? "Pending" : "Posted",
            amountUSD: reviewItem.amount,
            purchasedBy: "Plaid",
            creditCard: bill,
            friendlyName: reviewItem.merchantName,
            plaidTransactionID: reviewItem.plaidTransactionID,
            plaidAccountID: reviewItem.plaidAccountID,
            plaidPendingTransactionID: reviewItem.pendingTransactionID,
            plaidImportedAt: .now,
            plaidIsPending: reviewItem.pending
        )
    }
}

enum PlaidDateParsing {
    private static let isoFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dateTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFormatter.date(from: value)
    }

    static func day(_ value: String?) -> Date? {
        guard let value else { return nil }
        return dayFormatter.date(from: value)
    }
}

private struct TransactionFallbackSignature: Hashable {
    let date: TimeInterval?
    let merchant: String
    let amountInCents: Int?

    init(_ transaction: Transaction) {
        date = (transaction.transactionDate ?? transaction.clearingDate)
            .map { Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate }
        merchant = Self.normalized(transaction.merchant ?? transaction.friendlyName ?? transaction.transactionDescription)
        amountInCents = transaction.amountUSD.map { Int(($0 * 100).rounded()) }
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
