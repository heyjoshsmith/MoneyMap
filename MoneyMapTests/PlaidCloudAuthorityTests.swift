import XCTest
import SwiftData
@testable import MoneyMap

@MainActor
final class PlaidCloudAuthorityTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    func testOlderCloudResponseCannotRollBackBalanceOrRemoval() throws {
        let context = try makeContext()
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 20, balance: 50, transactionAmount: 5, removed: true), context: context)
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 10, balance: 999, transactionAmount: 99, removed: false), context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlaidAccountSnapshot>()).first?.currentBalance, 50)
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<PlaidTransactionReviewItem>()).first)
        XCTAssertEqual(transaction.amount, 5)
        XCTAssertNotNil(transaction.bankRemovedAt)
    }

    func testReviewDecisionsSurviveNewBankFacts() throws {
        let context = try makeContext()
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 10, balance: 50, transactionAmount: 5), context: context)
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<PlaidTransactionReviewItem>()).first)
        let suggestion = try XCTUnwrap(context.fetch(FetchDescriptor<PlaidSuggestion>()).first)
        transaction.status = .imported
        suggestion.status = .imported
        try context.save()
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 20, balance: 60, transactionAmount: 6), context: context)
        XCTAssertEqual(transaction.status, .imported)
        XCTAssertEqual(suggestion.status, .imported)
        XCTAssertEqual(transaction.amount, 6)
        XCTAssertEqual(PlaidCloudSyncService.mergedReviewStatus("skipped", "imported"), "imported")
        XCTAssertEqual(PlaidCloudSyncService.mergedReviewStatus("imported", "skipped"), "imported")
    }

    func testNewEnvelopeCanClearLiabilityWithUnchangedBalanceTimestamp() throws {
        let context = try makeContext()
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 10, balance: 50, transactionAmount: 5, minimumPayment: 25), context: context)
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 20, balance: 50, transactionAmount: 5), context: context)
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<PlaidAccountSnapshot>()).first)
        XCTAssertNil(PlaidAccountEnrichment.decode(account.enrichmentJSON)?.creditLiability)
    }

    func testRemovedAccountIsNotResurrectedByOlderEnvelope() throws {
        let context = try makeContext()
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 10, balance: 50, transactionAmount: 5), context: context)
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 20, balance: 50, transactionAmount: 5, includeAccount: false), context: context)
        try PlaidCloudSyncService.applySnapshotPayload(snapshot(version: 10, balance: 50, transactionAmount: 5), context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlaidAccountSnapshot>()).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: PlaidConnection.self, PlaidAccountSnapshot.self,
            PlaidTransactionReviewItem.self, PlaidSuggestion.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        retainedContainers.append(container)
        return ModelContext(container)
    }

    private func snapshot(version: Int, balance: Double, transactionAmount: Double, removed: Bool = false,
                          includeAccount: Bool = true, minimumPayment: Double? = nil) throws -> Data {
        let versionDate = String(format: "2026-09-19T12:00:%02dZ", version)
        let bankDate = "2026-09-19T11:00:00Z"
        var enrichment = PlaidAccountEnrichment()
        if let minimumPayment { enrichment.creditLiability = ["minimum_payment_amount": .number(minimumPayment)] }
        var transaction: [String: Any] = ["plaidTransactionID": "tx", "plaidAccountID": "card", "plaidItemID": "bank",
            "name": "Purchase", "amount": transactionAmount, "pending": false, "statusRaw": "ready", "createdAt": bankDate, "updatedAt": bankDate]
        if removed { transaction["bankRemovedAt"] = versionDate }
        let account: [String: Any] = ["accountID": "card", "itemID": "bank", "accountName": "Card", "type": "credit",
            "currentBalance": balance, "updatedAt": bankDate, "enrichmentJSON": try enrichment.encoded()]
        let suggestion: [String: Any] = ["id": "EF73817E-EF07-432A-9873-97C48DF6B679", "kindRaw": "creditCardBill",
            "plaidAccountID": "card", "plaidItemID": "bank", "title": "Card", "statusRaw": "ready", "createdAt": bankDate, "updatedAt": bankDate]
        return try JSONSerialization.data(withJSONObject: ["updatedAt": versionDate, "connections": [],
            "accounts": includeAccount ? [account] : [], "transactions": [transaction], "suggestions": [suggestion]])
    }
}
