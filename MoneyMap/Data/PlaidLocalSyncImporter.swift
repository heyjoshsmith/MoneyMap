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
    var updatedCount: Int = 0
    var removedCount: Int = 0
}

enum PlaidLocalSyncImporter {
    @discardableResult
    static func refreshSnapshots(_ snapshot: PlaidSnapshot, context: ModelContext) throws -> PlaidSnapshotRefreshSummary {
        let existingConnections = try context.fetch(FetchDescriptor<PlaidConnection>())
        var connectionsByItemID = Dictionary(existingConnections.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })

        for connectionDTO in snapshot.connections {
            let sourceUpdatedAt = PlaidDateParsing.dateTime(connectionDTO.updatedAt)
            if let existing = connectionsByItemID[connectionDTO.itemId],
               sourceUpdatedAt.map({ $0 >= existing.updatedAt }) != true { continue }
            let connection = connectionsByItemID[connectionDTO.itemId] ?? PlaidConnection(itemID: connectionDTO.itemId)
            connection.institutionID = connectionDTO.institutionId
            connection.institutionName = connectionDTO.institutionName
            connection.status = connectionDTO.status
            connection.errorMessage = connectionDTO.errorMessage
            connection.lastSyncAt = PlaidDateParsing.dateTime(connectionDTO.lastSyncAt)
            connection.updatedAt = sourceUpdatedAt ?? .distantPast
            if connectionsByItemID[connectionDTO.itemId] == nil {
                connection.createdAt = PlaidDateParsing.dateTime(connectionDTO.createdAt) ?? .now
                context.insert(connection)
            }
            connectionsByItemID[connectionDTO.itemId] = connection
        }

