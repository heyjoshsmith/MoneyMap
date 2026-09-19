import Foundation
import CloudKit

/// Populated only after physical Watch authentication is verified for an institution.
public enum WatchBankCompatibility {
    public static let verifiedInstitutionIDs: Set<String> = []
}

public struct WatchBankCommand: Codable, Identifiable {
    public var id: String
    public var action: String
    public var itemID: String?
    public var state: String
    public var createdAt: Date
    public var expiresAt: Date
    public var hostedURL: URL?
    public var message: String?
    public init(action: String, itemID: String? = nil) {
        id = UUID().uuidString; self.action = action; self.itemID = itemID; state = "requested"
        createdAt = .now; expiresAt = Date().addingTimeInterval(1800)
    }
    public var isTerminal: Bool { ["succeeded", "failed", "canceled", "expired"].contains(state) }
}

public enum WatchBankCommandStore {
    private static var database: CKDatabase { CKContainer(identifier: "iCloud.com.heyjoshsmith.MoneyMap").privateCloudDatabase }
    private static let recordType = "WatchBankCommand"
    public static func create(_ command: WatchBankCommand) async throws {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: "watch-bank-\(command.id)"))
        record["payload"] = try JSONEncoder().encode(command)
        _ = try await database.save(record)
    }
    public static func fetch(_ id: String) async throws -> WatchBankCommand {
        let record = try await database.record(for: CKRecord.ID(recordName: "watch-bank-\(id)"))
        return try decode(record)
    }
    public static func update(_ command: WatchBankCommand) async throws {
        let record = try await database.record(for: CKRecord.ID(recordName: "watch-bank-\(command.id)"))
        let existing = try decode(record)
        guard !existing.isTerminal else { return }
        record["payload"] = try JSONEncoder().encode(command)
        _ = try await database.save(record)
    }
    public static func pending() async throws -> [WatchBankCommand] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, resultsLimit: 100)
        var commands: [WatchBankCommand] = []
        while true {
            for (_, result) in page.matchResults {
                let value = try decode(result.get())
                if !value.isTerminal { commands.append(value) }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
        }
        return commands.sorted { $0.createdAt < $1.createdAt }
    }
    private static func decode(_ record: CKRecord) throws -> WatchBankCommand {
        guard let data = record["payload"] as? Data else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(WatchBankCommand.self, from: data)
    }
}
