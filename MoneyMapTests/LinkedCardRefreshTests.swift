import XCTest
import SwiftData
import CloudKit
@testable import MoneyMap

@MainActor
final class LinkedCardRefreshTests: XCTestCase {
    func testFreshBankOnTimeStatusOverridesOldScheduleWithoutChangingIt() throws {
        let card = makeCard("card-1")
        let oldDue = Calendar.current.date(byAdding: .day, value: -10, to: .now)!
        let nextDue = Calendar.current.date(byAdding: .day, value: 12, to: .now)!
        card.dueDate = oldDue
        card.datePaid = nil
        card.checkStatus()
        XCTAssertEqual(card.status, .overdue)
        var enrichment = PlaidAccountEnrichment()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        enrichment.creditLiability = ["is_overdue": .bool(false), "next_payment_due_date": .string(formatter.string(from: nextDue))]
        enrichment.productUpdatedAt["liabilities"] = .now
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 100)
        account.enrichmentJSON = try enrichment.encoded()
        try LinkedCardRefreshService.apply(account, to: card)
        XCTAssertEqual(card.status, .upcoming(date: Calendar.current.startOfDay(for: nextDue)))
        XCTAssertEqual(card.dueDate, oldDue)
        XCTAssertNil(card.datePaid)
        card.checkStatus()
        XCTAssertNotEqual(card.status, .overdue)

