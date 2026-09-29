import SwiftData
import SwiftUI

struct MacMenuBarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \PlaidConnection.updatedAt, order: .reverse) private var connections: [PlaidConnection]
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    @ObservedObject var lifecycle: MacBackgroundLifecycle
    @AppStorage(MacBankSyncPreferences.automaticRefreshEnabledKey) private var automaticRefresh = true
    @State private var confirmQuit = false
    private var lastSync: Date? { connections.allSatisfy { $0.lastSyncAt != nil } ? connections.compactMap(\.lastSyncAt).min() : nil }
    private var needsAttention: Bool { coordinator.errorMessage != nil || connections.contains { $0.errorMessage != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MoneyMap").font(.headline)
                    Text(coordinator.isWorking ? "Updating your banks…" : needsAttention ? "An update needs attention" : "Bank service is running")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if coordinator.isWorking { ProgressView().controlSize(.small) }
                else { Image(systemName: needsAttention ? "exclamationmark.circle.fill" : "checkmark.circle.fill").foregroundStyle(needsAttention ? .orange : .green) }
            }
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Connected banks", value: "\(connections.count)")
                if let lastSync { LabeledContent("Last bank update", value: lastSync.formatted(date: .abbreviated, time: .shortened)) }
                Text(automaticRefresh ? "Automatic updates and iPhone requests are active." : "Scheduled updates are off. iPhone requests are still handled.")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.callout).padding(12).macWorkspaceSurface(tint: .accentColor, radius: 12)
            if coordinator.pendingLinkSession != nil {
                Button("Finish Bank Sign-in…", systemImage: "arrow.forward.circle") { showWorkspace() }
            }
            if needsAttention {
                Button("Review Bank Status…", systemImage: "exclamationmark.triangle") { showWorkspace() }
            }
            Button { Task { await coordinator.syncAll(context: context) } } label: { Label("Refresh Banks", systemImage: "arrow.clockwise") }
                .disabled(coordinator.isWorking || connections.isEmpty)
            Button("Open MoneyMap", systemImage: "macwindow") { showWorkspace() }
            Button("Settings…", systemImage: "gearshape") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            if !lifecycle.isInMenuBar {
                Button("Move to Menu Bar", systemImage: "menubar.rectangle") { lifecycle.moveToMenuBar() }
            }
            Divider()
            Text("Updates continue while this Mac is awake and online.").font(.caption).foregroundStyle(.secondary)
            Button("Quit MoneyMap Completely…", systemImage: "power") { confirmQuit = true }
                .foregroundStyle(.secondary)
        }.buttonStyle(.plain).padding(20).frame(width: 340).macWorkspaceCanvas()
        .confirmationDialog("Stop bank updates?", isPresented: $confirmQuit) {
            Button("Quit MoneyMap Completely", role: .destructive) { lifecycle.quitCompletely() }
        } message: { Text("Bank sync and iPhone requests will stop until you open MoneyMap again.") }
    }
    private func showWorkspace() {
        lifecycle.showWorkspace()
        openWindow(id: "main")
    }
}

struct MacMenuBarIcon: View {
    private static let icon: NSImage = {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }()
    var body: some View { Image(nsImage: Self.icon).accessibilityLabel("MoneyMap bank sync") }
}
