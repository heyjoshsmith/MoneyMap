import SwiftUI
import SwiftData
import AuthenticationServices

@MainActor final class WatchBankAuthentication: ObservableObject {
    @Published var error: String?
    private var session: ASWebAuthenticationSession?
    func start(_ url: URL) {
        guard url.scheme == "https", url.host == "secure.plaid.com" else { error = "Invalid bank sign-in address."; return }
        session = ASWebAuthenticationSession(url: url, callbackURLScheme: "moneymap-watch") { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.error = error.localizedDescription }
                self?.session = nil
            }
        }
        if session?.start() != true { error = "Bank sign-in could not open on this Watch." }
    }
    func cancel() { session?.cancel(); session = nil }
}

struct WatchBankConnectionsView: View {
    @StateObject private var authentication = WatchBankAuthentication()
    @AppStorage("watchBankRequestID") private var requestID = ""
    @State private var command: WatchBankCommand?
    @State private var error: String?
    @State private var connections: [PlaidConnection] = []
    @State private var confirmingDisconnect: String?
    var body: some View {
        List {
            Text("Your Mac securely connects banks and refreshes balances. Keep MoneyMap for Mac running and online.").font(.caption).foregroundStyle(.secondary)
            if WatchBankCompatibility.verifiedInstitutionIDs.isEmpty {
                Label("Watch bank sign-in is awaiting device verification.", systemImage: "info.circle").font(.caption)
            }
            Button("Connect a Bank") { request("link") }.disabled(WatchBankCompatibility.verifiedInstitutionIDs.isEmpty || busy)
            Button("Refresh Bank Data") { request("refresh") }.disabled(busy)
            ForEach(connections) { connection in
                Section(connection.institutionName ?? "Bank") {
                    Button("Reconnect") { request("reconnect", itemID: connection.itemID) }.disabled(busy || WatchBankCompatibility.verifiedInstitutionIDs.isEmpty)
                    Button("Remove Bank", role: .destructive) { confirmingDisconnect = connection.itemID }.disabled(busy)
                }
            }
            if let command {
                Section("Request") {
                    Text(command.message ?? (command.state == "requested" ? "Waiting for Mac" : command.state.capitalized)).font(.caption)
                    if let url = command.hostedURL, !command.isTerminal, command.expiresAt > .now {
                        Button("Sign In on Watch") { authentication.start(url) }
                    }
                    if !command.isTerminal { Button("Cancel", role: .cancel) { Task { await cancel() } } }
                }
            }
            if let error = error ?? authentication.error { Text(error).font(.caption).foregroundStyle(WatchDesign.coral) }
        }.navigationTitle("Banks")
            .confirmationDialog("Remove this bank from MoneyMap?", isPresented: Binding(get: { confirmingDisconnect != nil }, set: { if !$0 { confirmingDisconnect = nil } })) {
                Button("Remove Bank", role: .destructive) { if let id = confirmingDisconnect { request("disconnect", itemID: id) }; confirmingDisconnect = nil }
            }
            .task {
                await loadConnections()
                while !Task.isCancelled {
                    if !requestID.isEmpty {
                        do {
                            command = try await WatchBankCommandStore.fetch(requestID)
                            if var value = command, value.expiresAt < .now, !value.isTerminal {
                                value.state = "expired"; value.message = "Request expired. Try again with your Mac online."
                                try await WatchBankCommandStore.update(value); command = value
                            }
                            if command?.state == "succeeded" { await loadConnections() }
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                }
            }
    }
    private var busy: Bool { command.map { !$0.isTerminal && $0.expiresAt > .now } ?? false }
    private func request(_ action: String, itemID: String? = nil) {
        let value = WatchBankCommand(action: action, itemID: itemID)
        command = value
        Task {
            do { try await WatchBankCommandStore.create(value); requestID = value.id; error = nil }
            catch { command = nil; self.error = error.localizedDescription }
        }
    }
    private func cancel() async {
        guard var value = command else { return }
        authentication.cancel(); value.state = "canceled"; value.message = "Canceled"
        do { try await WatchBankCommandStore.update(value); command = value } catch { self.error = error.localizedDescription }
    }
    private func loadConnections() async {
        do {
            let context = ModelContext(try PlaidSyncContainerFactory.make())
            try await PlaidCloudSyncService.pull(context: context)
            connections = try context.fetch(FetchDescriptor<PlaidConnection>())
        } catch { self.error = error.localizedDescription }
    }
}
