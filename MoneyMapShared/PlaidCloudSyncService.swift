//
//  PlaidCloudSyncService.swift
//  MoneyMapShared
//
//  Created by Codex on 7/6/26.
//

import CloudKit
import Foundation
import SwiftData

@MainActor
public enum PlaidCloudSyncService {
    private static let database = CKContainer(identifier: "iCloud.com.heyjoshsmith.MoneyMap").privateCloudDatabase
    private static let snapshotRecordID = CKRecord.ID(recordName: "primary")
    private static let macRefreshCommandRecordID = CKRecord.ID(recordName: "mac-refresh")

    public static func push(context: ModelContext) async throws {
        #if !os(macOS)
        // Bank snapshots belong to the Mac. A phone must never publish an older copy over a newer scan.
        try await pushReviewDecisions(context: context)
        return
        #else
        try await pullReviewDecisions(context: context)

        let snapshot = PlaidCloudSnapshot(
            updatedAt: .now,
            connections: try context.fetch(FetchDescriptor<PlaidConnection>()).map(PlaidCloudConnection.init),
            accounts: try context.fetch(FetchDescriptor<PlaidAccountSnapshot>()).map(PlaidCloudAccount.init),
            transactions: try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>()).map(PlaidCloudTransaction.init),
            suggestions: try context.fetch(FetchDescriptor<PlaidSuggestion>()).map(PlaidCloudSuggestion.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let record = CKRecord(recordType: "PlaidSyncSnapshot", recordID: snapshotRecordID)
        let temporaryFile = try setPayload(encoder.encode(snapshot), on: record)
        defer { if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) } }
        record["updatedAt"] = snapshot.updatedAt

