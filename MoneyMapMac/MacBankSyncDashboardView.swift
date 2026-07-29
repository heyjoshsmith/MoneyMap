//
//  MacBankSyncDashboardView.swift
//  MoneyMapMac
//
//  Created by Codex on 7/6/26.
//

import ServiceManagement
import SwiftData
import SwiftUI

struct MacBankSyncDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaidConnection.updatedAt, order: .reverse) private var connections: [PlaidConnection]
    @Query(sort: \PlaidAccountSnapshot.accountName) private var accounts: [PlaidAccountSnapshot]
    @Query(sort: \PlaidTransactionReviewItem.updatedAt, order: .reverse) private var reviewItems: [PlaidTransactionReviewItem]
    @Query(sort: \PlaidSuggestion.updatedAt, order: .reverse) private var suggestions: [PlaidSuggestion]

    @StateObject private var coordinator = MacPlaidSyncCoordinator()
    @State private var credentialEditor = PlaidCredentialEditorState()
    @State private var launchAtLogin = false
    @State private var launchAtLoginMessage: String?
    @State private var credentialStatusMessage: String?
    @State private var credentialErrorMessage: String?
    @State private var showingCredentialSettings = false
    @State private var showingAdvancedDetails = false
    @State private var connectionPendingRemoval: PlaidConnection?
    @AppStorage(MacBankSyncPreferences.automaticRefreshEnabledKey) private var automaticRefreshEnabled = true
    @AppStorage(MacBankSyncPreferences.refreshIntervalMinutesKey) private var refreshIntervalMinutes = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusOverviewCard
                nextActionCard
                credentialsDisclosureCard
                connectionsCard
                phoneSyncCard
                advancedDetailsCard
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .frame(minWidth: 780, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            credentialEditor.loadStatus(hasConnections: !connections.isEmpty)
            launchAtLogin = LaunchAtLoginController.isEnabled
            showingCredentialSettings = !credentialEditor.hasStoredCredentials
        }
        .task(id: automaticRefreshConfigurationID) {
            await coordinator.runAutomaticRefreshLoop(
                context: modelContext,
                automaticRefreshEnabled: automaticRefreshEnabled,
                refreshIntervalMinutes: refreshIntervalMinutes
            )
        }
        .confirmationDialog(
            removeConnectionTitle,
            isPresented: removeConnectionConfirmationBinding,
            titleVisibility: .visible,
            presenting: connectionPendingRemoval
        ) { connection in
            Button("Remove from MoneyMap", role: .destructive) {
                Task { await coordinator.removeConnection(itemID: connection.itemID, context: modelContext) }
                connectionPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                connectionPendingRemoval = nil
            }
        } message: { connection in
            Text("This removes \(connection.institutionName ?? "this bank") from MoneyMap on this Mac and from the iPhone sync snapshot. It does not close your bank account.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MoneyMap for Mac")
                .font(.largeTitle.weight(.semibold))
            Text("Connect banks here, keep credentials on this Mac, and send safe snapshots to your iPhone.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusOverviewCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: primaryStatus.systemImage)
                    .font(.title2)
                    .foregroundStyle(primaryStatus.color)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text(primaryStatus.title)
                        .font(.headline)
                    Text(primaryStatus.detail)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                HStack(spacing: 20) {
                    MetricTile(title: "Banks", value: "\(connections.count)", symbol: "building.columns")
                    MetricTile(title: "Accounts", value: "\(accounts.count)", symbol: "creditcard")
                    MetricTile(title: "Ready", value: "\(readyReviewItems.count + readySuggestions.count)", symbol: "tray.full")
                }
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var nextActionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: nextActionSystemImage)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(nextActionTitle)
                            .font(.headline)
                        Text(nextActionDetail)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if coordinator.isWorking {
                        ProgressView()
                    }
                }

                if let statusMessage = coordinator.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = coordinator.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack {
                    nextActionButtons
                    Spacer()
                }
            }
            .padding(4)
        } label: {
            Label("Next Step", systemImage: "arrow.forward.circle")
        }
    }

    @ViewBuilder
    private var nextActionButtons: some View {
        if !credentialEditor.hasStoredCredentials {
            Button {
                showingCredentialSettings = true
            } label: {
                Label("Add Credentials", systemImage: "key")
            }
            .buttonStyle(.borderedProminent)

            Button {
                openPlaidSignup()
            } label: {
                Label("Create Plaid Account", systemImage: "person.crop.circle.badge.plus")
            }
        } else if coordinator.pendingLinkSession != nil {
            Button {
                Task { await coordinator.finishHostedLinkConnection(context: modelContext) }
            } label: {
                Label("Finish Bank Connection", systemImage: "checkmark.circle")
            }
            .disabled(coordinator.isWorking)
            .buttonStyle(.borderedProminent)

            Button {
                coordinator.openPendingLinkSession()
            } label: {
                Label("Open Link Again", systemImage: "safari")
            }
            .disabled(coordinator.isWorking)

            Button {
                coordinator.cancelPendingLinkSession()
            } label: {
                Label("Start Over", systemImage: "xmark.circle")
            }
            .disabled(coordinator.isWorking)
        } else if connections.isEmpty {
            Button {
                Task { await coordinator.startHostedLinkConnection() }
            } label: {
                Label("Connect Bank", systemImage: "link.badge.plus")
            }
            .disabled(coordinator.isWorking)
            .buttonStyle(.borderedProminent)

            if credentialEditor.environment == .sandbox {
                Button {
                    Task { await coordinator.createSandboxConnection(context: modelContext) }
                } label: {
                    Label("Create Sandbox Test Bank", systemImage: "testtube.2")
                }
                .disabled(coordinator.isWorking)
            }
        } else {
            Button {
                Task { await coordinator.syncAll(context: modelContext) }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(coordinator.isWorking)
            .buttonStyle(.borderedProminent)

            Button {
                Task { await coordinator.startHostedLinkConnection() }
            } label: {
                Label("Add Another Bank", systemImage: "link.badge.plus")
            }
            .disabled(coordinator.isWorking)
        }
    }

    private var credentialsDisclosureCard: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showingCredentialSettings) {
                VStack(alignment: .leading, spacing: 18) {
                    setupGuideContent
                    Divider()
                    credentialFieldsContent
                    Divider()
                    launchAtLoginContent
                    Divider()
                    automaticRefreshContent
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Label(
                        credentialEditor.hasStoredCredentials ? "Plaid credentials saved" : "Plaid credentials needed",
                        systemImage: credentialEditor.hasStoredCredentials ? "checkmark.seal" : "key"
                    )
                    Spacer()
                    Text(credentialEditor.environment.displayName)
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }
            .padding(4)
        } label: {
            Label("Setup", systemImage: "gearshape")
        }
    }

    private var setupGuideContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("First-time setup")
                .font(.headline)

            GuidedPlaidStep(
                number: 1,
                title: "Create a Plaid developer account",
                detail: "Sandbox is for fake test banks. Production is what you use for your real accounts."
            )
            GuidedPlaidStep(
                number: 2,
                title: "Copy your API keys",
                detail: "Plaid shows one Client ID, plus separate Sandbox and Production secrets."
            )
            GuidedPlaidStep(
                number: 3,
                title: "Save the matching secret here",
                detail: "MoneyMap keeps credentials in this Mac's Keychain and lets you switch environments without pasting again."
            )

            HStack {
                Button {
                    openPlaidSignup()
                } label: {
                    Label("Create Plaid Account", systemImage: "person.crop.circle.badge.plus")
                }

                Button {
                    openPlaidAPIKeys()
                } label: {
                    Label("Open API Keys", systemImage: "key.viewfinder")
                }
            }
        }
    }

    private var credentialFieldsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Environment", selection: $credentialEditor.environment) {
                ForEach(PlaidCredentialEnvironment.allCases) { environment in
                    Text(environment.displayName).tag(environment)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: credentialEditor.environment) { oldValue, newValue in
                credentialEditor.selectEnvironment(newValue, previousEnvironment: oldValue)
                credentialStatusMessage = nil
                credentialErrorMessage = nil
            }

            TextField("Plaid Client ID", text: $credentialEditor.clientID)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)

            SecureField("\(credentialEditor.environment.displayName) Secret", text: $credentialEditor.secret)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)

            HStack(spacing: 12) {
                ForEach(PlaidCredentialEnvironment.allCases) { environment in
                    PlaidCredentialSlotStatus(
                        environment: environment,
                        isSaved: credentialEditor.hasSavedSecret(for: environment)
                    )
                }
            }

            if let credentialStatusMessage {
                Label(credentialStatusMessage, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }

            if let credentialErrorMessage {
                Label(credentialErrorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                if credentialEditor.hasStoredCredentials {
                    Button {
                        loadCredentialValues()
                    } label: {
                        Label("Load Saved", systemImage: "key.viewfinder")
                    }
                    .disabled(coordinator.isWorking)
                }

                Button {
                    saveCredentials()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .disabled(!credentialEditor.canSave || coordinator.isWorking)

                Button {
                    if saveCredentials() {
                        Task { await coordinator.validateCredentials() }
                    }
                } label: {
                    Label("Save and Test", systemImage: "network")
                }
                .disabled(!credentialEditor.canSave || coordinator.isWorking)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var launchAtLoginContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open MoneyMap for Mac at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                }

            Text("Leave this on if you want bank data to keep refreshing from this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let launchAtLoginMessage {
                Label(launchAtLoginMessage, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var automaticRefreshContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Refresh bank data automatically", isOn: $automaticRefreshEnabled)

            Picker("Refresh every", selection: $refreshIntervalMinutes) {
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("3 hours").tag(180)
                Text("6 hours").tag(360)
            }
            .pickerStyle(.segmented)
            .disabled(!automaticRefreshEnabled)

            Label("iPhone refresh requests are checked while this app is open.", systemImage: "iphone.gen3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var storageStatusCard: some View {
        let report = PlaidSyncContainerFactory.lastReport

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(report.mode.displayName, systemImage: report.mode == .cloudKit ? "icloud" : "externaldrive.badge.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(report.mode == .cloudKit ? Color.primary : Color.orange)

                if let storeURL = report.storeURL {
                    Text(storeURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let fallbackReason = report.fallbackReason {
                    Text(fallbackReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Storage", systemImage: "externaldrive.connected.to.line.below")
        }
    }

    private var credentialsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Environment", selection: $credentialEditor.environment) {
                    ForEach(PlaidCredentialEnvironment.allCases) { environment in
                        Text(environment.displayName).tag(environment)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: credentialEditor.environment) { oldValue, newValue in
                    credentialEditor.selectEnvironment(newValue, previousEnvironment: oldValue)
                    credentialStatusMessage = nil
                    credentialErrorMessage = nil
                }

                TextField("Plaid Client ID", text: $credentialEditor.clientID)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)

                SecureField("\(credentialEditor.environment.displayName) Secret", text: $credentialEditor.secret)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                HStack(spacing: 12) {
                    ForEach(PlaidCredentialEnvironment.allCases) { environment in
                        PlaidCredentialSlotStatus(
                            environment: environment,
                            isSaved: credentialEditor.hasSavedSecret(for: environment)
                        )
                    }
                }

                Text("MoneyMap stores one shared Client ID and separate Sandbox and Production secrets in Keychain. Switching environments reloads that environment's saved secret.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let credentialStatusMessage {
                    Label(credentialStatusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                if let credentialErrorMessage {
                    Label(credentialErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack {
                    Button {
                        openPlaidDashboard()
                    } label: {
                        Label("Open Plaid Dashboard", systemImage: "safari")
                    }

                    Spacer()

                    Button {
                        saveCredentials()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .disabled(!credentialEditor.canSave || coordinator.isWorking)

                    Button {
                        if saveCredentials() {
                            Task { await coordinator.validateCredentials() }
                        }
                    } label: {
                        Label("Save and Test", systemImage: "network")
                    }
                    .disabled(!credentialEditor.canSave || coordinator.isWorking)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(4)
        } label: {
            Label("Plaid Credentials", systemImage: "key")
        }
    }

    private var setupGuideCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: credentialEditor.hasStoredCredentials ? "checkmark.seal.fill" : "person.badge.key")
                        .font(.title2)
                        .foregroundStyle(credentialEditor.hasStoredCredentials ? .green : .accentColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(credentialEditor.hasStoredCredentials ? "Plaid setup is saved" : "Get your Plaid credentials")
                            .font(.headline)
                        Text("Plaid gives you a Client ID and an environment secret after you create a developer account. MoneyMap stores them only in this Mac's Keychain.")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    GuidedPlaidStep(
                        number: 1,
                        title: "Create a Plaid developer account",
                        detail: "Use Plaid's signup page. Sandbox is for fake test banks; Production is where Plaid now lets you test with real accounts."
                    )
                    GuidedPlaidStep(
                        number: 2,
                        title: "Open Team Settings, then API",
                        detail: "Copy the Client ID and the secret for the environment you want to use."
                    )
                    GuidedPlaidStep(
                        number: 3,
                        title: "Paste and test in MoneyMap",
                        detail: "Choose Sandbox for fake banks or Production for your real accounts, paste the matching secret, then choose Save and Test."
                    )
                    GuidedPlaidStep(
                        number: 4,
                        title: "Connect a bank with Plaid Link",
                        detail: credentialEditor.hasStoredCredentials ? "Your credentials are saved. Use Start Bank Connection below." : "This unlocks after your credentials are saved."
                    )
                }

                HStack {
                    Button {
                        openPlaidSignup()
                    } label: {
                        Label("Create Plaid Account", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        openPlaidAPIKeys()
                    } label: {
                        Label("Open API Keys", systemImage: "key.viewfinder")
                    }

                    Spacer()

                    Text("No terminal required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        } label: {
            Label("First-Time Setup", systemImage: "sparkles")
        }
    }

    private var bankConnectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect with Plaid Link")
                            .font(.headline)
                        Text("MoneyMap opens Plaid in your browser. After bank login and consent, return here to finish the connection and sync the first snapshot.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if coordinator.isWorking {
                        ProgressView()
                    }
                }

                if let pendingLinkSession = coordinator.pendingLinkSession {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(pendingLinkSession.mode == .addItem ? "Bank connection in progress" : "Reconnect in progress", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                        if let expiration = pendingLinkSession.expiration {
                            Text("Expires \(expiration.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        if let requestID = pendingLinkSession.requestID {
                            Text("Plaid request \(requestID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Button {
                        Task { await coordinator.startHostedLinkConnection() }
                    } label: {
                        Label(credentialEditor.hasStoredCredentials ? "Start Bank Connection" : "Save \(credentialEditor.environment.displayName) Credentials First", systemImage: "link.badge.plus")
                    }
                    .disabled(!credentialEditor.hasStoredCredentials || coordinator.isWorking)
                    .buttonStyle(.borderedProminent)

                    if coordinator.pendingLinkSession != nil {
                        Button {
                            coordinator.openPendingLinkSession()
                        } label: {
                            Label("Open Link Again", systemImage: "safari")
                        }
                        .disabled(coordinator.isWorking)

                        Button {
                            Task { await coordinator.finishHostedLinkConnection(context: modelContext) }
                        } label: {
                            Label("Finish Bank Connection", systemImage: "checkmark.circle")
                        }
                        .disabled(!credentialEditor.hasStoredCredentials || coordinator.isWorking)
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Bank Connection", systemImage: "link")
        }
    }

    private var syncCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syncHeadline)
                            .font(.headline)
                        Text(syncDetail)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if coordinator.isWorking {
                        ProgressView()
                    }
                }

                if let statusMessage = coordinator.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = coordinator.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let launchAtLoginMessage {
                    Label(launchAtLoginMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                Toggle("Open MoneyMap for Mac at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }

                HStack {
                    Button {
                        Task { await coordinator.syncAll(context: modelContext) }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!credentialEditor.hasStoredCredentials || connections.isEmpty || coordinator.isWorking)

                    if credentialEditor.environment == .sandbox {
                        Button {
                            Task { await coordinator.createSandboxConnection(context: modelContext) }
                        } label: {
                            Label("Create Sandbox Test Bank", systemImage: "testtube.2")
                        }
                        .disabled(!credentialEditor.hasStoredCredentials || coordinator.isWorking)
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Mac Server", systemImage: "desktopcomputer")
        }
    }

    private var connectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupBox {
                if connections.isEmpty {
                    ContentUnavailableView("No Bank Connections", systemImage: "link")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(connections) { connection in
                            MacPlaidConnectionRow(
                                connection: connection,
                                onReconnect: {
                                    Task { await coordinator.startReconnect(itemID: connection.itemID) }
                                },
                                onRemove: {
                                    connectionPendingRemoval = connection
                                }
                            )
                            if connection.id != connections.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } label: {
                Label("Connections", systemImage: "building.columns")
            }

            Text("Account rows are read-only snapshots. Remove a bank connection here to clean up test banks and synced accounts in MoneyMap.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var phoneSyncCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: "iphone.gen3")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready for iPhone Review")
                        .font(.headline)
                    Text(phoneSyncSummary)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 20) {
                    MetricTile(title: "Transactions", value: "\(readyReviewItems.count)", symbol: "tray.full")
                    MetricTile(title: "Suggestions", value: "\(readySuggestions.count)", symbol: "lightbulb")
                }
                .frame(maxWidth: 220)
            }
            .padding(4)
        } label: {
            Label("iPhone Sync", systemImage: "icloud.and.arrow.up")
        }
    }

    private var advancedDetailsCard: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showingAdvancedDetails) {
                VStack(alignment: .leading, spacing: 18) {
                    storageStatusCard
                    accountsCard
                    transactionsCard
                    diagnosticsCard
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Label("Details and Diagnostics", systemImage: "stethoscope")
                    Spacer()
                    Text("\(accounts.count) accounts, \(reviewItems.count) transactions")
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }
            .padding(4)
        }
    }

    private var accountsCard: some View {
        GroupBox {
            if accounts.isEmpty {
                ContentUnavailableView("No Synced Accounts", systemImage: "building.columns")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        Text("Account").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Type").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Balance").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(accounts) { account in
                        GridRow {
                            Text(account.displayName)
                            Text(account.subtype ?? account.type).foregroundStyle(.secondary)
                            Text(balanceText(account)).monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Account Snapshots", systemImage: "list.bullet.rectangle")
        }
    }

    private var transactionsCard: some View {
        GroupBox {
            if reviewItems.isEmpty {
                ContentUnavailableView("No Synced Transactions", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        MetricTile(title: "Ready", value: "\(readyReviewItems.count)", symbol: "tray.full")
                        MetricTile(title: "Imported", value: "\(importedReviewItems.count)", symbol: "checkmark.circle")
                        MetricTile(title: "Skipped", value: "\(skippedReviewItems.count)", symbol: "forward.end")
                    }

                    Divider()

                    ForEach(Array(reviewItems.prefix(10))) { reviewItem in
                        MacPlaidTransactionRow(reviewItem: reviewItem)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Transactions", systemImage: "list.bullet.rectangle")
        }
    }

    private var reviewCard: some View {
        GroupBox {
            HStack(spacing: 24) {
                MetricTile(title: "Transactions", value: "\(readyReviewItems.count)", symbol: "tray.full")
                MetricTile(title: "Suggestions", value: "\(readySuggestions.count)", symbol: "lightbulb")
                MetricTile(title: "Connections", value: "\(connections.count)", symbol: "link")
            }
        } label: {
            Label("Prepared for Review", systemImage: "checklist")
        }
    }

    private var diagnosticsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                DiagnosticLine(label: "Environment", value: credentialEditor.environment.displayName)
                DiagnosticLine(label: "Connections", value: "\(connections.count)")
                DiagnosticLine(label: "Accounts", value: "\(accounts.count)")
                DiagnosticLine(label: "Transactions", value: "\(reviewItems.count)")
                DiagnosticLine(label: "Suggestions", value: "\(suggestions.count)")
                if let pendingLinkSession = coordinator.pendingLinkSession {
                    DiagnosticLine(label: "Pending Link", value: pendingLinkSession.mode == .addItem ? "Add bank" : "Reconnect")
                    DiagnosticLine(label: "Link Token", value: pendingLinkSession.linkToken)
                }
                ForEach(connections.filter { $0.errorMessage != nil }) { connection in
                    DiagnosticLine(
                        label: connection.institutionName ?? "Connection",
                        value: connection.errorMessage ?? "Needs attention"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        } label: {
            Label("Diagnostics", systemImage: "stethoscope")
        }
    }


    private var syncHeadline: String {
        if let lastSyncAt = connections.compactMap(\.lastSyncAt).max() {
            let freshness = BankSyncFreshness(lastSyncAt: lastSyncAt)
            let prefix = freshness.level.isStale ? "Stale sync" : "Last synced"
            let age = freshness.level.isStale ? " - \(freshness.ageLabel ?? "old")" : ""
            return "\(prefix) \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))\(age)"
        }
        return connections.isEmpty ? "Ready to connect a bank" : "Ready to sync"
    }

    private var syncDetail: String {
        automaticRefreshEnabled
            ? "This Mac refreshes every \(automaticRefreshIntervalLabel) while MoneyMap is open. iPhone and iPad read the shared snapshots."
            : "Automatic refresh is off. iPhone and iPad read snapshots after you sync this Mac."
    }

    private var automaticRefreshConfigurationID: String {
        "\(automaticRefreshEnabled)-\(refreshIntervalMinutes)-\(credentialEditor.hasStoredCredentials)-\(connections.count)"
    }

    private var automaticRefreshIntervalLabel: String {
        switch refreshIntervalMinutes {
        case 30:
            return "30 minutes"
        case 60:
            return "hour"
        case 180:
            return "3 hours"
        case 360:
            return "6 hours"
        default:
            return "\(refreshIntervalMinutes) minutes"
        }
    }

    private var removeConnectionTitle: String {
        guard let connectionPendingRemoval else { return "Remove Bank Connection?" }
        return "Remove \(connectionPendingRemoval.institutionName ?? "Bank Connection")?"
    }

    private var removeConnectionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { connectionPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    connectionPendingRemoval = nil
                }
            }
        )
    }

    private var primaryStatus: (title: String, detail: String, systemImage: String, color: Color) {
        if !credentialEditor.hasStoredCredentials {
            return (
                "Set up Plaid credentials",
                "Save your Client ID and the matching Sandbox or Production secret before connecting banks.",
                "key",
                .orange
            )
        }

        if coordinator.pendingLinkSession != nil {
            return (
                "Finish the bank connection",
                "Plaid Link is open or waiting in your browser. Finish it there, then return here.",
                "link",
                .accentColor
            )
        }

        if connections.isEmpty {
            return (
                "Ready to connect a bank",
                "Credentials are saved. Start Plaid Link to connect your first bank.",
                "link.badge.plus",
                .accentColor
            )
        }

        if !connectionsNeedingAttention.isEmpty {
            return (
                "\(connectionsNeedingAttention.count) bank\(connectionsNeedingAttention.count == 1 ? "" : "s") need attention",
                "Reconnect the affected bank login, then sync again.",
                "exclamationmark.triangle",
                .orange
            )
        }

        if readyReviewItems.count + readySuggestions.count > 0 {
            return (
                "New items are ready on iPhone",
                "\(readyReviewItems.count) transactions and \(readySuggestions.count) suggestions are waiting for review.",
                "iphone.gen3",
                .green
            )
        }

        if let lastSyncAt = connections.compactMap(\.lastSyncAt).max() {
            let freshness = BankSyncFreshness(lastSyncAt: lastSyncAt)
            if freshness.level.isStale {
                return (
                    "Bank data is stale",
                    "Last synced \(lastSyncAt.formatted(date: .abbreviated, time: .shortened)) (\(freshness.ageLabel ?? "old")). Run Sync Now to refresh Plaid and push a new iPhone snapshot.",
                    "exclamationmark.triangle",
                    .orange
                )
            }
            return (
                "Bank sync is current",
                "Last synced \(lastSyncAt.formatted(date: .abbreviated, time: .shortened)).",
                "checkmark.circle",
                .green
            )
        }

        return (
            "Ready to sync",
            "Your bank connection is saved. Run Sync Now to refresh accounts and transactions.",
            "arrow.triangle.2.circlepath",
            .accentColor
        )
    }

    private var nextActionTitle: String {
        if !credentialEditor.hasStoredCredentials {
            return "Add your Plaid credentials"
        }
        if coordinator.pendingLinkSession != nil {
            return "Finish Plaid Link"
        }
        if connections.isEmpty {
            return "Connect your first bank"
        }
        return "Sync bank data"
    }

    private var nextActionDetail: String {
        if !credentialEditor.hasStoredCredentials {
            return "MoneyMap needs your Plaid Client ID and the secret for the environment you want to use."
        }
        if coordinator.pendingLinkSession != nil {
            return "Complete bank login in the browser, then finish the connection here."
        }
        if connections.isEmpty {
            return "This opens Plaid in your browser. Credentials and tokens stay on this Mac."
        }
        return "Refresh accounts, transactions, and suggestions, then send the latest snapshot to iPhone."
    }

    private var nextActionSystemImage: String {
        if !credentialEditor.hasStoredCredentials {
            return "key"
        }
        if coordinator.pendingLinkSession != nil {
            return "checkmark.circle"
        }
        if connections.isEmpty {
            return "link.badge.plus"
        }
        return "arrow.triangle.2.circlepath"
    }

    private var phoneSyncSummary: String {
        if readyReviewItems.isEmpty && readySuggestions.isEmpty {
            return connections.isEmpty
                ? "Connect a bank on this Mac first. Your iPhone will receive safe snapshots after a sync."
                : "No new review items are waiting right now. Sync again when you want to refresh bank data."
        }

        return "Open MoneyMap on iPhone, go to Wallet, then Bank Sync to review imported bank data."
    }

    private var connectionsNeedingAttention: [PlaidConnection] {
        connections.filter { connection in
            connection.errorMessage?.isEmpty == false ||
            connection.status == "needs_attention" ||
            connection.status == "needs_credentials"
        }
    }

    private var readyReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .ready }
    }

    private var importedReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .imported }
    }

    private var skippedReviewItems: [PlaidTransactionReviewItem] {
        reviewItems.filter { $0.status == .skipped }
    }

    private var readySuggestions: [PlaidSuggestion] {
        suggestions.filter { $0.status == .ready }
    }

    private func balanceText(_ account: PlaidAccountSnapshot) -> String {
        guard let balance = account.currentBalance else { return "Not available" }
        return balance.formatted(.currency(code: account.currencyCode ?? "USD"))
    }

    private func openPlaidDashboard() {
        openPlaidAPIKeys()
    }

    private func openPlaidSignup() {
        NSWorkspace.shared.open(URL(string: "https://dashboard.plaid.com/signup")!)
    }

    private func openPlaidAPIKeys() {
        NSWorkspace.shared.open(URL(string: "https://dashboard.plaid.com/team/keys")!)
    }

    @discardableResult
    private func saveCredentials() -> Bool {
        credentialStatusMessage = nil
        credentialErrorMessage = nil

        do {
            try credentialEditor.save()
            credentialStatusMessage = "\(credentialEditor.environment.displayName) credentials saved. Next: start a bank connection."
            return true
        } catch {
            credentialErrorMessage = error.localizedDescription
            return false
        }
    }

    private func loadCredentialValues() {
        credentialStatusMessage = nil
        credentialErrorMessage = nil

        do {
            try credentialEditor.loadValuesForEditing()
            credentialStatusMessage = "Saved credentials loaded."
        } catch {
            credentialErrorMessage = error.localizedDescription
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLoginMessage = enabled ? "MoneyMap for Mac will open when you sign in." : "MoneyMap for Mac will not open at login."
        } catch {
            launchAtLogin = LaunchAtLoginController.isEnabled
            launchAtLoginMessage = error.localizedDescription
        }
    }
}

struct MacBankSyncSettingsView: View {
    var body: some View {
        Form {
            Text("Manage Plaid credentials and bank sync from the main MoneyMap for Mac window.")
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacPlaidConnectionRow: View {
    let connection: PlaidConnection
    let onReconnect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: connection.errorMessage == nil ? "building.columns" : "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(connection.errorMessage == nil ? Color.accentColor : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.institutionName ?? "Plaid connection")
                    .font(.headline)
                Text(statusText)
                    .foregroundStyle(.secondary)
                if let errorMessage = connection.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            HStack {
                Button("Reconnect", systemImage: "arrow.triangle.2.circlepath") {
                    onReconnect()
                }

                Button("Remove", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        var parts: [String] = []
        if let status = connection.status, !status.isEmpty {
            parts.append(status.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let lastSyncAt = connection.lastSyncAt {
            parts.append("Last synced \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.isEmpty ? "Waiting for first sync" : parts.joined(separator: " - ")
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

private struct DiagnosticLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}

private struct PlaidCredentialSlotStatus: View {
    let environment: PlaidCredentialEnvironment
    let isSaved: Bool

    var body: some View {
        Label(
            isSaved ? "\(environment.displayName) saved" : "\(environment.displayName) empty",
            systemImage: isSaved ? "checkmark.circle.fill" : "circle"
        )
        .font(.caption)
        .foregroundStyle(isSaved ? Color.green : Color.secondary)
    }
}

private struct GuidedPlaidStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
