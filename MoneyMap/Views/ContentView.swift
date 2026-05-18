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
    @EnvironmentObject private var payCycleLiveActivityManager: PayCycleLiveActivityManager
    @Query(sort: \Goal.deadline, order: .forward) private var goals: [Goal]
    @Query private var bills: [Bill]
    @Query private var paydayConfigs: [PaydayConfig]
    @State private var selection: Tab = .bills
    
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion = ""
    @State private var pendingCSVURLs: [URL] = []
    @State private var showingBillsImportSheet = false
    @State private var showingWhatsNew = false
    
    var body: some View {
        TabView(selection: $selection) {
            GoalsView().tag(Tab.goals)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Goals")
                }
            PaydayView().tag(Tab.pay)
                .tabItem {
                    Image(systemName: "dollarsign.arrow.circlepath")
                    Text("Pay")
                }
            NavigationStack {
                RecommendationsView()
            }
            .tag(Tab.recommendations)
                .tabItem {
                    Image(systemName: "wand.and.stars")
                    Text("Plan")
                }
            BillsHome().tag(Tab.bills)
                .tabItem {
                    Image(systemName: "banknote")
                    Text("Bills")
                }
            Settings().tag(Tab.settings)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .onReceive(deepLinkManager.$pendingRoute) { route in
            guard let route else { return }
            handle(route: route)
            deepLinkManager.clearPendingRoute()
        }
        .sheet(isPresented: $showingBillsImportSheet) {
            CreditCardPickerSheet(csvURLs: pendingCSVURLs) { selectedBill in
                // Import logic goes here
                for url in pendingCSVURLs {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            let context = selectedBill.modelContext ?? modelContext
                            _ = try importTransactions(fromCSVAt: url, to: selectedBill, context: context)
                        } catch {
                            print("Error importing CSV: \(error)")
                        }
                    }
                }
                pendingCSVURLs.removeAll()
            }
        }
        .sheet(isPresented: $showingWhatsNew) {
            if let latest = WhatsNewRepository.latest {
                WhatsNewView(releases: [latest]) {
                    lastSeenWhatsNewVersion = MoneyMapVersion.marketingVersion
                    showingWhatsNew = false
                }
            }
        }
        .onAppear {
            maybePresentWhatsNew()
            consumePendingRouteIfNeeded()
            syncGoalNotifications()
            syncSearchIndex()
            syncPayCycleLiveActivity()
            reloadWidgetTimelines()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                consumePendingRouteIfNeeded()
                syncGoalNotifications()
                syncSearchIndex()
                syncPayCycleLiveActivity()
                reloadWidgetTimelines()
            }
        }
        .onChange(of: goalNotificationSignature) { _, _ in
            syncGoalNotifications()
        }
        .onChange(of: searchIndexSignature) { _, _ in
            syncSearchIndex()
            syncPayCycleLiveActivity()
            reloadWidgetTimelines()
        }
    }

    private func handle(route: MoneyMapRoute) {
        switch route {
        case .importCSV(let url):
            pendingCSVURLs = [url]
            showingBillsImportSheet = true
        case .openBill(let billID):
            selection = .bills
            deepLinkManager.requestedBillID = billID
        case .openGoal(let goalID):
            selection = .goals
            deepLinkManager.requestedGoalID = goalID
        case .showUpcomingBills:
            selection = .bills
            deepLinkManager.requestedBillsDestination = .upcomingBills
        case .showCardUtilization:
            selection = .bills
            deepLinkManager.requestedBillsDestination = .cardUtilization
        case .showRecommendations:
            selection = .recommendations
        }
    }

    private func maybePresentWhatsNew() {
        if lastSeenWhatsNewVersion != MoneyMapVersion.marketingVersion {
            showingWhatsNew = true
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

    private var searchIndexSignature: String {
        let goalSignature = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.amountSaved)|\($0.targetAmount ?? 0)" }
            .joined(separator: ";")
        let billSignature = bills
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.amount ?? 0)|\($0.dueDate?.timeIntervalSince1970 ?? 0)|\($0.datePaid?.timeIntervalSince1970 ?? 0)" }
            .joined(separator: ";")
        let paydayAmount = paydayConfigs.first?.amountPerPayday ?? 0
        return "\(goalSignature)#\(billSignature)#\(paydayAmount)#\(paydayManager.nextPayday?.timeIntervalSince1970 ?? 0)"
    }

    private func syncSearchIndex() {
        SpotlightIndexer.reindexBills(bills)
        SpotlightIndexer.reindexGoals(goals)
        let digest = FinancialPlanningEngine.digest(
            availableCash: paydayConfigs.first?.amountPerPayday ?? 0,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )
        SpotlightIndexer.reindexRecommendations(digest)
    }

    private func syncPayCycleLiveActivity() {
        payCycleLiveActivityManager.sync(
            availableCash: paydayConfigs.first?.amountPerPayday ?? 0,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday
        )
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "MainWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "PaydayCountdownWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "NextBillWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "UpcomingBillsListWidget")
    }
    
    enum Tab: String, CaseIterable, Identifiable {
        case goals, pay, recommendations, bills, settings
        var id: Self { return self }
    }
}

struct CreditCardPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    let csvURLs: [URL]
    let onImport: (Bill) -> Void
    @Query private var bills: [Bill]
    @Environment(\.dismiss) private var dismiss

    var creditCards: [Bill] {
        bills.filter { $0.category == .creditCard }
    }
    var body: some View {
        NavigationView {
            List(creditCards, id: \.id) { card in
                Button {
                    onImport(card)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: card.category?.icon ?? "creditcard")
                            .foregroundStyle(.blue)
                        Text(card.name ?? "Untitled")
                        Spacer()
                        if let amount = card.amount {
                            Text(amount, format: .currency(code: "USD"))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Credit Card")
        }
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    ContentView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .environmentObject(NotificationManager())
        .environmentObject(PayCycleLiveActivityManager())
        .modelContainer(container)
}