        try await save(record)
        #endif
    }

    public static func pull(context: ModelContext) async throws {
        let record: CKRecord
        do {
            record = try await readSnapshot {
                try await database.record(for: snapshotRecordID)
            }
        } catch {
            throw mapCloudKitError(error, missingSnapshotError: .missingSnapshot)
        }

        try applySnapshotPayload(payload(from: record), context: context, sourceUpdatedAt: record.modificationDate)
    }

    private static var appliedSnapshotDates: [String: Date] = [:]
    private static let inMemorySnapshotDates = NSMapTable<ModelContainer, NSDate>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory
    )

    /// Envelope ordering matters: individual account timestamps describe bank balances and can
    /// intentionally remain unchanged while fresh liabilities or removal facts arrive.
    static func applySnapshotPayload(_ payload: Data, context: ModelContext, sourceUpdatedAt: Date? = nil) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(PlaidCloudSnapshot.self, from: payload)
        let versionDate = sourceUpdatedAt ?? snapshot.updatedAt
        let configurations = context.container.configurations
        let persistentURLs = configurations.filter { !$0.isStoredInMemoryOnly }.map(\.url)
        let defaultsKey: String?
        let lastApplied: Date
        if persistentURLs.isEmpty {
            // Weak identity keys disappear with the container; a reused allocation address cannot
            // inherit an unrelated in-memory store's previously downloaded snapshot version.
            defaultsKey = nil
            lastApplied = inMemorySnapshotDates.object(forKey: context.container) as Date? ?? .distantPast
        } else {
            // Recreating a local store starts a new ordering history, even at the same path.
            let storeIdentity = persistentURLs.map { url in
                let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
                return "\(url.absoluteString)|\(created?.timeIntervalSince1970 ?? 0)"
            }.sorted().joined(separator: ";")
            let key = "plaid.cloud.appliedSnapshot." + Data(storeIdentity.utf8).base64EncodedString()
            defaultsKey = key
            let persistedDate = UserDefaults.standard.object(forKey: key) as? Date
            lastApplied = max(appliedSnapshotDates[key] ?? .distantPast, persistedDate ?? .distantPast)
        }
        guard versionDate >= lastApplied else { return }
        try upsertConnections(snapshot.connections, context: context)
        try upsertAccounts(snapshot.accounts, context: context)
        try upsertTransactions(snapshot.transactions, context: context)
        try upsertSuggestions(snapshot.suggestions, context: context)
        try context.save()
        if let defaultsKey {
            appliedSnapshotDates[defaultsKey] = versionDate
            UserDefaults.standard.set(versionDate, forKey: defaultsKey)
        } else {
            inMemorySnapshotDates.setObject(versionDate as NSDate, forKey: context.container)
        }
    }

    /// Import is an irreversible completed review action in the current UI. A stale skip/ready
    /// copy from another device must not turn an imported row back into a review candidate.
    static func mergedReviewStatus(_ first: String?, _ second: String?) -> String {
        let values = [first, second].compactMap { $0 }
        if values.contains(PlaidReviewStatus.imported.rawValue) { return PlaidReviewStatus.imported.rawValue }
        if values.contains(PlaidReviewStatus.skipped.rawValue) { return PlaidReviewStatus.skipped.rawValue }
        return PlaidReviewStatus.ready.rawValue
    }

    /// Large histories use an asset instead of exceeding CloudKit's inline record limit.
    static func setPayload(_ data: Data, on record: CKRecord) throws -> URL? {
        if data.count < 700_000 {
            record["payload"] = data
            record["payloadAsset"] = nil
            return nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plaid-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        record["payload"] = nil
        record["payloadAsset"] = CKAsset(fileURL: url)
        return url
    }

    static func payload(from record: CKRecord) throws -> Data {
        if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL {
            return try Data(contentsOf: url)
        }
        guard let data = record["payload"] as? Data else { throw PlaidCloudSyncError.missingSnapshotPayload }
        return data
    }

    private static let reviewRecordID = CKRecord.ID(recordName: "review-decisions")

    private struct ReviewDecisions: Codable {
        var transactions: [String: String] = [:]
        var suggestions: [String: String] = [:]
    }

    private static func readReviewRecord() async throws -> CKRecord {
        do { return try await readSnapshot { try await database.record(for: reviewRecordID) } }
        catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: "PlaidSyncSnapshot", recordID: reviewRecordID)
        }
    }

    private static func decisions(from record: CKRecord) throws -> ReviewDecisions {
        if record["payload"] == nil && record["payloadAsset"] == nil { return ReviewDecisions() }
        return try JSONDecoder().decode(ReviewDecisions.self, from: payload(from: record))
    }

    private static func pushReviewDecisions(context: ModelContext) async throws {
        for attempt in 0..<3 {
            let record = try await readReviewRecord()
            var values = try decisions(from: record)
            for item in try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>()) where item.status != .ready {
                values.transactions[item.plaidTransactionID] = mergedReviewStatus(values.transactions[item.plaidTransactionID], item.statusRaw)
            }
            for item in try context.fetch(FetchDescriptor<PlaidSuggestion>()) where item.status != .ready {
                values.suggestions[item.id.uuidString] = mergedReviewStatus(values.suggestions[item.id.uuidString], item.statusRaw)
            }
            let file = try setPayload(JSONEncoder().encode(values), on: record)
            defer { if let file { try? FileManager.default.removeItem(at: file) } }
            record["updatedAt"] = Date()
            do {
                _ = try await database.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                continue
            }
        }
    }

    private static func pullReviewDecisions(context: ModelContext) async throws {
        let values = try decisions(from: await readReviewRecord())
        for item in try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>()) {
            if let status = values.transactions[item.plaidTransactionID] { item.statusRaw = mergedReviewStatus(item.statusRaw, status) }
        }
        for item in try context.fetch(FetchDescriptor<PlaidSuggestion>()) {
            if let status = values.suggestions[item.id.uuidString] { item.statusRaw = mergedReviewStatus(item.statusRaw, status) }
        }
        try context.save()
    }

    // Retry reads only: interrupted requests are safe to repeat without duplicating writes.
    static func readSnapshot(
        sleep: (Double) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        fetch: () async throws -> CKRecord
    ) async throws -> CKRecord {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                let record = try await fetch()
                try Task.checkCancellation()
                return record
            } catch {
                try Task.checkCancellation()
                guard let cloudError = error as? CKError,
                      [.operationCancelled, .networkFailure, .serviceUnavailable,
                       .requestRateLimited, .zoneBusy].contains(cloudError.code),
                      attempt < 2 else { throw error }
                let delay = max(cloudError.retryAfterSeconds ?? 0, Double(attempt + 1))
                // Long server backoffs belong to a later user refresh.
                guard delay <= 10 else { throw error }
                try await sleep(delay)
            }
        }
        throw CancellationError()
    }

    public static func requestMacRefresh(source: String) async throws -> PlaidMacRefreshCommand {
        let command = PlaidMacRefreshCommand(
            requestID: UUID().uuidString,
            source: source,
            state: .pending,
            requestedAt: .now,
            startedAt: nil,
            completedAt: nil,
            message: nil,
            handledBy: nil
        )
        let record = CKRecord(recordType: "PlaidSyncSnapshot", recordID: macRefreshCommandRecordID)
        try apply(command, to: record)
        try await save(record)
        return command
    }

    public static func latestMacRefreshCommand() async throws -> PlaidMacRefreshCommand? {
        do {
            let record = try await database.record(for: macRefreshCommandRecordID)
            return try macRefreshCommand(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw mapCloudKitError(error)
        }
    }

    public static func updateMacRefreshCommand(
        requestID: String,
        state: PlaidMacRefreshCommandState,
        message: String?,
        handledBy: String?
    ) async throws {
        let record: CKRecord
        do {
            record = try await database.record(for: macRefreshCommandRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            throw mapCloudKitError(error)
        }

        guard var command = try macRefreshCommand(from: record), command.requestID == requestID else {
            return
        }

        command.state = state
        command.message = message
        if state == .running {
            command.startedAt = Date()
        }
        if state == .completed || state == .failed {
            command.completedAt = Date()
        }
        command.handledBy = handledBy
        try apply(command, to: record)
        try await save(record)
    }
}

public enum PlaidCloudSyncError: LocalizedError {
    case missingSnapshot
    case missingSnapshotPayload
    case cloudUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingSnapshot:
            return "No Mac bank-sync snapshot has reached iCloud yet. Open MoneyMap for Mac and let it sync once."
        case .missingSnapshotPayload:
            return "The Plaid iCloud snapshot exists but does not contain sync data."
        case .cloudUnavailable(let message):
            return message
        }
    }
}