        let existingAccounts = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        var accountsByID = Dictionary(existingAccounts.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })

        for accountDTO in snapshot.accounts {
            let sourceUpdatedAt = PlaidDateParsing.dateTime(accountDTO.updatedAt)
            if let existing = accountsByID[accountDTO.accountId],
               sourceUpdatedAt.map({ $0 >= existing.updatedAt }) != true { continue }
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
            account.updatedAt = sourceUpdatedAt ?? .distantPast
            if accountsByID[accountDTO.accountId] == nil {
                context.insert(account)
            }
            accountsByID[accountDTO.accountId] = account
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
        let items = transactions.compactMap { dto -> PlaidTransactionReviewItem? in
            guard let amount = dto.amount else { return nil }
            return PlaidTransactionReviewItem(
                plaidTransactionID: dto.transactionId, plaidAccountID: dto.accountId,
                plaidItemID: dto.itemId, name: dto.name ?? "Plaid transaction",
                merchantName: dto.merchantName, category: dto.category,
                date: PlaidDateParsing.day(dto.date), authorizedDate: PlaidDateParsing.day(dto.authorizedDate),
                amount: amount, currencyCode: dto.currencyCode, pending: dto.pending,
                pendingTransactionID: dto.pendingTransactionId,
                updatedAt: PlaidDateParsing.dateTime(dto.updatedAt) ?? .now
            )
        }
        return try importReviewedItems(items, context: context, bills: bills)
    }

    @discardableResult
    static func importReviewedItems(
        _ reviewItems: [PlaidTransactionReviewItem],
        context: ModelContext,
        bills: [Bill]
    ) throws -> PlaidTransactionImportSummary {
        let existingTransactions = try context.fetch(FetchDescriptor<Transaction>())
        var byID = Dictionary(existingTransactions.compactMap { transaction in
            transaction.plaidTransactionID.map { ($0, transaction) }
        }, uniquingKeysWith: { first, _ in first })
        // Reverse lookup avoids scanning all imported rows for every review item.
        struct PendingKey: Hashable {
            let accountID: String?
            let transactionID: String
        }
        var replacements: [PendingKey: Set<String>] = [:]
        func indexReplacement(_ transaction: Transaction, removing: Bool = false) {
            guard let pendingID = transaction.plaidPendingTransactionID,
                  let postedID = transaction.plaidTransactionID else { return }
            let key = PendingKey(accountID: transaction.plaidAccountID, transactionID: pendingID)
            if removing {
                replacements[key]?.remove(postedID)
            } else {
                replacements[key, default: []].insert(postedID)
            }
        }
        for transaction in byID.values { indexReplacement(transaction) }
        let linkedBills = Dictionary(bills.compactMap { bill in
            bill.plaidAccountID.map { ($0, bill) }
        }, uniquingKeysWith: { first, _ in first })
        var summary = PlaidTransactionImportSummary(importedCount: 0, skippedCount: 0)
        var imported = 0
        var skipped = 0
        var processed = Set<String>()
        // Reconcile active posted replacements before pending removal tombstones.
        let ordered = reviewItems.sorted {
            if ($0.bankRemovedAt == nil) != ($1.bankRemovedAt == nil) { return $0.bankRemovedAt == nil }
            return $0.updatedAt > $1.updatedAt
        }
        for item in ordered {
            guard processed.insert(item.plaidTransactionID).inserted else {
                if item.status == .ready { item.status = .skipped }
                skipped += 1
                continue
            }
            // A stale active pending row can arrive after its posted replacement.
            // Never revive a superseded legacy record merely because it still has its own ID.
            let replacementKey = PendingKey(accountID: item.plaidAccountID, transactionID: item.plaidTransactionID)
            if replacements[replacementKey]?.contains(where: { $0 != item.plaidTransactionID }) == true {
                if let superseded = byID[item.plaidTransactionID], superseded.plaidBankRemovedAt == nil {
                    superseded.plaidOriginalAmount = superseded.plaidOriginalAmount ?? superseded.amountUSD
                    superseded.plaidBankRemovedAt = item.updatedAt
                    superseded.amountUSD = nil
                    summary.removedCount += 1
                }
                continue
            }
            let pendingMatch = item.pendingTransactionID.flatMap { byID[$0] }
            if let transaction = byID[item.plaidTransactionID] ?? pendingMatch,
               transaction.plaidAccountID == item.plaidAccountID {
                if let previousUpdate = transaction.plaidBankUpdatedAt, previousUpdate > item.updatedAt { continue }
                if pendingMatch === transaction, let oldID = transaction.plaidTransactionID,
                   oldID != item.plaidTransactionID {
                    byID.removeValue(forKey: oldID)
                }
                // If an older client imported both pending and posted records, exclude the
                // superseded one while retaining its user annotations and relationships.
                if let pendingMatch, pendingMatch !== transaction,
                   pendingMatch.plaidAccountID == item.plaidAccountID {
                    pendingMatch.plaidOriginalAmount = pendingMatch.plaidOriginalAmount ?? pendingMatch.amountUSD
                    pendingMatch.plaidBankRemovedAt = item.updatedAt
                    pendingMatch.amountUSD = nil
                }
                let wasRemoved = transaction.plaidBankRemovedAt != nil
                indexReplacement(transaction, removing: true)
                let changed = apply(item, to: transaction)
                indexReplacement(transaction)
                byID[item.plaidTransactionID] = transaction
                if item.bankRemovedAt != nil {
                    if !wasRemoved { summary.removedCount += 1 }
                } else {
                    if changed { summary.updatedCount += 1 }
                    if item.status != .imported { item.status = .imported }
                }
                continue
            }
            guard item.status == .ready, item.bankRemovedAt == nil else { continue }
            let transaction = makeTransaction(from: item, bill: linkedBills[item.plaidAccountID])
            apply(item, to: transaction, isNew: true)
            indexReplacement(transaction)
            context.insert(transaction)
            byID[item.plaidTransactionID] = transaction
            item.status = .imported
            imported += 1
        }
        try context.save()
        return PlaidTransactionImportSummary(importedCount: imported, skippedCount: skipped,
                                            updatedCount: summary.updatedCount, removedCount: summary.removedCount)
    }

    @discardableResult
    private static func apply(_ item: PlaidTransactionReviewItem, to transaction: Transaction, isNew: Bool = false) -> Bool {
        let oldState = TransactionBankState(transaction)
        let previous = transaction.plaidBankSnapshotJSON.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(BankTransactionLabels.self, from: $0) }
        let labels = BankTransactionLabels(name: item.name, merchant: item.merchantName ?? item.name,
                                          category: item.category ?? previous?.category,
                                          friendlyName: item.merchantName ?? previous?.friendlyName)
        // Only replace labels still matching our last bank import. Existing legacy custom labels survive.
        if isNew || transaction.transactionDescription == previous?.name { transaction.transactionDescription = labels.name }
        if isNew || transaction.merchant == previous?.merchant { transaction.merchant = labels.merchant }
        if isNew || transaction.category == previous?.category { transaction.category = labels.category }
        if isNew || transaction.friendlyName == previous?.friendlyName { transaction.friendlyName = labels.friendlyName }
        if let date = item.date { transaction.transactionDate = date }
        if let authorizedDate = item.authorizedDate { transaction.clearingDate = authorizedDate }
        transaction.type = item.pending ? "Pending" : "Posted"
        transaction.plaidIsPending = item.pending
        transaction.plaidTransactionID = item.plaidTransactionID
        if let pendingID = item.pendingTransactionID { transaction.plaidPendingTransactionID = pendingID }
        if let currency = item.currencyCode { transaction.plaidCurrencyCode = currency }
        transaction.plaidOriginalAmount = item.amount
        transaction.plaidBankRemovedAt = item.bankRemovedAt
        transaction.plaidBankUpdatedAt = item.updatedAt
        transaction.amountUSD = item.bankRemovedAt == nil && transaction.plaidCurrencyCode?.uppercased() == "USD" ? item.amount : nil
        if let enrichment = item.enrichmentJSON { transaction.plaidEnrichmentJSON = enrichment }
        transaction.plaidBankSnapshotJSON = (try? JSONEncoder().encode(labels)).flatMap { String(data: $0, encoding: .utf8) }
        return oldState != TransactionBankState(transaction)
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

private struct BankTransactionLabels: Codable {
    let name: String
    let merchant: String
    let category: String?
    let friendlyName: String?
}

/// Excludes sync bookkeeping so unchanged snapshots do not generate user-facing updates.
private struct TransactionBankState: Equatable {
    let labels: [String?]
    let dates: [Date?]
    let amounts: [Double?]
    let pending: Bool?

    init(_ transaction: Transaction) {
        labels = [transaction.transactionDescription, transaction.merchant, transaction.category,
                  transaction.friendlyName, transaction.type, transaction.plaidTransactionID,
                  transaction.plaidPendingTransactionID, transaction.plaidCurrencyCode,
                  transaction.plaidEnrichmentJSON]
        dates = [transaction.transactionDate, transaction.clearingDate, transaction.plaidBankRemovedAt]
        amounts = [transaction.amountUSD, transaction.plaidOriginalAmount]
        pending = transaction.plaidIsPending
    }
}
