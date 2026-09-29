import ServiceManagement
import SwiftData
import SwiftUI

private enum MacWorkspace: String, CaseIterable, Identifiable {
    case overview = "Overview", banks = "Banks", activity = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: "house"; case .banks: "building.columns"; case .activity: "clock.arrow.circlepath" }
    }
}

struct MacBankSyncDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlaidConnection.updatedAt, order: .reverse) private var connections: [PlaidConnection]
    @Query(sort: \PlaidAccountSnapshot.accountName) private var accounts: [PlaidAccountSnapshot]
    @Query(sort: \PlaidTransactionReviewItem.updatedAt, order: .reverse) private var transactions: [PlaidTransactionReviewItem]
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    @State private var destination: MacWorkspace? = .overview
    @State private var selectedBank: String?
    @State private var workflow = false
    @State private var reconnectID: String?
    @State private var upgradeAccess = false
    @State private var setup = false
    @AppStorage("plaid.credentialsSaved") private var hasService = false
    @State private var phoneGuide = false
    @State private var removal: PlaidConnection?

    private var bank: PlaidConnection? { connections.first { $0.itemID == selectedBank } }
    private var attentionCount: Int { connections.filter { $0.errorMessage != nil || $0.status == "needs_attention"  }.count }
    private var upgradeCount: Int { connections.filter { !needsReconnect($0) && needsConsent($0) }.count }
    private var lastSync: Date? { connections.allSatisfy { $0.lastSyncAt != nil } ? connections.compactMap(\.lastSyncAt).min() : nil }

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("MoneyMap") {
                    ForEach(MacWorkspace.allCases) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .buttonStyle(.plain).padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch destination ?? .overview {
                    case .overview: overview
                    case .banks: if let bank { bankDetail(bank) } else { banks }
                    case .activity: activity
                    }
                }
                .padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }
            .macWorkspaceCanvas()
            .navigationTitle(destination?.rawValue ?? "MoneyMap")
            .toolbar {
                ToolbarItemGroup {
                    if coordinator.isWorking { ProgressView().controlSize(.small).accessibilityLabel("Updating bank data") }
                    Button { Task { await coordinator.syncAll(context: context) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(coordinator.isWorking || connections.isEmpty).help("Refresh your banks and send updates to iPhone")
                    Button { beginConnection() } label: { Label("Add Bank", systemImage: "plus") }
                        .disabled(coordinator.isWorking)
                }
            }
        }
        .groupBoxStyle(MacWorkspaceGroupStyle())
        .frame(minWidth: 820, minHeight: 600)
        .onAppear { refreshServiceStatus() }
        .onChange(of: destination) { _, _ in selectedBank = nil }
        .sheet(isPresented: $phoneGuide) { MacPhoneUpdateFlow(coordinator: coordinator) }
        .sheet(isPresented: $workflow) {
            MacBankConnectionFlow(coordinator: coordinator, reconnectID: reconnectID, upgradeAccess: upgradeAccess)
        }
        .sheet(isPresented: $setup, onDismiss: { refreshServiceStatus() }) {
            MacServiceSetupFlow(coordinator: coordinator)
        }
        .confirmationDialog("Remove this bank?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { connection in
            Button("Remove from MoneyMap", role: .destructive) {
                Task { await coordinator.removeConnection(itemID: connection.itemID, context: context) }
                selectedBank = nil; removal = nil
            }
        } message: { connection in
            Text("Remove \(connection.institutionName ?? "this bank") and its synced accounts from MoneyMap? Your bank account stays open.")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading("Your banks, in order", subtitle: "This Mac keeps your bank data ready for MoneyMap on iPhone.")
            GroupBox {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: hasService ? (attentionCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill") : "building.columns")
                        .font(.system(size: 32)).foregroundStyle(attentionCount > 0 ? Color.orange : Color.accentColor)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(!hasService ? "Welcome to MoneyMap" : connections.isEmpty ? "Connect your first bank" : attentionCount > 0 ? "A little attention needed" : "You're connected")
                            .font(.title2.weight(.semibold))
                        Text(!hasService ? "A short setup gets this Mac ready to connect your accounts." : connections.isEmpty ? "Choose your bank and sign in securely in your browser." : attentionCount > 0 ? "\(attentionCount) bank\(attentionCount == 1 ? " has" : "s have") a connection update to review." : "\(connections.count) banks · \(accounts.count) accounts")
                            .foregroundStyle(.secondary)
                        if let lastSync { Text("All banks refreshed through \(lastSync.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        if !hasService || connections.isEmpty {
                            Button(!hasService ? "Get Started" : "Connect a Bank") { beginConnection() }.buttonStyle(.borderedProminent)
                        } else if attentionCount > 0 {
                            Button("Review Banks") { destination = .banks }.buttonStyle(.borderedProminent)
                        }
                    }
                    Spacer()
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(MacWorkspaceGroupStyle(tint: attentionCount > 0 ? .orange : .accentColor))
            if let pending = coordinator.pendingLinkSession {
                actionRow(pending.isDataUpgrade == true ? "Finish your data upgrade" : "Finish your bank sign-in", detail: "Continue where you left off in your browser.", symbol: "arrow.forward.circle") { workflow = true }
            }
            if upgradeCount > 0 {
                actionRow("Unlock more account details", detail: "\(upgradeCount) connected bank\(upgradeCount == 1 ? "" : "s") can request additional data access.", symbol: "sparkles") { destination = .banks }
            }
            if PlaidSyncContainerFactory.lastReport.mode == .inMemory {
                Label("MoneyMap couldn't open its saved data. Changes won't be kept after quitting. Open Settings → Troubleshooting for details.", systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
            }
            if coordinator.errorMessage != nil {
                DisclosureGroup {
                    Text(coordinator.errorMessage ?? "").textSelection(.enabled).foregroundStyle(.secondary).padding(.top, 8)
                } label: { Label("The last update needs attention", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            actionRow("Your banks", detail: "Accounts, balances, and connection health", symbol: "building.columns") { destination = .banks }
            actionRow("Latest activity", detail: "See what has arrived from your banks", symbol: "clock.arrow.circlepath") { destination = .activity }
            actionRow("Update your iPhone", detail: "A short guide to bringing your bank data up to date", symbol: "iphone") { phoneGuide = true }
            GroupBox {
                Label("MoneyMap can keep updating your banks from the menu bar, even with this window closed.", systemImage: "iphone.and.arrow.forward")
                    .foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var banks: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeading("Your banks", subtitle: "Open a bank to see its accounts or manage its connection.")
            if connections.isEmpty {
                ContentUnavailableView { Label("No banks yet", systemImage: "building.columns") } description: { Text("Connect an account to get started.") } actions: { Button("Connect a Bank") { beginConnection() } }
            }
            ForEach(connections) { connection in
                actionRow(connection.institutionName ?? "Bank", detail: "\(accounts.filter { $0.itemID == connection.itemID }.count) accounts · \(needsReconnect(connection) ? "Reconnect needed" : needsConsent(connection) ? "Data access upgrade available" : connection.errorMessage != nil ? "Update delayed" : "Connected")", symbol: "building.columns") { selectedBank = connection.itemID }
            }
        }
    }

    private func bankDetail(_ connection: PlaidConnection) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { selectedBank = nil } label: { Label("All Banks", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            pageHeading(connection.institutionName ?? "Bank", subtitle: connection.lastSyncAt.map { "Updated \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Waiting for its first update")
            if needsReconnect(connection) {
                GroupBox {
                    HStack(spacing: 16) {
                        Label("Bank access needs to be restored", systemImage: "exclamationmark.lock").foregroundStyle(.orange)
                        Spacer()
                        Button("Reconnect Bank") { reconnectID = connection.itemID; upgradeAccess = false; workflow = true }
                            .buttonStyle(.borderedProminent).disabled(coordinator.isWorking)
                    }.padding(12)
                }.groupBoxStyle(MacWorkspaceGroupStyle(tint: .orange))
            } else if needsConsent(connection) {
                GroupBox {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Get more from your accounts").font(.headline)
                            Text("Your bank is connected. Approve additional access to request payment details or other supported data.").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Upgrade Data Access") { reconnectID = connection.itemID; upgradeAccess = true; workflow = true }
                            .buttonStyle(.borderedProminent).disabled(coordinator.isWorking)
                    }.padding(12)
                }.groupBoxStyle(MacWorkspaceGroupStyle(tint: .purple))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), alignment: .top)], alignment: .leading, spacing: 20) {
                ForEach(accounts.filter { $0.itemID == connection.itemID }) { account in
                    MacAccountDetailsCard(account: account, connection: connection,
                        transactions: transactions.filter { $0.plaidAccountID == account.accountID && $0.bankRemovedAt == nil },
                        canUpgrade: !coordinator.isWorking && !needsReconnect(connection)) {
                            reconnectID = connection.itemID; upgradeAccess = true; workflow = true
                        }
                }
            }
            Text("Capabilities are based on data returned for each account. A successful bank connection does not guarantee every field is supplied.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = connection.errorMessage {
                DisclosureGroup("Connection details") { Text(error).textSelection(.enabled).padding(.top, 8) }.foregroundStyle(.secondary)
            }
            Button("Remove Bank…", role: .destructive) { removal = connection }.disabled(coordinator.isWorking)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeading("Latest activity", subtitle: "Recent bank transactions. Review and organize them in MoneyMap on iPhone.")
            if let status = coordinator.statusMessage {
                DisclosureGroup("Latest update") { Text(status).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 8) }
            }
            if transactions.isEmpty { ContentUnavailableView("No activity yet", systemImage: "clock") }
            else {
                GroupBox {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(transactions.prefix(50))) { item in MacPlaidTransactionRow(reviewItem: item); Divider() }
                    }.padding(12)
                }
                Text("Showing the 50 most recently updated transactions.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func beginConnection() {
        refreshServiceStatus()
        if hasService { reconnectID = nil; upgradeAccess = false; workflow = true } else { setup = true }
    }
    private func refreshServiceStatus() { hasService = PlaidCredentialStore().hasStoredCredentialsHint || !connections.isEmpty }
    private func needsReconnect(_ connection: PlaidConnection) -> Bool {
        MacBankAccessPresentation.needsReconnect(status: connection.status, error: connection.errorMessage, enrichmentJSON: connection.enrichmentJSON)
    }
    private func needsConsent(_ connection: PlaidConnection) -> Bool {
        accounts.filter { $0.itemID == connection.itemID }.contains { account in
            MacAccountCapability.make(type: account.type, balance: account.currentBalance, accountJSON: account.enrichmentJSON,
                connectionJSON: connection.enrichmentJSON, transactionCount: 0).contains { $0.availability == .upgrade }
        }
    }
}

private func pageHeading(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.largeTitle.weight(.semibold))
        Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private func actionRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary) }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .macWorkspaceSurface(radius: 14)
            .contentShape(Rectangle())
    }.buttonStyle(.plain)
}

