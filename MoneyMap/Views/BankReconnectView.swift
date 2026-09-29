import SwiftUI

/// The phone carries only a short-lived hosted Link URL. Bank credentials stay in Plaid.
struct BankReconnectView: View {
    let itemID: String
    let bankName: String
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var command: PhoneBankReconnectCommand?
    @State private var isLoading = true
    @State private var isUpdating = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var importedCommandID: String?
    @State private var mutationVersion = 0

    private var isOtherBank: Bool { command.map { $0.itemID != itemID && !$0.isTerminal && !$0.hasExpired } ?? false }
    private var current: PhoneBankReconnectCommand? { command?.itemID == itemID ? command : nil }
    private var hostedURL: URL? {
        guard let current, current.state == .ready, !current.hasExpired,
              let url = current.sanitizedHostedURL, url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "secure.plaid.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(bankName, systemImage: "building.columns").font(.headline)
                    Text("Keep MoneyMap open on your Mac and connected to the internet. Your Mac prepares a secure bank sign-in that you can complete on this iPhone.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    if isLoading {
                        HStack { ProgressView(); Text("Checking for a reconnection…") }
                    } else if isOtherBank {
                        Label("Another bank is reconnecting", systemImage: "clock")
                        Text("Finish that reconnection first, or cancel it before reconnecting this bank.")
                            .foregroundStyle(.secondary)
                        Button("Cancel Other Reconnection", role: .destructive) { Task { await cancel() } }
                    } else {
                        stateContent
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Check Again") { Task { await reload() } }
                    }
                }
                if let current, !current.isTerminal, !current.hasExpired {
                    Section {
                        Button("Cancel Reconnection", role: .destructive) { Task { await cancel() } }
                    } footer: {
                        Text("Closing this sheet keeps your request available. You can return to this bank to continue.")
                    }
                }
            }
            .disabled(isUpdating || isRefreshing)
            .navigationTitle("Reconnect Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await reload()
                while !Task.isCancelled && scenePhase == .active {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    guard !Task.isCancelled else { return }
                    await reload()
                }
            }
        }
    }

    @ViewBuilder private var stateContent: some View {
        if isRefreshing {
            HStack { ProgressView(); Text("Updating your bank data…") }
        } else if let current, current.state == .succeeded {
            Label("Bank reconnected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(MoneyMapDesign.calmGreen)
            Text(current.message ?? "Bank Sync has checked for your Mac’s latest account data. Review its sync status for any remaining updates.")
                .foregroundStyle(.secondary)
            Text("Request started \(current.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            requestButton("Reconnect Again")
        } else if let current, current.hasExpired {
            Label("Reconnection expired", systemImage: "clock.badge.exclamationmark")
            Text("Prepare a new sign-in with MoneyMap open on your Mac.").foregroundStyle(.secondary)
            requestButton("Try Again")
        } else if let current, current.state == .requested {
            HStack { ProgressView(); Text("Waiting for your Mac…") }
            Text("Your request is saved in iCloud. Open MoneyMap on your Mac to prepare the bank sign-in.")
                .foregroundStyle(.secondary)
        } else if let current, current.state == .ready {
            if let hostedURL {
                Button {
                    openURL(hostedURL) { accepted in
                        if !accepted { errorMessage = "The bank sign-in could not be opened. Please try again." }
                    }
                } label: {
                    Label("Continue to Bank", systemImage: "safari")
                }
                Text("Complete sign-in in Safari, then return here. Keep MoneyMap open on your Mac while the bank connection finishes.")
                    .foregroundStyle(.secondary)
            } else {
                Label("Bank sign-in unavailable", systemImage: "exclamationmark.triangle")
                Text("Cancel this reconnection and try again to request a new secure sign-in.")
                    .foregroundStyle(.secondary)
            }
        } else if let current, current.state == .failed {
            Label("Reconnection needs attention", systemImage: "exclamationmark.triangle")
            Text(current.message ?? "Check MoneyMap on your Mac, then try again.").foregroundStyle(.secondary)
            requestButton("Try Again")
        } else {
            if current?.state == .canceled { Text("Reconnection canceled.").foregroundStyle(.secondary) }
            requestButton("Prepare Reconnection")
        }
    }

    private func requestButton(_ title: String) -> some View {
        Button { Task { await request() } } label: { Label(title, systemImage: "arrow.triangle.2.circlepath") }
    }

    private func request() async {
        guard !isUpdating else { return }
        isUpdating = true
        mutationVersion += 1
        errorMessage = nil
        defer { isUpdating = false }
        do {
            command = try await PhoneBankReconnectCommandStore.create(itemID: itemID)
        } catch {
            errorMessage = error.localizedDescription
            if let latest = try? await PhoneBankReconnectCommandStore.latest() { command = latest }
        }
    }

    private func cancel() async {
        guard !isUpdating, let command else { return }
        isUpdating = true
        mutationVersion += 1
        defer { isUpdating = false }
        do {
            let canceled = try await PhoneBankReconnectCommandStore.cancel(id: command.id)
            if !canceled { errorMessage = "The reconnection changed before it could be canceled. Its latest status is shown here." }
            else { errorMessage = nil }
            self.command = try await PhoneBankReconnectCommandStore.latest()
            await importIfCompleted()
        } catch { errorMessage = error.localizedDescription }
    }

    private func reload() async {
        guard !isUpdating, !isRefreshing else { return }
        let version = mutationVersion
        defer { isLoading = false }
        do {
            let latest = try await PhoneBankReconnectCommandStore.latest()
            guard !Task.isCancelled, version == mutationVersion else { return }
            command = latest
            errorMessage = nil
            await importIfCompleted()
        } catch {
            guard !Task.isCancelled, version == mutationVersion else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func importIfCompleted() async {
        guard let current, current.state == .succeeded, importedCommandID != current.id, !isRefreshing else { return }
        importedCommandID = current.id
        isRefreshing = true
        await onCompleted()
        isRefreshing = false
    }
}
