//
//  SharedModelContainerFactory.swift
//  MoneyMapShared
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SwiftData

public enum MoneyMapSharedContainerMode: String {
    case cloudKit
    case localOnly
    case inMemory

    public var displayName: String {
        switch self {
        case .cloudKit:
            return "iCloud sync"
        case .localOnly:
            return "Local only"
        case .inMemory:
            return "Temporary memory"
        }
    }
}

public struct MoneyMapSharedContainerReport {
    public let mode: MoneyMapSharedContainerMode
    public let storeURL: URL?
    public let fallbackReason: String?

    public init(mode: MoneyMapSharedContainerMode, storeURL: URL?, fallbackReason: String? = nil) {
        self.mode = mode
        self.storeURL = storeURL
        self.fallbackReason = fallbackReason
    }
}

public enum MoneyMapSharedContainerFactory {
    public private(set) static var lastReport = MoneyMapSharedContainerReport(
        mode: .inMemory,
        storeURL: nil,
        fallbackReason: "The shared container has not been opened yet."
    )

    public static func make() throws -> ModelContainer {
        let schema = sharedSchema()

        let containerURL = try storeDirectory()

        let storeURL = containerURL.appendingPathComponent("shared.sqlite")

        if isRunningUnderXCTest {
            let container = try ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
                ]
            )
            lastReport = MoneyMapSharedContainerReport(mode: .localOnly, storeURL: storeURL, fallbackReason: "Unit tests use local storage.")
            writeDiagnostic(lastReport)
            return container
        }

        do {
            let cloudContainer = try ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private("iCloud.com.heyjoshsmith.MoneyMap"))
                ]
            )
            lastReport = MoneyMapSharedContainerReport(mode: .cloudKit, storeURL: storeURL)
            writeDiagnostic(lastReport)
            return cloudContainer
        } catch {
            let cloudError = error
            do {
                let localContainer = try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
                    ]
                )
                lastReport = MoneyMapSharedContainerReport(mode: .localOnly, storeURL: storeURL, fallbackReason: detailedErrorDescription(cloudError))
                writeDiagnostic(lastReport)
                return localContainer
            } catch {
                lastReport = MoneyMapSharedContainerReport(
                    mode: .inMemory,
                    storeURL: storeURL,
                    fallbackReason: "CloudKit: \(detailedErrorDescription(cloudError))\nLocal: \(detailedErrorDescription(error))"
                )
                writeDiagnostic(lastReport)
                throw error
            }
        }
    }

    public static func makeInMemory(fallbackReason: String = "The persistent shared store could not be opened.") -> ModelContainer {
        let schema = sharedSchema()

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            lastReport = MoneyMapSharedContainerReport(mode: .inMemory, storeURL: nil, fallbackReason: fallbackReason)
            writeDiagnostic(lastReport)
            return container
        }

        preconditionFailure("Could not create an in-memory shared SwiftData container.")
    }

    private static func sharedSchema() -> Schema {
        Schema([
            Goal.self,
            PaydayConfig.self,
            Bill.self,
            Transaction.self,
            AuditEvent.self,
            PaymentMethod.self,
            PlaidConnection.self,
            PlaidAccountSnapshot.self,
            PlaidTransactionReviewItem.self,
            PlaidSuggestion.self,
            ManualSavingsAccount.self,
            ExtraMoneyPlan.self,
            ExtraMoneyPlanItem.self
        ])
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
        let macURL = applicationSupportURL.appendingPathComponent("MoneyMap", isDirectory: true)
        try fileManager.createDirectory(at: macURL, withIntermediateDirectories: true)
        return macURL
        #else
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
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
        #endif
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func detailedErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"]

        if !nsError.userInfo.isEmpty {
            let userInfo = nsError.userInfo
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "; ")
            parts.append(userInfo)
        }

        return parts.joined(separator: " | ")
    }

    private static func writeDiagnostic(_ report: MoneyMapSharedContainerReport) {
        UserDefaults.standard.set(report.mode.rawValue, forKey: "MoneyMapSharedContainerDiagnostic.mode")
        UserDefaults.standard.set(report.storeURL?.path, forKey: "MoneyMapSharedContainerDiagnostic.storeURL")
        UserDefaults.standard.set(report.fallbackReason, forKey: "MoneyMapSharedContainerDiagnostic.fallbackReason")
        UserDefaults.standard.set(Date(), forKey: "MoneyMapSharedContainerDiagnostic.date")

        guard let directory = diagnosticDirectory() else { return }

        let body = [
            "mode=\(report.mode.rawValue)",
            "storeURL=\(report.storeURL?.path ?? "nil")",
            "fallbackReason=\(report.fallbackReason ?? "nil")",
            "date=\(ISO8601DateFormatter().string(from: Date()))"
        ].joined(separator: "\n")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? body.write(to: directory.appendingPathComponent("MoneyMapSharedContainerDiagnostic.txt"), atomically: true, encoding: .utf8)
    }

    private static func diagnosticDirectory() -> URL? {
        let fileManager = FileManager.default

        #if os(macOS)
        return try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MoneyMap", isDirectory: true)
        #else
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") {
            return containerURL
        }

        return try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MoneyMap", isDirectory: true)
        #endif
    }
}