        enrichment.productUpdatedAt["liabilities"] = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        card.plaidEnrichmentJSON = try enrichment.encoded()
        card.checkStatus()
        XCTAssertEqual(card.status, .overdue, "Stale bank data must not override the local schedule")
        enrichment.productUpdatedAt["liabilities"] = .now
        card.plaidEnrichmentJSON = try enrichment.encoded()
        card.plaidUnavailable = true
        card.checkStatus()
        XCTAssertEqual(card.status, .overdue, "Manual cards retain local payment status")
    }

    func testBankOverdueIsNotHiddenByFutureLocalSchedule() throws {
        let card = makeCard("card-1")
        card.dueDate = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
        var enrichment = PlaidAccountEnrichment()
        enrichment.creditLiability = ["is_overdue": .bool(true)]
        enrichment.productUpdatedAt["liabilities"] = .now
        card.plaidEnrichmentJSON = try enrichment.encoded()
        card.checkStatus()
        XCTAssertEqual(card.status, .overdue)
        card.plaidAccountID = nil
        card.checkStatus()
        XCTAssertNotEqual(card.status, .overdue)
    }

    func testLocalPaymentAndUndoCannotChangeReportedBankBalance() throws {
        let card = makeCard("card-1")
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 250)
        try LinkedCardRefreshService.apply(account, to: card)
        card.makePayment(of: 50)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 250)
        card.currentCreditCardDetails?.cardBalance = 999
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 250)
        account.currentBalance = 200
        account.updatedAt = account.updatedAt.addingTimeInterval(1)
        try LinkedCardRefreshService.apply(account, to: card)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 200)
        card.paymentEntries = []
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 200)
    }

    func testExistingLinkedSnapshotSeedsAuthoritativeBalanceWithoutNewTimestamp() throws {
        let card = makeCard("card-1")
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 300)
        card.plaidUpdatedAt = account.updatedAt
        XCTAssertNil(card.plaidReportedCardBalance)
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([account], to: [card]), 1)
        XCTAssertEqual(card.plaidReportedCardBalance, 300)
    }

    func testBankOnTimeWithoutDueDateDoesNotInventDateOrShowLocalOverdue() throws {
        let card = makeCard("card-1")
        card.dueDate = .distantPast
        var enrichment = PlaidAccountEnrichment()
        enrichment.creditLiability = ["is_overdue": .bool(false)]
        enrichment.productUpdatedAt["liabilities"] = .now
        card.plaidEnrichmentJSON = try enrichment.encoded()
        card.checkStatus()
        XCTAssertNil(card.effectiveStatus)
        XCTAssertNil(card.displayDueDate)
        XCTAssertEqual(card.displayStatusName, "On Time")
        XCTAssertFalse(card.displayPaymentIsPaid)
    }

    func testRefreshOnlyUpdatesMatchingCardAndPreservesManualDetails() throws {
        let card = makeCard("card-1")
        let other = makeCard("card-2")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 325, availableBalance: 675, updatedAt: timestamp)
        try LinkedCardRefreshService.apply(account, to: card)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 325)
        XCTAssertEqual(card.currentCreditCardDetails?.annualPercentageRate, 19)
        XCTAssertEqual(card.currentCreditCardDetails?.minimumPayment, 25)
        XCTAssertEqual(card.amount, 25)
        XCTAssertEqual(card.plaidUpdatedAt, timestamp)
        XCTAssertEqual(other.currentCreditCardDetails?.cardBalance, 100)
        XCTAssertNil(other.plaidUpdatedAt)
    }

    func testWrongAccountAndMissingBalanceDoNotChangeCard() throws {
        let card = makeCard("card-1")
        let wrong = PlaidAccountSnapshot(accountID: "card-2", itemID: "bank", accountName: "Other", type: "credit", currentBalance: 900)
        XCTAssertThrowsError(try LinkedCardRefreshService.apply(wrong, to: card))
        let missing = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit")
        XCTAssertThrowsError(try LinkedCardRefreshService.apply(missing, to: card))
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 100)
        XCTAssertNil(card.plaidUpdatedAt)
    }

    func testRefreshingSameSnapshotDoesNotAdvanceTimestamp() throws {
        let card = makeCard("card-1")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 325, updatedAt: timestamp)
        try LinkedCardRefreshService.apply(account, to: card)
        try LinkedCardRefreshService.apply(account, to: card)
        XCTAssertEqual(card.plaidUpdatedAt, timestamp)
    }

    func testReconcilePersistsBalanceAcrossSeparateStoresWithoutTransactions() throws {
        let mainContainer = try ModelContainer(for: Bill.self, Transaction.self, PaymentMethod.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let snapshotContainer = try ModelContainer(for: PlaidAccountSnapshot.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let mainContext = ModelContext(mainContainer)
        let snapshotContext = ModelContext(snapshotContainer)
        let card = makeCard("card-1")
        mainContext.insert(card)
        try mainContext.save()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        snapshotContext.insert(PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 425, updatedAt: timestamp))
        try snapshotContext.save()

        XCTAssertEqual(try LinkedCardRefreshService.reconcile(snapshotContext: snapshotContext, context: mainContext), 1)
        let reader = ModelContext(mainContainer)
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<Bill>()).first)
        XCTAssertEqual(saved.currentCreditCardDetails?.cardBalance, 425)
        XCTAssertEqual(saved.plaidUpdatedAt, timestamp)
        XCTAssertTrue(try reader.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }

    func testBatchRefreshUpdatesLinkedCardsWithoutTransactions() throws {
        let card = makeCard("card-1")
        let manual = makeCard("card-2")
        manual.plaidUnavailable = true
        let missingBalance = makeCard("card-3")
        let unmatched = makeCard("card-4")
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let accounts = [
            PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 325, updatedAt: timestamp),
            PlaidAccountSnapshot(accountID: "card-2", itemID: "bank", accountName: "Manual", type: "credit", currentBalance: 500, updatedAt: timestamp),
            PlaidAccountSnapshot(accountID: "card-3", itemID: "bank", accountName: "Missing", type: "credit", updatedAt: timestamp)
        ]
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest(accounts, to: [card, manual, missingBalance, unmatched]), 1)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 325)
        XCTAssertEqual(card.plaidUpdatedAt, timestamp)
        XCTAssertEqual(card.currentCreditCardDetails?.minimumPayment, 25)
        for unchanged in [manual, missingBalance, unmatched] {
            XCTAssertEqual(unchanged.currentCreditCardDetails?.cardBalance, 100)
            XCTAssertNil(unchanged.plaidUpdatedAt)
        }
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest(accounts, to: [card]), 0)
    }

    func testOlderSnapshotCannotRollBackCardBalanceOrTimestamp() throws {
        let card = makeCard("card-1")
        let newest = Date(timeIntervalSince1970: 1_800_000_000)
        card.plaidUpdatedAt = newest
        let old = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 900, updatedAt: newest.addingTimeInterval(-60))
        try LinkedCardRefreshService.apply(old, to: card)
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([old], to: [card]), 0)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 100)
        XCTAssertEqual(card.plaidUpdatedAt, newest)
    }

    func testDuplicateSnapshotsUseNewestBalanceIncludingCredit() throws {
        let card = makeCard("card-1")
        let newest = Date(timeIntervalSince1970: 1_800_000_000)
        let old = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 900, updatedAt: newest.addingTimeInterval(-60))
        let current = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: -25, updatedAt: newest)
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([current, old], to: [card]), 1)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, -25)
        XCTAssertEqual(card.plaidUpdatedAt, newest)
    }

    func testBankCreditDetailsUseReportedLimitAndPurchaseAPR() throws {
        let card = makeCard("card-1")
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 200, availableBalance: 600)
        var extra = PlaidAccountEnrichment()
        extra.creditLimit = 750
        extra.creditLiability = ["minimum_payment_amount": .number(35), "last_statement_balance": .number(250),
            "aprs": .array([.object(["apr_type": .string("cash_apr"), "apr_percentage": .number(29)]),
                            .object(["apr_type": .string("purchase_apr"), "apr_percentage": .number(17.5)])])]
        account.enrichmentJSON = try extra.encoded()
        try LinkedCardRefreshService.apply(account, to: card)
        XCTAssertEqual(card.currentCreditCardDetails?.creditLimit, 750)
        XCTAssertEqual(card.currentCreditCardDetails?.annualPercentageRate, 17.5)
        XCTAssertEqual(card.currentCreditCardDetails?.minimumPayment, 35)
        XCTAssertEqual(card.currentCreditCardDetails?.statementBalance, 250)
        XCTAssertEqual(card.amount, 25, "Keep the user's selected payment amount")
    }

    func testLiabilityChangesApplyWithoutNewBalanceTimestamp() throws {
        let card = makeCard("card-1")
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 100)
        try LinkedCardRefreshService.apply(account, to: card)
        var extra = PlaidAccountEnrichment()
        extra.creditLiability = ["minimum_payment_amount": .number(42)]
        account.enrichmentJSON = try extra.encoded()
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([account], to: [card]), 1)
        XCTAssertEqual(card.currentCreditCardDetails?.minimumPayment, 42)
        XCTAssertEqual(card.plaidUpdatedAt, account.updatedAt)
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([account], to: [card]), 0)
    }

    func testFirstBankTimestampReplacesLegacyCachedFetchTime() throws {
        let card = makeCard("card-1")
        card.plaidUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let bankDate = Date(timeIntervalSince1970: 1_799_990_000)
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 240, updatedAt: bankDate)
        var extra = PlaidAccountEnrichment()
        extra.balanceSource = "bank_reported"
        account.enrichmentJSON = try extra.encoded()
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([account], to: [card]), 1)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 240)
        XCTAssertEqual(card.plaidUpdatedAt, bankDate)
        account.currentBalance = 900
        account.updatedAt = bankDate.addingTimeInterval(-10)
        try LinkedCardRefreshService.apply(account, to: card)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 240)
    }

    func testForeignBalanceCannotEnterDollarCardTotals() throws {
        let card = makeCard("card-1")
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 900, currencyCode: "EUR")
        XCTAssertThrowsError(try LinkedCardRefreshService.apply(account, to: card))
        XCTAssertEqual(try LinkedCardRefreshService.applyLatest([account], to: [card]), 0)
        XCTAssertEqual(card.currentCreditCardDetails?.cardBalance, 100)
    }

    func testCloudPayloadUsesAssetForLargeHistoryAndReadsLegacyInlineData() throws {
        let record = CKRecord(recordType: "PlaidSyncSnapshot")
        let small = Data("legacy snapshot".utf8)
        XCTAssertNil(try PlaidCloudSyncService.setPayload(small, on: record))
        XCTAssertEqual(try PlaidCloudSyncService.payload(from: record), small)
        let large = Data(repeating: 65, count: 800_000)
        let file = try XCTUnwrap(PlaidCloudSyncService.setPayload(large, on: record))
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertNil(record["payload"])
        XCTAssertEqual(try PlaidCloudSyncService.payload(from: record), large)
    }

    func testEnrichmentSurvivesCloudRoundTripAndLegacyPayloadDecodes() throws {
        let account = PlaidAccountSnapshot(accountID: "card-1", itemID: "bank", accountName: "Card", type: "credit", currentBalance: 325)
        var extra = PlaidAccountEnrichment()
        extra.creditLimit = 1200
        account.enrichmentJSON = try extra.encoded()
        let encoded = try JSONEncoder().encode(PlaidCloudAccount(account))
        let decoded = try JSONDecoder().decode(PlaidCloudAccount.self, from: encoded)
        XCTAssertEqual(decoded.enrichmentJSON, account.enrichmentJSON)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "enrichmentJSON")
        let old = try JSONDecoder().decode(PlaidCloudAccount.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.enrichmentJSON)
        let review = PlaidTransactionReviewItem(plaidTransactionID: "tx", plaidAccountID: "card-1", plaidItemID: "bank", name: "Removed", amount: 10)
        review.bankRemovedAt = .now
        review.enrichmentJSON = "{}"
        let updatedAt = review.updatedAt
        review.status = .imported
        XCTAssertEqual(review.updatedAt, updatedAt)
        let transactionWire = try JSONDecoder().decode(PlaidCloudTransaction.self, from: JSONEncoder().encode(PlaidCloudTransaction(review)))
        XCTAssertEqual(transactionWire.bankRemovedAt, review.bankRemovedAt)
        XCTAssertEqual(transactionWire.enrichmentJSON, "{}")
    }

    func testInterruptedCloudReadRetriesAndReturnsSnapshot() async throws {
        var attempts = 0
        var delays: [Double] = []
        let expected = CKRecord(recordType: "PlaidSyncSnapshot")
        let result = try await PlaidCloudSyncService.readSnapshot(sleep: { delays.append($0) }) {
            attempts += 1
            if attempts < 3 { throw CKError(.operationCancelled) }
            return expected
        }
        XCTAssertEqual(result.recordID, expected.recordID)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(delays, [1, 2])
    }

    func testRepeatedCloudCancellationStopsAfterThreeAttempts() async {
        var attempts = 0
        do {
            _ = try await PlaidCloudSyncService.readSnapshot(sleep: { _ in }) {
                attempts += 1
                throw CKError(.operationCancelled)
            }
            XCTFail("Expected refresh failure")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .operationCancelled)
        }
        XCTAssertEqual(attempts, 3)
    }

    func testMissingSnapshotDoesNotRetry() async {
        var attempts = 0
        do {
            _ = try await PlaidCloudSyncService.readSnapshot(sleep: { _ in XCTFail("Unexpected retry") }) {
                attempts += 1
                throw CKError(.unknownItem)
            }
            XCTFail("Expected missing snapshot")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .unknownItem)
        }
        XCTAssertEqual(attempts, 1)
    }

    func testCloudReadRespectsServerBackoff() async throws {
        var attempts = 0
        var delays: [Double] = []
        _ = try await PlaidCloudSyncService.readSnapshot(sleep: { delays.append($0) }) {
            attempts += 1
            if attempts == 1 {
                throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 4.0])
            }
            return CKRecord(recordType: "PlaidSyncSnapshot")
        }
        XCTAssertEqual(delays, [4])
    }

    func testCancelledTaskDoesNotRetryCloudRead() async {
        let task = Task { @MainActor in
            try await PlaidCloudSyncService.readSnapshot(sleep: { _ in XCTFail("Unexpected retry") }) {
                withUnsafeCurrentTask { $0?.cancel() }
                throw CKError(.operationCancelled)
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected task cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func makeCard(_ accountID: String) -> Bill {
        Bill(name: "Card", amount: 25, dueDate: nil, category: .creditCard, recurrenceInterval: 1, recurrenceUnit: .month, creditCardDetails: CreditCardDetails(creditLimit: 1000, cardBalance: 100, annualPercentageRate: 19, minimumPayment: 25), plaidAccountID: accountID)
    }
}
