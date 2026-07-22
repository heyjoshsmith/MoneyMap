//
//  MoneyMapMacApp.swift
//  MoneyMapMac
//
//  Created by Codex on 7/6/26.
//

import SwiftData
import SwiftUI

@main
struct MoneyMapMacApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try PlaidSyncContainerFactory.make()
            let report = PlaidSyncContainerFactory.lastReport
            try? "mode=\(report.mode.rawValue)\nstore=\(report.storeURL?.path ?? "nil")\nreason=\(report.fallbackReason ?? "nil")\n".write(
                to: URL(fileURLWithPath: "/tmp/MoneyMapMacStorageDiagnostic.txt"),
                atomically: true,
                encoding: .utf8
            )
            print("MoneyMap for Mac storage mode: \(report.mode.rawValue), store: \(report.storeURL?.path ?? "nil"), reason: \(report.fallbackReason ?? "nil")")
        } catch {
            let fallbackReason = "The Plaid sync store could not be opened: \(error.localizedDescription)"
            modelContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: fallbackReason)
            try? "mode=inMemory\nstore=nil\nreason=\(fallbackReason)\n".write(
                to: URL(fileURLWithPath: "/tmp/MoneyMapMacStorageDiagnostic.txt"),
                atomically: true,
                encoding: .utf8
            )
            print("MoneyMap for Mac is using in-memory data. \(fallbackReason)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MacBankSyncDashboardView()
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            MacBankSyncSettingsView()
                .modelContainer(modelContainer)
        }
    }
}