public enum PlaidMacRefreshCommandState: String, Codable {
    case pending
    case running
    case completed
    case failed
}

public struct PlaidMacRefreshCommand: Codable, Equatable {
    public var requestID: String
    public var source: String
    public var state: PlaidMacRefreshCommandState
    public var requestedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var message: String?
    public var handledBy: String?

    public init(
        requestID: String,
        source: String,
        state: PlaidMacRefreshCommandState,
        requestedAt: Date,
        startedAt: Date?,
        completedAt: Date?,
        message: String?,
        handledBy: String?
    ) {
        self.requestID = requestID
        self.source = source
        self.state = state
        self.requestedAt = requestedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.message = message
        self.handledBy = handledBy
    }
}

private extension PlaidCloudSyncService {
    static func save(_ record: CKRecord) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: [record])
        operation.savePolicy = .allKeys
        do {
            try await withCheckedThrowingContinuation { continuation in
                operation.modifyRecordsResultBlock = { result in
                    continuation.resume(with: result.map { _ in () })
                }
                database.add(operation)
            }
        } catch {
            throw mapCloudKitError(error)
        }
    }

    static func apply(_ command: PlaidMacRefreshCommand, to record: CKRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        record["payload"] = try encoder.encode(command)
        record["updatedAt"] = Date()
    }

    static func macRefreshCommand(from record: CKRecord) throws -> PlaidMacRefreshCommand? {
        guard let payload = record["payload"] as? Data else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaidMacRefreshCommand.self, from: payload)
    }

    static func mapCloudKitError(
        _ error: Error,
        missingSnapshotError: PlaidCloudSyncError? = nil
    ) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        guard let ckError = error as? CKError else {
            return error
        }

        if ckError.code == .unknownItem, let missingSnapshotError {
            return missingSnapshotError
        }

        switch ckError.code {
        case .operationCancelled:
            return PlaidCloudSyncError.cloudUnavailable("The bank update was interrupted. Please try again.")
        case .notAuthenticated:
            return PlaidCloudSyncError.cloudUnavailable("Sign in to iCloud on this device before using Bank Sync.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return PlaidCloudSyncError.cloudUnavailable("iCloud is not reachable right now. Keep MoneyMap open and try again after the connection settles.")
        default:
            return PlaidCloudSyncError.cloudUnavailable("Bank Sync could not reach iCloud: \(ckError.localizedDescription)")
        }
    }

    static func run(_ operation: CKModifyRecordsOperation) async throws {
        do {
            try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result.map { _ in () })
            }
            database.add(operation)
            }
        } catch {
            throw mapCloudKitError(error)
        }
    }

    static func upsertConnections(_ items: [PlaidCloudConnection], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidConnection>())
        let byItemID = Dictionary(existing.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshotItemIDs = Set(items.map(\.itemID))

        for connection in existing where !snapshotItemIDs.contains(connection.itemID) {
            context.delete(connection)
        }

        for item in items {
            let connection = byItemID[item.itemID] ?? PlaidConnection(itemID: item.itemID)
            connection.institutionID = item.institutionID
            connection.institutionName = item.institutionName
            connection.status = item.status
            connection.lastSyncAt = item.lastSyncAt
            connection.createdAt = item.createdAt
            connection.updatedAt = item.updatedAt
            connection.enrichmentJSON = item.enrichmentJSON
            connection.errorMessage = item.errorMessage
            if byItemID[item.itemID] == nil {
                context.insert(connection)
            }
        }
    }

    static func upsertAccounts(_ items: [PlaidCloudAccount], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        let byAccountID = Dictionary(existing.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshotAccountIDs = Set(items.map(\.accountID))

        for account in existing where !snapshotAccountIDs.contains(account.accountID) {
            context.delete(account)
        }

        for item in items {
            let account = byAccountID[item.accountID] ?? PlaidAccountSnapshot(
                accountID: item.accountID,
                itemID: item.itemID,
                accountName: item.accountName,
                type: item.type
            )
            account.itemID = item.itemID
            account.institutionName = item.institutionName
            account.accountName = item.accountName
            account.officialName = item.officialName
            account.mask = item.mask
            account.type = item.type
            account.subtype = item.subtype
            account.currentBalance = item.currentBalance
            account.availableBalance = item.availableBalance
            account.currencyCode = item.currencyCode
            account.updatedAt = item.updatedAt
            account.enrichmentJSON = item.enrichmentJSON
            if byAccountID[item.accountID] == nil {
                context.insert(account)
            }
        }
    }

    static func upsertTransactions(_ items: [PlaidCloudTransaction], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidTransactionReviewItem>())
        let byTransactionID = Dictionary(existing.map { ($0.plaidTransactionID, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshotTransactionIDs = Set(items.map(\.plaidTransactionID))

        for transaction in existing where !snapshotTransactionIDs.contains(transaction.plaidTransactionID) {
            context.delete(transaction)
        }

        for item in items {
            let transaction = byTransactionID[item.plaidTransactionID] ?? PlaidTransactionReviewItem(
                plaidTransactionID: item.plaidTransactionID,
                plaidAccountID: item.plaidAccountID,
                plaidItemID: item.plaidItemID,
                name: item.name,
                amount: item.amount
            )
            transaction.plaidAccountID = item.plaidAccountID
            transaction.plaidItemID = item.plaidItemID
            transaction.name = item.name
            transaction.merchantName = item.merchantName
            transaction.category = item.category
            transaction.date = item.date
            transaction.authorizedDate = item.authorizedDate
            transaction.amount = item.amount
            transaction.currencyCode = item.currencyCode
            transaction.pending = item.pending
            transaction.pendingTransactionID = item.pendingTransactionID
            // Keep local review choices while accepting fresh bank-owned fields.
            transaction.statusRaw = mergedReviewStatus(transaction.statusRaw, item.statusRaw)
            transaction.createdAt = item.createdAt
            transaction.updatedAt = item.updatedAt
            transaction.enrichmentJSON = item.enrichmentJSON
            transaction.bankRemovedAt = item.bankRemovedAt
            if byTransactionID[item.plaidTransactionID] == nil {
                context.insert(transaction)
            }
        }
    }

    static func upsertSuggestions(_ items: [PlaidCloudSuggestion], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PlaidSuggestion>())
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshotIDs = Set(items.map(\.id))

        for suggestion in existing where !snapshotIDs.contains(suggestion.id) {
            context.delete(suggestion)
        }

        for item in items {
            let suggestion = byID[item.id] ?? PlaidSuggestion(
                kind: PlaidSuggestionKind(rawValue: item.kindRaw) ?? .paymentMethod,
                plaidAccountID: item.plaidAccountID,
                plaidItemID: item.plaidItemID,
                title: item.title
            )
            suggestion.id = item.id
            suggestion.kindRaw = item.kindRaw
            suggestion.plaidAccountID = item.plaidAccountID
            suggestion.plaidItemID = item.plaidItemID
            suggestion.title = item.title
            suggestion.detail = item.detail
            suggestion.amount = item.amount
            suggestion.dueDate = item.dueDate
            suggestion.statusRaw = mergedReviewStatus(suggestion.statusRaw, item.statusRaw)
            suggestion.createdAt = item.createdAt
            suggestion.updatedAt = item.updatedAt
            if byID[item.id] == nil {
                context.insert(suggestion)
            }
        }
    }
}

private struct PlaidCloudSnapshot: Codable {
    var updatedAt: Date
    var connections: [PlaidCloudConnection]
    var accounts: [PlaidCloudAccount]
    var transactions: [PlaidCloudTransaction]
    var suggestions: [PlaidCloudSuggestion]
}

struct PlaidCloudConnection: Codable {
    var enrichmentJSON: String?
    var itemID: String
    var institutionID: String?
    var institutionName: String?
    var status: String?
    var lastSyncAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var errorMessage: String?

    init(_ connection: PlaidConnection) {
        enrichmentJSON = connection.enrichmentJSON
        itemID = connection.itemID
        institutionID = connection.institutionID
        institutionName = connection.institutionName
        status = connection.status
        lastSyncAt = connection.lastSyncAt
        createdAt = connection.createdAt
        updatedAt = connection.updatedAt
        errorMessage = connection.errorMessage
    }
}

struct PlaidCloudAccount: Codable {
    var enrichmentJSON: String?
    var accountID: String
    var itemID: String
    var institutionName: String?
    var accountName: String
    var officialName: String?
    var mask: String?
    var type: String
    var subtype: String?
    var currentBalance: Double?
    var availableBalance: Double?
    var currencyCode: String?
    var updatedAt: Date

    init(_ account: PlaidAccountSnapshot) {
        enrichmentJSON = account.enrichmentJSON
        accountID = account.accountID
        itemID = account.itemID
        institutionName = account.institutionName
        accountName = account.accountName
        officialName = account.officialName
        mask = account.mask
        type = account.type
        subtype = account.subtype
        currentBalance = account.currentBalance
        availableBalance = account.availableBalance
        currencyCode = account.currencyCode
        updatedAt = account.updatedAt
    }
}

struct PlaidCloudTransaction: Codable {
    var bankRemovedAt: Date?
    var enrichmentJSON: String?
    var plaidTransactionID: String
    var plaidAccountID: String
    var plaidItemID: String
    var name: String
    var merchantName: String?
    var category: String?
    var date: Date?
    var authorizedDate: Date?
    var amount: Double
    var currencyCode: String?
    var pending: Bool
    var pendingTransactionID: String?
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(_ transaction: PlaidTransactionReviewItem) {
        bankRemovedAt = transaction.bankRemovedAt
        enrichmentJSON = transaction.enrichmentJSON
        plaidTransactionID = transaction.plaidTransactionID
        plaidAccountID = transaction.plaidAccountID
        plaidItemID = transaction.plaidItemID
        name = transaction.name
        merchantName = transaction.merchantName
        category = transaction.category
        date = transaction.date
        authorizedDate = transaction.authorizedDate
        amount = transaction.amount
        currencyCode = transaction.currencyCode
        pending = transaction.pending
        pendingTransactionID = transaction.pendingTransactionID
        statusRaw = transaction.statusRaw
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
    }
}

private struct PlaidCloudSuggestion: Codable {
    var id: UUID
    var kindRaw: String
    var plaidAccountID: String
    var plaidItemID: String
    var title: String
    var detail: String?
    var amount: Double?
    var dueDate: Date?
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(_ suggestion: PlaidSuggestion) {
        id = suggestion.id
        kindRaw = suggestion.kindRaw
        plaidAccountID = suggestion.plaidAccountID
        plaidItemID = suggestion.plaidItemID
        title = suggestion.title
        detail = suggestion.detail
        amount = suggestion.amount
        dueDate = suggestion.dueDate
        statusRaw = suggestion.statusRaw
        createdAt = suggestion.createdAt
        updatedAt = suggestion.updatedAt
    }
}
