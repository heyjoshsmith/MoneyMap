//
//  PlaidLocalSyncImporterTests.swift
//  MoneyMapTests
//
//  Created by Codex on 7/5/26.
//

import SwiftData
import XCTest
@testable import MoneyMap

final class PlaidLocalSyncImporterTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []
    func testRefreshSnapshotsUpsertsConnectionsAndAccounts() throws {
        let context = try makeContext()
        let initialSnapshot = PlaidSnapshot(
            connections: [
                PlaidConnectionDTO(
                    itemId: "item-1",
                    institutionId: "ins-1",
                    institutionName: "Plaid Bank",
                    transactionsCursor: nil,
                    status: "connected",
                    errorMessage: nil,
                    createdAt: "2026-07-05T12:00:00Z",
                    updatedAt: "2026-07-05T12:00:00Z",
                    lastSyncAt: nil
                )
            ],
            accounts: [
                PlaidAccountDTO(
                    accountId: "account-1",
                    itemId: "item-1",
                    institutionName: "Plaid Bank",
                    name: "Checking",
                    officialName: nil,
                    mask: "1111",
                    type: "depository",
                    subtype: "checking",
                    currentBalance: 100,
                    availableBalance: 90,
                    currencyCode: "USD",
                    updatedAt: "2026-07-05T12:00:00Z"
                )
            ],
            transactions: [],
            liabilities: []
        )

        let updatedSnapshot = PlaidSnapshot(
            connections: [
                PlaidConnectionDTO(
                    itemId: "item-1",
                    institutionId: "ins-1",
                    institutionName: "Plaid Bank",
                    transactionsCursor: nil,
                    status: "synced",
                    errorMessage: nil,
                    createdAt: "2026-07-05T12:00:00Z",
                    updatedAt: "2026-07-05T13:00:00Z",
                    lastSyncAt: "2026-07-05T13:00:00Z"
                )
            ],
            accounts: [
                PlaidAccountDTO(
                    accountId: "account-1",
                    itemId: "item-1",
                    institutionName: "Plaid Bank",
                    name: "Checking",
                    officialName: nil,
                    mask: "1111",
                    type: "depository",
                    subtype: "checking",
                    currentBalance: 125,
                    availableBalance: 100,
                    currencyCode: "USD",
                    updatedAt: "2026-07-05T13:00:00Z"
                )
            ],
            transactions: [],
            liabilities: []
        )

        try PlaidLocalSyncImporter.refreshSnapshots(initialSnapshot, context: context)
        try PlaidLocalSyncImporter.refreshSnapshots(updatedSnapshot, context: context)
        // A delayed legacy bridge response must not replace newer cloud bank facts.
        try PlaidLocalSyncImporter.refreshSnapshots(initialSnapshot, context: context)

        let connections = try context.fetch(FetchDescriptor<PlaidConnection>())
        let accounts = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.status, "synced")
        XCTAssertNotNil(connections.first?.lastSyncAt)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.currentBalance, 125)
    }

    func testReviewedPlaidTransactionsDedupeAndLinkToCardBill() throws {
        let context = try makeContext()
        let bill = Bill(
            name: "Plaid Card",
            amount: 25,
            dueDate: .now,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(creditLimit: 1_000, cardBalance: 100),
            plaidAccountID: "account-card"
        )
        context.insert(bill)

        let transaction = PlaidTransactionDTO(
            transactionId: "transaction-1",
            itemId: "item-1",
            accountId: "account-card",
            pendingTransactionId: nil,
            date: "2026-07-01",
            authorizedDate: "2026-07-01",
            name: "Coffee Shop",
            merchantName: "Local Cafe",
            category: "Food > Coffee",
            amount: 5.25,
            pending: false,
            paymentChannel: "in store",
            currencyCode: "USD",
            updatedAt: "2026-07-05T12:00:00Z"
        )

        let firstImport = try PlaidLocalSyncImporter.importReviewedTransactions(
            [transaction],
            context: context,
            bills: [bill]
        )
        let secondImport = try PlaidLocalSyncImporter.importReviewedTransactions(
            [transaction],
            context: context,
            bills: [bill]
        )

        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        XCTAssertEqual(firstImport.importedCount, 1)
        XCTAssertEqual(secondImport.importedCount, 0)
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.plaidTransactionID, "transaction-1")
        XCTAssertEqual(transactions.first?.creditCard?.id, bill.id)
    }

    func testReviewItemsImportAndMarkStatuses() throws {
        let context = try makeContext()
        let bill = Bill(
            name: "Plaid Card",
            amount: 25,
            dueDate: .now,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(creditLimit: 1_000, cardBalance: 100),
            plaidAccountID: "account-card"
        )
        context.insert(bill)

        let reviewItem = PlaidTransactionReviewItem(
            plaidTransactionID: "review-transaction-1",
            plaidAccountID: "account-card",
            plaidItemID: "item-1",
            name: "Grocery Store",
            merchantName: "Local Market",
            category: "Shops > Groceries",
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            authorizedDate: Date(timeIntervalSinceReferenceDate: 800_000_000),
            amount: 42.18,
            currencyCode: "USD"
        )

        let duplicateReviewItem = PlaidTransactionReviewItem(
            plaidTransactionID: "review-transaction-1",
            plaidAccountID: "account-card",
            plaidItemID: "item-1",
            name: "Grocery Store",
            merchantName: "Local Market",
            category: "Shops > Groceries",
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            amount: 42.18,
            currencyCode: "USD"
        )

        let summary = try PlaidLocalSyncImporter.importReviewedItems(
            [reviewItem, duplicateReviewItem],
            context: context,
            bills: [bill]
        )

        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual([reviewItem.statusRaw, duplicateReviewItem.statusRaw].sorted(), ["imported", "skipped"])
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.plaidTransactionID, "review-transaction-1")
        XCTAssertEqual(transactions.first?.merchant, "Local Market")
        XCTAssertEqual(transactions.first?.creditCard?.id, bill.id)
    }

    func testCreditCardPaymentMethodMirrorCarriesPlaidLink() throws {
        let context = try makeContext()
        let bill = Bill(
            name: "Plaid Card",
            amount: 25,
            dueDate: .now,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 1_000,
                cardBalance: 100,
                issuerName: "Plaid Bank",
                lastFourDigits: "1234"
            ),
            plaidAccountID: "account-card",
            plaidItemID: "item-1",
            plaidInstitutionID: "ins-1",
            plaidUpdatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
        context.insert(bill)

        let didChange = PaymentMethodSyncService.syncCreditCardPaymentMethods(
            bills: [bill],
            paymentMethods: [],
            context: context
        )
        try context.save()

        let paymentMethods = try context.fetch(FetchDescriptor<PaymentMethod>())

        XCTAssertTrue(didChange)
        XCTAssertEqual(paymentMethods.count, 1)
        XCTAssertEqual(paymentMethods.first?.linkedBillID, bill.id)
        XCTAssertEqual(paymentMethods.first?.plaidAccountID, "account-card")
        XCTAssertEqual(paymentMethods.first?.plaidItemID, "item-1")
        XCTAssertEqual(paymentMethods.first?.plaidInstitutionID, "ins-1")
    }

    func testImportedCorrectionsPreserveCustomLabelsAndReconcileBankAmounts() throws {
        let context = try makeContext()
        let item = reviewItem("one", amount: 10)
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        transaction.friendlyName = "My custom name"
        transaction.category = "My category"
        let userLink = UUID()
        transaction.linkedBillID = userLink
        item.amount = 12
        item.name = "Corrected merchant"
        item.merchantName = "Corrected merchant"
        item.category = "Bank category"
        item.enrichmentJSON = "{\"payment_channel\":\"online\"}"
        item.updatedAt = .now.addingTimeInterval(1)
        let summary = try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        XCTAssertEqual(summary.updatedCount, 1)
        XCTAssertEqual(transaction.amountUSD, 12)
        XCTAssertEqual(transaction.merchant, "Corrected merchant")
        XCTAssertEqual(transaction.friendlyName, "My custom name")
        XCTAssertEqual(transaction.category, "My category")
        XCTAssertEqual(transaction.linkedBillID, userLink)
        XCTAssertEqual(transaction.plaidEnrichmentJSON, item.enrichmentJSON)
    }

    func testPendingReplacementAndRemovalDoNotDoubleCountOrDeleteUserLinks() throws {
        let context = try makeContext()
        let pending = reviewItem("pending", amount: 10)
        pending.pending = true
        try PlaidLocalSyncImporter.importReviewedItems([pending], context: context, bills: [])
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        original.friendlyName = "Keep me"
        let posted = reviewItem("posted", amount: 13)
        posted.pendingTransactionID = "pending"
        posted.updatedAt = .now.addingTimeInterval(2)
        pending.bankRemovedAt = .now
        pending.updatedAt = .now.addingTimeInterval(1)
        try PlaidLocalSyncImporter.importReviewedItems([pending, posted], context: context, bills: [])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 1)
        XCTAssertEqual(original.plaidTransactionID, "posted")
        XCTAssertEqual(original.friendlyName, "Keep me")
        XCTAssertEqual(original.amountUSD, 13)
        posted.bankRemovedAt = .now
        posted.updatedAt = .now.addingTimeInterval(3)
        let summary = try PlaidLocalSyncImporter.importReviewedItems([posted, pending], context: context, bills: [])
        XCTAssertEqual(summary.removedCount, 1)
        XCTAssertNil(original.amountUSD)
        XCTAssertEqual(original.displayAmount, 13)
        XCTAssertNotNil(original.plaidBankRemovedAt)
    }

    func testForeignCurrencyIsPreservedWithoutCountingAsDollars() throws {
        let context = try makeContext()
        let item = reviewItem("foreign", amount: 100)
        item.currencyCode = "CAD"
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertNil(transaction.amountUSD)
        XCTAssertEqual(transaction.displayAmount, 100)
        XCTAssertEqual(transaction.displayCurrencyCode, "CAD")
    }

    func testOlderSnapshotCannotOverwriteCurrentImportedAmount() throws {
        let context = try makeContext()
        let item = reviewItem("one", amount: 20)
        item.updatedAt = .now.addingTimeInterval(10)
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        item.amount = 5
        item.updatedAt = .distantPast
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).first?.amountUSD, 20)
    }

    func testDistinctBankIDsWithSameMerchantDateAndAmountBothImport() throws {
        let context = try makeContext()
        let first = reviewItem("purchase-a", amount: 5)
        let second = reviewItem("purchase-b", amount: 5)
        let summary = try PlaidLocalSyncImporter.importReviewedItems([first, second], context: context, bills: [])
        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 2)
    }

    func testUserSelectedCardAndMissingMetadataSurviveCorrection() throws {
        let context = try makeContext()
        let item = reviewItem("purchase", amount: 10)
        item.enrichmentJSON = "{\"website\":\"example.com\"}"
        item.category = "Food"
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first)
        let chosen = Bill(name: "User selected", amount: 25, dueDate: .now,
                          category: .creditCard, recurrenceInterval: 1, recurrenceUnit: .month)
        context.insert(chosen)
        transaction.creditCard = chosen
        transaction.linkedBillID = chosen.id
        item.amount = 15
        item.currencyCode = nil
        item.enrichmentJSON = nil
        item.category = nil
        item.date = nil
        item.updatedAt = .now.addingTimeInterval(1)
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        XCTAssertEqual(transaction.creditCard?.id, chosen.id)
        XCTAssertEqual(transaction.linkedBillID, chosen.id)
        XCTAssertEqual(transaction.category, "Food")
        XCTAssertNotNil(transaction.transactionDate)
        XCTAssertNotNil(transaction.plaidEnrichmentJSON)
        XCTAssertEqual(transaction.plaidCurrencyCode, "USD")
        XCTAssertEqual(transaction.amountUSD, 15)
    }

    func testUnchangedSnapshotDoesNotReportCorrections() throws {
        let context = try makeContext()
        let item = reviewItem("unchanged", amount: 10)
        try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        let summary = try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(summary.updatedCount, 0)
        XCTAssertEqual(summary.removedCount, 0)
    }

    func testLegacyPendingRecordCannotReviveAfterPostedReplacement() throws {
        let context = try makeContext()
        let pending = reviewItem("legacy-pending", amount: 10)
        pending.pending = true
        let posted = reviewItem("legacy-posted", amount: 12)
        try PlaidLocalSyncImporter.importReviewedItems([pending, posted], context: context, bills: [])
        posted.pendingTransactionID = pending.plaidTransactionID
        posted.updatedAt = .now.addingTimeInterval(10)
        try PlaidLocalSyncImporter.importReviewedItems([pending, posted], context: context, bills: [])
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.compactMap(\.amountUSD).reduce(0, +), 12)
        XCTAssertNotNil(transactions.first(where: { $0.plaidTransactionID == "legacy-pending" })?.plaidBankRemovedAt)
        try PlaidLocalSyncImporter.importReviewedItems([pending, posted], context: context, bills: [])
        XCTAssertEqual(transactions.compactMap(\.amountUSD).reduce(0, +), 12)
    }

    func testManualLookalikeDoesNotSuppressAuthoritativeBankTransaction() throws {
        let context = try makeContext()
        let item = reviewItem("distinct-bank-purchase", amount: 10)
        let manual = Transaction(transactionDate: item.date, clearingDate: nil,
                                 transactionDescription: item.name, merchant: item.merchantName,
                                 category: nil, type: "Posted", amountUSD: 10, purchasedBy: "Me")
        context.insert(manual)
        let summary = try PlaidLocalSyncImporter.importReviewedItems([item], context: context, bills: [])
        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 2)
        XCTAssertNil(manual.plaidTransactionID)
        XCTAssertEqual(manual.amountUSD, 10)
    }

    func testReplacementLookupIsScopedToAccount() throws {
        let context = try makeContext()
        let posted = reviewItem("posted-other-account", amount: 20)
        posted.plaidAccountID = "other-account"
        posted.pendingTransactionID = "pending-current-account"
        try PlaidLocalSyncImporter.importReviewedItems([posted], context: context, bills: [])
        let pending = reviewItem("pending-current-account", amount: 10)
        pending.pending = true
        let result = try PlaidLocalSyncImporter.importReviewedItems([pending], context: context, bills: [])
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 2)
    }

    func testLargeImportRemainsIdempotent() throws {
        let context = try makeContext()
        let items = (0..<2000).map { reviewItem("bulk-\($0)", amount: 10) }
        let start = Date()
        XCTAssertEqual(try PlaidLocalSyncImporter.importReviewedItems(items, context: context, bills: []).importedCount, 2000)
        XCTAssertEqual(try PlaidLocalSyncImporter.importReviewedItems(items, context: context, bills: []).importedCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 2000)
        print("PERFORMANCE: 2000-row import and replay: \(Date().timeIntervalSince(start)) seconds")
    }

    private func reviewItem(_ id: String, amount: Double) -> PlaidTransactionReviewItem {
        PlaidTransactionReviewItem(plaidTransactionID: id, plaidAccountID: "account",
                                  plaidItemID: "item", name: "Merchant", merchantName: "Merchant",
                                  date: Date(timeIntervalSince1970: 1_700_000_000), amount: amount, currencyCode: "USD")
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Bill.self,
            Transaction.self,
            PaymentMethod.self,
            PlaidConnection.self,
            PlaidAccountSnapshot.self,
            PlaidTransactionReviewItem.self,
            PlaidSuggestion.self,
            configurations: config
        )
        retainedContainers.append(container)
        return ModelContext(container)
    }
}
