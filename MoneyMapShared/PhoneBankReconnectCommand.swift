import Foundation
import CloudKit

public enum PhoneBankReconnectState: String, Codable, Sendable {
    case requested, ready, succeeded, failed, canceled
}

public struct PhoneBankReconnectCommand: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var itemID: String
    public var state: PhoneBankReconnectState
    public var createdAt: Date
    public var expiresAt: Date
    public var hostedURL: URL?
    public var message: String?

    public init(itemID: String, now: Date = .now) {
        id = UUID().uuidString
        self.itemID = itemID
        state = .requested
        createdAt = now
        expiresAt = now.addingTimeInterval(1800)
        message = "Waiting for your Mac to prepare the bank sign-in."
    }

    public var isTerminal: Bool { [.succeeded, .failed, .canceled].contains(state) }
    public var hasExpired: Bool { expiresAt <= .now }
    public var sanitizedHostedURL: URL? {
        guard let hostedURL,
              let components = URLComponents(url: hostedURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "secure.plaid.com",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { return nil }
        return hostedURL
    }

    /// Used again against the latest server record immediately before a conditional save.
    public func canReplace(_ current: Self, now: Date = .now) -> Bool {
        guard id == current.id, itemID == current.itemID, createdAt == current.createdAt,
              expiresAt <= current.expiresAt, !current.isTerminal else { return false }
        if current.expiresAt <= now, state != .failed && state != .canceled { return false }
        switch (current.state, state) {
        case (.requested, .ready): return sanitizedHostedURL != nil
        case (.ready, .succeeded), (.requested, .failed), (.ready, .failed),
             (.requested, .canceled), (.ready, .canceled): return true
        default: return false
        }
    }
}

public enum PhoneBankReconnectError: LocalizedError {
    case anotherRequestPending, invalidItem, concurrentChange
    public var errorDescription: String? {
        switch self {
        case .anotherRequestPending: "Another bank reconnect is already in progress. Finish or cancel it before reconnecting this bank."
        case .invalidItem: "This bank connection is unavailable. Refresh Bank Sync and try again."
        case .concurrentChange: "The bank reconnect request changed on another device. Refresh its status and try again."
        }
    }
}

@MainActor
public enum PhoneBankReconnectCommandStore {
    private static var database: CKDatabase { CKContainer(identifier: "iCloud.com.heyjoshsmith.MoneyMap").privateCloudDatabase }
    private static let recordID = CKRecord.ID(recordName: "phone-bank-reconnect")

    public static func latest() async throws -> PhoneBankReconnectCommand? {
        let record = try await readRecord()
        return try decode(record)
    }

    /// Resumes a live request for this bank; never silently replaces another bank's request.
    public static func create(itemID: String) async throws -> PhoneBankReconnectCommand {
        guard !itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PhoneBankReconnectError.invalidItem }
        for attempt in 0..<3 {
            let record = try await readRecord()
            if let current = try decode(record), !current.isTerminal, !current.hasExpired {
                guard current.itemID == itemID else { throw PhoneBankReconnectError.anotherRequestPending }
                return current
            }
            let command = PhoneBankReconnectCommand(itemID: itemID)
            try encode(command, into: record)
            do { try await save(record); return command }
            catch where isConflict(error) && attempt < 2 { continue }
        }
        throw PhoneBankReconnectError.concurrentChange
    }

    @discardableResult
    public static func cancel(id: String) async throws -> Bool {
        guard var command = try await latest(), command.id == id, !command.isTerminal else { return false }
        command.state = .canceled
        command.hostedURL = nil
        command.message = "Bank reconnect canceled."
        return try await update(command)
    }

    /// Returns false when canceled, superseded, expired, or already terminal, without reviving it.
    @discardableResult
    public static func update(_ command: PhoneBankReconnectCommand) async throws -> Bool {
        for attempt in 0..<3 {
            let record = try await readRecord()
            guard let current = try decode(record), command.canReplace(current) else { return false }
            var sanitized = command
            if sanitized.isTerminal { sanitized.hostedURL = nil }
            try encode(sanitized, into: record)
            do { try await save(record); return true }
            catch where isConflict(error) && attempt < 2 { continue }
        }
        throw PhoneBankReconnectError.concurrentChange
    }

    private static func readRecord() async throws -> CKRecord {
        do { return try await PlaidCloudSyncService.readSnapshot { try await database.record(for: recordID) } }
        catch let error as CKError where error.code == .unknownItem {
            // Reuse the already deployed record type; no production schema change is needed.
            return CKRecord(recordType: "PlaidSyncSnapshot", recordID: recordID)
        }
    }

    private static func decode(_ record: CKRecord) throws -> PhoneBankReconnectCommand? {
        guard let payload = record["payload"] as? Data else { return nil }
        return try JSONDecoder().decode(PhoneBankReconnectCommand.self, from: payload)
    }

    private static func encode(_ command: PhoneBankReconnectCommand, into record: CKRecord) throws {
        record["payload"] = try JSONEncoder().encode(command)
        record["updatedAt"] = Date()
    }

    private static func save(_ record: CKRecord) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: [record])
        operation.savePolicy = .ifServerRecordUnchanged
        operation.isAtomic = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in continuation.resume(with: result.map { _ in () }) }
            database.add(operation)
        }
    }

    private static func isConflict(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        if error.code == .serverRecordChanged { return true }
        return error.partialErrorsByItemID?.values.contains { ($0 as? CKError)?.code == .serverRecordChanged } == true
    }
}
