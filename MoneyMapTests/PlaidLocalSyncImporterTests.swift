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
        XCTAssertEqual(reviewItem.status, .imported)
        XCTAssertEqual(duplicateReviewItem.status, .skipped)
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

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
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
        return ModelContext(container)
    }
}
