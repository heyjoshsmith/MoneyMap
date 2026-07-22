//
//  PlaidSyncContainerFactory.swift
//  MoneyMapShared
//
//  Created by Codex on 7/6/26.
//

import Foundation
import SwiftData

public enum PlaidSyncContainerFactory {
    public private(set) static var lastReport = MoneyMapSharedContainerReport(
        mode: .inMemory,
        storeURL: nil,
        fallbackReason: "The Plaid sync container has not been opened yet."
    )

    public static func make() throws -> ModelContainer {
        let schema = Schema([
            PlaidConnection.self,
            PlaidAccountSnapshot.self,
            PlaidTransactionReviewItem.self,
            PlaidSuggestion.self
        ])
        let storeURL = try storeDirectory().appendingPathComponent("plaid-sync.sqlite")

        if isRunningUnderXCTest {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)]
            )
            lastReport = MoneyMapSharedContainerReport(mode: .localOnly, storeURL: storeURL, fallbackReason: "Unit tests use local storage.")
            return container
        }

        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)]
        )
        lastReport = MoneyMapSharedContainerReport(mode: .cloudKit, storeURL: storeURL, fallbackReason: "Plaid data uses a local cache with direct iCloud upload/download.")
        return container
    }

    public static func makeInMemory(fallbackReason: String) -> ModelContainer {
        let schema = Schema([
            PlaidConnection.self,
            PlaidAccountSnapshot.self,
            PlaidTransactionReviewItem.self,
            PlaidSuggestion.self
        ])
        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            lastReport = MoneyMapSharedContainerReport(mode: .inMemory, storeURL: nil, fallbackReason: fallbackReason)
            return container
        }

        preconditionFailure("Could not create an in-memory Plaid sync container.")
    }

    private static func storeDirectory() throws -> URL {
        let fileManager = FileManager.default

        #if os(macOS)
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupportURL.appendingPathComponent("MoneyMap", isDirectory: true)
        #else
        let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MoneyMap", isDirectory: true)
        #endif

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func detailedErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.userInfo.isEmpty {
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }

        let userInfo = nsError.userInfo
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription) | \(userInfo)"
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
