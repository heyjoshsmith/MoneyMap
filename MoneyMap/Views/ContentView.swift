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
    @Query private var paydayConfigs: [PaydayConfig]
    @State private var selection: Tab = .home
    
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion = ""
    @State private var pendingCSVURLs: [URL] = []
    @State private var showingBillsImportSheet = false
    @State private var showingWhatsNew = false
    
    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Home", systemImage: "house", value: Tab.home) {
                HomeView()
            }
            SwiftUI.Tab("Bills", systemImage: "banknote", value: Tab.bills) {
                BillsHome()
            }
            SwiftUI.Tab("Goals", systemImage: "target", value: Tab.goals) {
                GoalsView()
            }
            SwiftUI.Tab("Settings", systemImage: "gear", value: Tab.settings) {
                Settings()
            }
            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                MoneyMapAssistantView()
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
                    lastSeenWhatsNewVersion = WhatsNewRepository.currentPresentationID
                    showingWhatsNew = false
                }
            }
        }
        .onAppear {
            maybePresentWhatsNew()
            consumePendingRouteIfNeeded()
            refreshBillStatuses()
            syncBillNotifications()
            syncGoalNotifications()
            syncSearchIndex()
            reloadWidgetTimelines()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                consumePendingRouteIfNeeded()
                refreshBillStatuses()
                syncBillNotifications()
                syncGoalNotifications()
                syncSearchIndex()
                reloadWidgetTimelines()
            }
        }
        .onChange(of: goalNotificationSignature) { _, _ in
            syncGoalNotifications()
        }
        .onChange(of: searchIndexSignature) { _, _ in
            syncBillNotifications()
            syncSearchIndex()
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
            selection = .home
        }
    }

    private func maybePresentWhatsNew() {
        if lastSeenWhatsNewVersion != WhatsNewRepository.currentPresentationID {
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

    private func syncBillNotifications() {
        notificationManager.scheduleBillDueNotifications(for: bills)
    }

    private var searchIndexSignature: String {
        let goalSignature = goals
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.amountSaved)|\($0.targetAmount ?? 0)" }
            .joined(separator: ";")
        let billSignature = bills
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString)|\($0.amount ?? 0)|\($0.dueDate?.timeIntervalSince1970 ?? 0)|\($0.datePaid?.timeIntervalSince1970 ?? 0)|\($0.autopayEnabled)|\($0.gracePeriodDays ?? 0)"
            }
            .joined(separator: ";")
        let transactionSignature = bills
            .flatMap { $0.transactions ?? [] }
            .sorted { MoneyMapTransactionStore.mostRecentFirst(lhs: $0, rhs: $1) }
            .map { transaction in
                "\(transactionEntityID(for: transaction))|\(transaction.amountUSD ?? 0)|\((transaction.transactionDate ?? transaction.clearingDate)?.timeIntervalSince1970 ?? 0)"
            }
            .joined(separator: ";")
        let paydayAmount = paydayConfigs.first?.amountPerPayday ?? 0
        return "\(goalSignature)#\(billSignature)#\(transactionSignature)#\(paydayAmount)#\(paydayManager.nextPayday?.timeIntervalSince1970 ?? 0)"
    }

    private func syncSearchIndex() {
        SpotlightIndexer.reindexBills(bills)
        SpotlightIndexer.reindexGoals(goals)
        SpotlightIndexer.reindexTransactions(bills.flatMap { $0.transactions ?? [] })
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

    private func refreshBillStatuses() {
        var didChange = false

        for bill in bills {
            let previousDueDate = bill.dueDate
            let previousDatePaid = bill.datePaid
            let previousStatus = bill.status

            bill.checkStatus()

            if previousDueDate != bill.dueDate ||
                previousDatePaid != bill.datePaid ||
                previousStatus != bill.status {
                didChange = true
            }
        }

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
        case home, bills, search, goals, settings
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
        .modelContainer(container)
}
