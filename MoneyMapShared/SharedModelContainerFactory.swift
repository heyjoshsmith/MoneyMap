//
//  SharedModelContainerFactory.swift
//  MoneyMapShared
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SwiftData

public enum MoneyMapSharedContainerFactory {
    public static func make() throws -> ModelContainer {
        let schema = sharedSchema()

        let containerURL = try storeDirectory()

        let storeURL = containerURL.appendingPathComponent("shared.sqlite")

        if let cloudContainer = try? ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
            ]
        ) {
            return cloudContainer
        }

        return try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        )
    }

    public static func makeInMemory() -> ModelContainer {
        let schema = sharedSchema()

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            return container
        }

        preconditionFailure("Could not create an in-memory shared SwiftData container.")
    }

    private static func sharedSchema() -> Schema {
        Schema([Goal.self, PaydayConfig.self, Bill.self, Transaction.self, AuditEvent.self])
    }

    private static func storeDirectory() throws -> URL {
        let fileManager = FileManager.default

        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") {
            return containerURL
        }

        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fallbackURL = applicationSupportURL.appendingPathComponent("MoneyMap", isDirectory: true)
        try fileManager.createDirectory(at: fallbackURL, withIntermediateDirectories: true)
        return fallbackURL
    }
}
