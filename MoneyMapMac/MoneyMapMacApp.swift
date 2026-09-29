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
    @NSApplicationDelegateAdaptor(MacBackgroundLifecycle.self) private var lifecycle
    @AppStorage(MacBackgroundLifecycle.keepRunningKey) private var keepRunning = true
    private let modelContainer: ModelContainer
    private let coordinator: MacPlaidSyncCoordinator

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
        coordinator = MacPlaidSyncCoordinator()
        coordinator.startAutomaticRefresh(context: modelContainer.mainContext)
    }

    var body: some Scene {
        Window("MoneyMap", id: "main") {
            MacWorkspaceRoot(coordinator: coordinator, lifecycle: lifecycle)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button(keepRunning ? "Close Window & Keep Syncing" : "Quit MoneyMap") { lifecycle.closeWorkspaceOrQuit() }
                    .keyboardShortcut("q")
                if keepRunning {
                    Button("Quit MoneyMap Completely") { lifecycle.quitCompletely() }
                        .keyboardShortcut("q", modifiers: [.command, .option])
                }
            }
        }

        MenuBarExtra {
            MacMenuBarView(coordinator: coordinator, lifecycle: lifecycle).modelContainer(modelContainer)
        } label: { MacMenuBarIcon() }
        .menuBarExtraStyle(.window)

        Settings {
            MacBankSyncSettingsView(coordinator: coordinator)
                .modelContainer(modelContainer)
        }
    }
}

private struct MacWorkspaceRoot: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    @ObservedObject var lifecycle: MacBackgroundLifecycle
    var body: some View {
        MacBankSyncDashboardView(coordinator: coordinator)
            .background(MacWorkspaceWindowBridge(lifecycle: lifecycle, openWindow: { openWindow(id: "main") }))
            .toolbar {
                ToolbarItem { Button { lifecycle.moveToMenuBar() } label: { Label("Move to Menu Bar", systemImage: "menubar.rectangle") }.help("Hide the Dock icon and keep bank sync running") }
            }
    }
}
