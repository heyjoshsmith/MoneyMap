// SharedModelContainerFactory.swift
// MoneyMap
// Provides a shared way to construct the SwiftData ModelContainer for both the app and extensions (e.g., App Intents).

import Foundation
import SwiftData

enum SharedModelContainerFactory {
    static func make() throws -> ModelContainer {
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")!
        let storeURL = containerURL.appendingPathComponent("shared.sqlite")

        let schema = Schema([Goal.self, PaydayConfig.self, Bill.self])

        // Try CloudKit-backed configuration first
        if let container = try? ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
            ]
        ) {
            return container
        }

        // Fall back to local-only configuration
        return try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            ]
        )
    }
}
