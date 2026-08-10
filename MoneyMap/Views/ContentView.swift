//
//  ContentView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import WidgetKit

// MARK: - ContentView (TabView)
struct ContentView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject private var paydayManager: PaydayManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \Goal.deadline, order: .forward) private var goals: [Goal]
    @Query private var bills: [Bill]
    @Query private var transactions: [Transaction]
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @Query private var paydayConfigs: [PaydayConfig]
    @State private var selection: Tab = .today
    
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion = ""
    @State private var pendingCSVURLs: [URL] = []
    @State private var showingBillsImportSheet = false
    @State private var showingWhatsNew = false
    @State private var didScheduleInitialStartupWork = false
    @State private var didCompleteInitialStartupWork = false
    @State private var indexAndNotificationRefreshTask: Task<Void, Never>?
    
    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "sun.max", value: Tab.today) {
                HomeView()
            }
            SwiftUI.Tab("Wallet", systemImage: "wallet.pass", value: Tab.wallet) {
                WalletView()
            }
            SwiftUI.Tab("Plan", systemImage: "wand.and.stars", value: Tab.plan) {
                NavigationStack {
                    RecommendationsView()
                }
            }
            SwiftUI.Tab("Goals", systemImage: "target", value: Tab.goals) {
                GoalsView()
            }
            SwiftUI.Tab("Ask", systemImage: "sparkles", value: Tab.ask, role: .search) {
                MoneyMapAssistantView()
            }
        }
        .background(MoneyMapDesign.groupedBackground)
        .onReceive(deepLinkManager.$pendingRoute) { route in
            guard let route else { return }
            handle(route: route)
            deepLinkManager.clearPendingRoute()
        }
        .sheet(isPresented: $showingBillsImportSheet, onDismiss: {
            pendingCSVURLs.removeAll()
        }) {
            TransactionCSVImportGuideView(
                csvURLs: pendingCSVURLs,
                onFinished: { _ in
                    pendingCSVURLs.removeAll()
                    showingBillsImportSheet = false
                },
                onCancel: {
                    pendingCSVURLs.removeAll()
                    showingBillsImportSheet = false
                }
            )
        }
        .sheet(isPresented: $showingWhatsNew) {
            if let latest = WhatsNewRepository.latest {
                WhatsNewView(releases: [latest]) {
                    lastSeenWhatsNewVersion = WhatsNewRepository.currentPresentationID
                    showingWhatsNew = false
                }
            }
        }
        .onAppear {
            MoneyMapDiagnostics.record("content.appear")
            consumePendingRouteIfNeeded()
            scheduleInitialStartupWork()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                consumePendingRouteIfNeeded()
                if didCompleteInitialStartupWork {
                    scheduleForegroundSync()
                }
            }
        }
        .onChange(of: goalNotificationSignature) { _, _ in
            syncGoalNotifications()
        }
        .onChange(of: searchIndexRefreshSignature) { _, _ in
            scheduleIndexAndNotificationRefresh()
        }
        .onChange(of: paymentMethodSyncSignature) { _, _ in
            syncPaymentMethods()
        }
    }

    private func handle(route: MoneyMapRoute) {
        switch route {
        case .importCSV(let url):
            pendingCSVURLs = [url]
            showingBillsImportSheet = true
        case .openBill(let billID):
            selection = .wallet
            deepLinkManager.requestedBillID = billID
        case .openGoal(let goalID):
            selection = .goals
            deepLinkManager.requestedGoalID = goalID
        case .showUpcomingBills:
            selection = .wallet
            deepLinkManager.requestedBillsDestination = .upcomingBills
        case .showCardUtilization:
            selection = .wallet
            deepLinkManager.requestedBillsDestination = .cardUtilization
        case .showRecommendations:
            selection = .plan
        }
    }

    private func maybePresentWhatsNew() {
        if lastSeenWhatsNewVersion != WhatsNewRepository.currentPresentationID {
            showingWhatsNew = true
        }
    }

    private func scheduleInitialStartupWork() {
        guard !didScheduleInitialStartupWork else { return }
        didScheduleInitialStartupWork = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            maybePresentWhatsNew()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            runStartupSyncs()
            didCompleteInitialStartupWork = true
        }
    }

    private func scheduleForegroundSync() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            runStartupSyncs()
        }
    }

    private func runStartupSyncs() {
        syncPaymentMethods()
        refreshBillStatuses()
        syncBillNotifications()
        syncGoalNotifications()
        reloadWidgetTimelines()
        scheduleSearchIndexSync()
    }

    private func scheduleSearchIndexSync() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncSearchIndex()
        }
    }

    private func scheduleIndexAndNotificationRefresh() {
        indexAndNotificationRefreshTask?.cancel()
        indexAndNotificationRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            syncBillNotifications()
            syncSearchIndex()
            reloadWidgetTimelines()
            indexAndNotificationRefreshTask = nil
        }
    }

    private func consumePendingRouteIfNeeded() {
        guard let route = PendingRouteStore.consume() else { return }
        handle(route: route)
    }

    private var goalNotificationSignature: String {
        goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { goal in
                let deadline = goal.deadline?.timeIntervalSince1970 ?? 0
                return "\(goal.id.uuidString)|\(goal.amountSaved)|\(goal.targetAmount ?? 0)|\(goal.amountPerPaycheck ?? 0)|\(deadline)"
            }
            .joined(separator: ";") + "|\(paydayManager.nextPayday?.timeIntervalSince1970 ?? 0)"
    }

    private func syncGoalNotifications() {
        notificationManager.scheduleGoalProgressNotifications(
            for: goals,
            nextPayday: paydayManager.nextPayday
        )
    }

    private func syncBillNotifications() {
        notificationManager.scheduleBillDueNotifications(for: bills)
    }

    private var searchIndexRefreshSignature: String {
        let paydayAmount = paydayConfigs.first?.amountPerPayday ?? 0
        return "\(goals.count)#\(bills.count)#\(transactions.count)#\(paydayAmount)#\(paydayManager.nextPayday?.timeIntervalSince1970 ?? 0)"
    }

    private var resolvedPaycheckAmount: Double {
        MoneyMapPlanningStore.resolvedPaycheckAmount(manualAmount: paydayConfigs.first?.amountPerPayday ?? 0)
    }

    private var paymentMethodSyncSignature: String {
        let creditCardBillSignature = bills
            .filter { $0.category == .creditCard }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { bill in
                "\(bill.id.uuidString)|\(bill.name ?? "")|\(bill.creditCardDetails?.issuerName ?? "")|\(bill.creditCardDetails?.lastFourDigits ?? "")"
            }
            .joined(separator: ";")
        let creditCardMethodSignature = paymentMethods
            .filter { $0.type == .creditCard }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.linkedBillID?.uuidString ?? "")|\($0.displayName)" }
            .joined(separator: ";")
        return "\(creditCardBillSignature)#\(creditCardMethodSignature)"
    }

    private func syncPaymentMethods() {
        guard PaymentMethodSyncService.syncCreditCardPaymentMethods(
            bills: bills,
            paymentMethods: paymentMethods,
            context: modelContext
        ) else {
            return
        }

        try? modelContext.save()
    }

    private func syncSearchIndex() {
        SpotlightIndexer.reindexBills(bills)
        SpotlightIndexer.reindexGoals(goals)
        SpotlightIndexer.reindexTransactions(transactions)
        let digest = FinancialPlanningEngine.digest(
            availableCash: resolvedPaycheckAmount,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )
        SpotlightIndexer.reindexRecommendations(digest)
    }

    private func refreshBillStatuses() {
        var didChange = false

        didChange = BillPaymentMatcher.refreshStatuses(for: bills, transactions: transactions)

        if didChange {
            try? modelContext.save()
        }
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "MainWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "PaydayCountdownWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "NextBillWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "UpcomingBillsListWidget")
    }
    
    enum Tab: String, CaseIterable, Identifiable {
        case today, wallet, plan, goals, ask
        var id: Self { return self }
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    ContentView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .environmentObject(NotificationManager())
        .modelContainer(container)
}