private struct MacBankConnectionFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    let reconnectID: String?
    var upgradeAccess = false
    @State private var finishedUpgrade = false
    private var isUpgrade: Bool { finishedUpgrade || (coordinator.pendingLinkSession?.isDataUpgrade ?? upgradeAccess) }
    @State private var product = "transactions"
    @State private var completed = false
    @State private var performedAction = false
    @State private var cancelConfirmation = false
    private var pending: Bool { coordinator.pendingLinkSession != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
            Text(completed ? (isUpgrade ? "Data access updated" : "Connection updated") : pending ? (isUpgrade ? "Approve additional access" : "Finish in your browser") : reconnectID == nil ? "Connect a bank" : isUpgrade ? "Upgrade data access" : "Reconnect your bank")
                .font(.title.weight(.semibold))
            Text(completed ? "Step 3 of 3 · Ready" : pending ? "Step 2 of 3 · Bank sign-in" : "Step 1 of 3 · Prepare")
                .font(.subheadline).foregroundStyle(.secondary)
            if completed {
                Label("Your available bank data has been refreshed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(coordinator.statusMessage ?? "Your updated data is ready for iPhone.").foregroundStyle(.secondary)
            } else if pending {
                Text(isUpgrade ? "Approve the additional data you want to share in your browser, then return here. Your existing bank connection stays in place." : "Sign in and approve access in your browser. Return here when you finish so MoneyMap can retrieve your accounts.")
                Button("Open Bank Sign-in Again") { coordinator.openPendingLinkSession() }.disabled(coordinator.isWorking)
                Text("You can close this guide and resume it from Overview.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(reconnectID == nil ? "Choose the kind of account you want to add. You'll sign in securely with Plaid in your browser." : isUpgrade ? "Your bank is already connected. This upgrade requests supported payment, loan, or investment details. Some banks may still leave individual fields unavailable." : "Your bank sign-in is no longer working. Sign in again to restore access to your accounts.")
                if reconnectID == nil {
                    Picker("Account type", selection: $product) {
                        Text("Everyday banking & cards").tag("transactions")
                        Text("Investments").tag("investments")
                        Text("Loans").tag("liabilities")
                    }.pickerStyle(.radioGroup)
                }
            }
            if performedAction, let error = coordinator.errorMessage {
                Label("We couldn't finish this step. You can try again.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                DisclosureGroup("Details") { Text(error).font(.caption).textSelection(.enabled) }
            } else if performedAction, pending, let message = coordinator.statusMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button(completed ? "Close" : "Later") { dismiss() }.keyboardShortcut(.cancelAction)
                if pending { Button("Cancel Connection…", role: .destructive) { cancelConfirmation = true }.disabled(coordinator.isWorking) }
                Spacer()
                if coordinator.isWorking { ProgressView().controlSize(.small) }
                Button(completed ? "Done" : pending ? "I've Finished Signing In" : "Continue to Bank") {
                    if completed { dismiss(); return }
                    Task {
                        performedAction = true
                        if pending {
                            finishedUpgrade = isUpgrade
                            await coordinator.finishHostedLinkConnection(context: context)
                            completed = coordinator.pendingLinkSession == nil && coordinator.errorMessage == nil
                        } else if let reconnectID { await coordinator.startReconnect(itemID: reconnectID, upgradeDataAccess: isUpgrade) }
                        else { await coordinator.startHostedLinkConnection(primaryProduct: product) }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(coordinator.isWorking)
            }
        }.padding(28).frame(width: 520, height: 440).background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("Cancel this bank connection?", isPresented: $cancelConfirmation) {
            Button("Cancel Connection", role: .destructive) { coordinator.cancelPendingLinkSession(); dismiss() }
        }
    }
}

struct MacBankSyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    @AppStorage(MacBankSyncPreferences.automaticRefreshEnabledKey) private var automaticRefresh = true
    @AppStorage(MacBankSyncPreferences.refreshIntervalMinutesKey) private var interval = 60
    @AppStorage(MacPlaidAPIClient.linkCustomizationNameKey) private var customization = ""
    @AppStorage(MacBackgroundLifecycle.keepRunningKey) private var keepRunning = true
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var setup = false
    @State private var serviceReady = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep bank data up to date", isOn: $automaticRefresh)
                Toggle("Keep syncing when I close MoneyMap", isOn: $keepRunning)
                Toggle("Open MoneyMap at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard enabled != LaunchAtLoginController.isEnabled else { return }
                        do { try LaunchAtLoginController.setEnabled(enabled); launchError = nil }
                        catch { launchError = error.localizedDescription; launchAtLogin = LaunchAtLoginController.isEnabled }
                    }
                if let launchError { Text(launchError).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Everyday essentials") } footer: { Text("When background sync is on, closing the window or pressing ⌘Q keeps MoneyMap in the menu bar. Use Quit MoneyMap Completely to stop it.") }
            Section("Bank connection service") {
                LabeledContent("Plaid", value: serviceReady ? "Set up" : "Setup needed")
                Button(serviceReady ? "Manage Connection Setup…" : "Set Up Bank Connections…") { setup = true }
                    .disabled(coordinator.isWorking || coordinator.pendingLinkSession != nil)
            }
            Section {
                DisclosureGroup("Refresh schedule") {
                    Picker("Check for updates", selection: $interval) {
                        Text("Every 30 minutes").tag(30); Text("Every hour").tag(60)
                        Text("Every 3 hours").tag(180); Text("Every 6 hours").tag(360)
                    }.disabled(!automaticRefresh)
                    Text("Bank availability can affect when new data arrives.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Advanced connection options") {
                    Text("Only change these if your Plaid setup requires it.").foregroundStyle(.secondary)
                    TextField("Link customization", text: $customization, prompt: Text("Use Plaid default"))
                        .disabled(coordinator.isWorking || coordinator.pendingLinkSession != nil)
                    Link("Open Plaid Dashboard", destination: URL(string: "https://dashboard.plaid.com/")!)
                    Text("Open a bank and choose Upgrade Data Access to approve additional information.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Troubleshooting") {
                    LabeledContent("Connection environment", value: PlaidCredentialStore().selectedEnvironment.displayName)
                    let report = PlaidSyncContainerFactory.lastReport
                    LabeledContent("Storage", value: report.mode.displayName)
                    if let reason = report.fallbackReason { Text(reason).font(.caption).textSelection(.enabled) }
                    if let url = report.storeURL { Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let error = coordinator.errorMessage { Text(error).font(.caption).textSelection(.enabled) }
                    if PlaidCredentialStore().selectedEnvironment == .sandbox {
                        Button("Add a Test Bank") { Task { await coordinator.createSandboxConnection(context: context) } }
                            .disabled(coordinator.isWorking || coordinator.pendingLinkSession != nil)
                    }
                }
            } header: { Text("More options") }
        }.formStyle(.grouped).frame(width: 560, height: 540)
        .onAppear { launchAtLogin = LaunchAtLoginController.isEnabled; refreshStatus() }
        .sheet(isPresented: $setup, onDismiss: { refreshStatus() }) { MacServiceSetupFlow(coordinator: coordinator) }
    }
    private func refreshStatus() { serviceReady = PlaidCredentialStore().hasStoredCredentialsHint }
}

private struct MacServiceSetupFlow: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    @State private var editor = PlaidCredentialEditorState()
    @State private var step = 0
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
            Text(step == 2 ? "Your Mac is ready" : "Set up bank connections").font(.title.weight(.semibold))
            Text("Step \(step + 1) of 3").font(.subheadline).foregroundStyle(.secondary)
            if step == 0 {
                Text("MoneyMap uses Plaid to connect to your banks. This one-time setup saves the connection keys securely in your Mac's Keychain.")
                Text("Have a Plaid account ready, then continue to enter its connection keys.").foregroundStyle(.secondary)
                Link("Open Plaid", destination: URL(string: "https://dashboard.plaid.com/")!)
            } else if step == 1 {
                Text("Copy the keys from your Plaid account. These are service keys, not your bank password.").foregroundStyle(.secondary)
                Picker("Accounts", selection: $editor.environment) {
                    Text("Real accounts").tag(PlaidCredentialEnvironment.production)
                    Text("Test accounts").tag(PlaidCredentialEnvironment.sandbox)
                }.onChange(of: editor.environment) { old, new in editor.selectEnvironment(new, previousEnvironment: old) }
                TextField("Client ID", text: $editor.clientID).textFieldStyle(.roundedBorder)
                SecureField(editor.environment == .production ? "Production secret" : "Sandbox secret", text: $editor.secret).textFieldStyle(.roundedBorder)
                HStack {
                    Link("Find My Keys", destination: URL(string: "https://dashboard.plaid.com/team/keys")!)
                    Spacer()
                    Button("Load Saved Keys") { do { try editor.loadValuesForEditing() } catch { errorMessage = error.localizedDescription } }
                }
            } else {
                Label("Connection service verified", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Use Add Bank in the main window to choose a bank and sign in. You can manage these settings whenever you need to.").foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label("Setup needs attention", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                DisclosureGroup("Details") { Text(errorMessage).font(.caption).textSelection(.enabled) }
            }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                if step == 1 { Button("Back") { step = 0; errorMessage = nil }.disabled(working) }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(step == 2 ? "Done" : step == 1 ? "Save & Verify" : "Continue") {
                    if step == 2 { dismiss() }
                    else if step == 0 { step = 1 }
                    else {
                        working = true; errorMessage = nil
                        Task {
                            do {
                                // Verify before replacing the saved keys or selected environment.
                                let credentials = PlaidStoredCredentials(clientID: editor.clientID.trimmingCharacters(in: .whitespacesAndNewlines), secret: editor.secret.trimmingCharacters(in: .whitespacesAndNewlines), environment: editor.environment)
                                try await MacPlaidAPIClient(credentials: credentials).validateCredentials()
                                try editor.save(); step = 2
                            } catch { errorMessage = error.localizedDescription }
                            working = false
                        }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(working || coordinator.isWorking || (step == 1 && !editor.canSave))
            }
        }.padding(28).frame(width: 500, height: 430).background(Color(nsColor: .windowBackgroundColor))
        .onAppear { editor.loadStatus(hasConnections: false) }
        .interactiveDismissDisabled(working)
    }
}
private struct MacPlaidTransactionRow: View {
    let reviewItem: PlaidTransactionReviewItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(reviewItem.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(reviewItem.amount.formatted(.currency(code: reviewItem.currencyCode ?? "USD")))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(reviewItem.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch reviewItem.status {
        case .ready: return "tray.full"
        case .imported: return "checkmark.circle"
        case .skipped: return "forward.end"
        }
    }

    private var statusColor: Color {
        switch reviewItem.status {
        case .ready: return .accentColor
        case .imported: return .green
        case .skipped: return .secondary
        }
    }

    private var detailText: String {
        var parts: [String] = []
        if let date = reviewItem.date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let category = reviewItem.category, !category.isEmpty {
            parts.append(category)
        }
        if reviewItem.pending {
            parts.append("Pending")
        }
        return parts.joined(separator: " - ")
    }
}

private struct PlaidCredentialEditorState {
    var clientID = ""
    var secret = ""
    var environment = PlaidCredentialEnvironment.sandbox
    var hasStoredCredentials = false
    private var savedSecretEnvironments: Set<PlaidCredentialEnvironment> = []
    private var secretsByEnvironment: [PlaidCredentialEnvironment: String] = [:]

    var canSave: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func hasSavedSecret(for environment: PlaidCredentialEnvironment) -> Bool {
        if savedSecretEnvironments.contains(environment) {
            return true
        }

        return !(secretsByEnvironment[environment] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    mutating func loadStatus(hasConnections: Bool) {
        let store = PlaidCredentialStore()
        environment = store.selectedEnvironment
        clientID = ""
        secret = ""
        secretsByEnvironment = [:]
        savedSecretEnvironments = store.savedSecretEnvironments
        hasStoredCredentials = store.hasStoredCredentialsHint || hasConnections
    }

    mutating func loadValuesForEditing() throws {
        let store = PlaidCredentialStore()
        environment = store.selectedEnvironment
        clientID = (try? store.loadClientID()) ?? ""
        secretsByEnvironment[environment] = (try? store.secret(for: environment)) ?? ""
        secret = secretsByEnvironment[environment] ?? ""
        if canSave {
            store.markCredentialsSaved(for: environment)
            savedSecretEnvironments.insert(environment)
        }
        hasStoredCredentials = canSave
    }

    mutating func selectEnvironment(
        _ newEnvironment: PlaidCredentialEnvironment,
        previousEnvironment: PlaidCredentialEnvironment
    ) {
        secretsByEnvironment[previousEnvironment] = secret
        environment = newEnvironment
        secret = secretsByEnvironment[newEnvironment] ?? ""
        hasStoredCredentials = canSave
    }

    mutating func save() throws {
        let store = PlaidCredentialStore()
        try store.save(clientID: clientID, secret: secret, environment: environment)
        secretsByEnvironment[environment] = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        savedSecretEnvironments.insert(environment)
        hasStoredCredentials = canSave
    }
}

enum LaunchAtLoginController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum MacBankSyncPreferences {
    static let automaticRefreshEnabledKey = "plaid.automaticRefreshEnabled"
    static let refreshIntervalMinutesKey = "plaid.refreshIntervalMinutes"
}

private struct MacPhoneUpdateFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject var coordinator: MacPlaidSyncCoordinator
    @State private var refreshed = false
    @State private var attempted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Update your iPhone").font(.title.weight(.semibold))
            Text(refreshed ? "Step 2 of 2 · On your iPhone" : "Step 1 of 2 · Refresh your banks").foregroundStyle(.secondary)
            if refreshed {
                Label("Bank refresh finished", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Open MoneyMap on your iPhone. Go to Wallet → Bank Sync, then refresh to receive your Mac's latest update.")
                Text("Both devices need an internet connection and the same iCloud account.").foregroundStyle(.secondary)
            } else {
                Text("First, this Mac will check your banks for updates and send the available data to iCloud.")
                Text("Keep MoneyMap open until the refresh finishes.").foregroundStyle(.secondary)
                if attempted, let error = coordinator.errorMessage {
                    DisclosureGroup("The update needs attention") { Text(error).font(.caption).textSelection(.enabled) }
                }
            }
            Spacer()
            Divider()
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if coordinator.isWorking { ProgressView().controlSize(.small) }
                Button(refreshed ? "Done" : attempted ? "Try Again" : "Refresh Banks") {
                    if refreshed { dismiss() }
                    else { Task { attempted = true; await coordinator.syncAll(context: context); refreshed = coordinator.errorMessage == nil } }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(coordinator.isWorking)
            }
        }.padding(28).frame(width: 500, height: 360).background(Color(nsColor: .windowBackgroundColor))
    }
}
