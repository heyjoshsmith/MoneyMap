import XCTest
import CloudKit
@testable import MoneyMap

@MainActor
final class LinkedCardRefreshTests: XCTestCase {
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
