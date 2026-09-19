import SwiftUI
import SwiftData
import WidgetKit

struct WatchDashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var bills: [Bill]
    @Query private var goals: [Goal]
    @Query private var configs: [PaydayConfig]
    @AppStorage("watchOnboarded") private var onboarded = false
    @State private var path: [String] = []
    @State private var showSettings = false
    @State private var refreshError: String?
    private var dueBills: [Bill] { bills.filter { $0.lifecycleState == .active && $0.datePaid == nil }.sorted(by: Bill.byDate) }
    private var nextPayday: Date? { configs.compactMap { $0.nextScheduledPayday(onOrAfter: .now) }.min() }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 10) {
                    if !onboarded && configs.isEmpty && bills.isEmpty && goals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "leaf.fill").font(.title2).foregroundStyle(WatchDesign.green)
                            Text("Your money,\nat a glance.").font(.headline)
                            Text("Set up here or use your existing iCloud data.").font(.caption2).foregroundStyle(.secondary)
                            NavigationLink("Set Up Payday", value: "payday")
                            Button("Explore MoneyMap") { onboarded = true }
                        }.padding()
                    }
                    NavigationLink(value: "plan") {
                        WatchMetric(title: "Payday", value: nextPayday?.daysUntil ?? "Set up",
                            detail: nextPayday?.formatted(.dateTime.month(.abbreviated).day()), symbol: "banknote")
                    }.buttonStyle(.plain)
                    NavigationLink(value: "bills") {
                        WatchMetric(title: "Upcoming bills", value: WatchDesign.money(dueBills.prefix(5).reduce(0) { $0 + ($1.amount ?? 0) }),
                            detail: "Next \(min(5, dueBills.count)) · \(dueBills.filter { ($0.dueDate ?? .distantFuture) < Calendar.current.startOfDay(for: .now) }.count) overdue",
                            symbol: "calendar", tint: WatchDesign.gold)
                    }.buttonStyle(.plain)
                    if let goal = goals.filter({ $0.remainingAmount > 0 }).sorted(by: { $0.createdDate < $1.createdDate }).first {
                        NavigationLink(value: "goal/\(goal.id)") {
                            WatchMetric(title: goal.name ?? "Goal", value: goal.progress().formatted(.percent.precision(.fractionLength(0))),
                                detail: "\(WatchDesign.money(goal.remainingAmount)) to go", symbol: "target", progress: goal.progress())
                        }.buttonStyle(.plain)
                    }
                    NavigationLink("Bills", value: "bills")
                    NavigationLink("Plan", value: "plan")
                    NavigationLink("Wallet", value: "wallet")
                    NavigationLink("Goals", value: "goals")
                    if let refreshError { Text(refreshError).font(.caption2).foregroundStyle(.secondary) }
                }.padding(.horizontal, 4)
            }
            .navigationTitle("MoneyMap")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(.white) } } }
            .navigationDestination(for: String.self) { route in destination(route) }
            .sheet(isPresented: $showSettings) { NavigationStack { WatchSettingsView() } }
            .onOpenURL { url in
                guard url.scheme == "moneymap-watch" else { return }
                path = [(url.host ?? "") + url.path]
            }
            .task { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .init("WatchRouteRequested"))) { _ in consumeRoute() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in Task { await refresh() } }
        }
    }
    @ViewBuilder private func destination(_ route: String) -> some View {
        if route.hasPrefix("bill/"), let id = UUID(uuidString: String(route.dropFirst(5))), let bill = bills.first(where: { $0.id == id }) {
            WatchBillDetailView(bill: bill)
        } else if route.hasPrefix("goal/"), let id = UUID(uuidString: String(route.dropFirst(5))), let goal = goals.first(where: { $0.id == id }) {
            WatchGoalDetailView(goal: goal)
        } else {
            switch route {
            case "bills": WatchBillsView()
            case "goals": WatchGoalsView()
            case "wallet": WatchWalletView()
            case "transactions", "spending": WatchTransactionsView()
            case "record": WatchSpendingEditor()
            case "contribute": WatchGoalsView()
            case "payment": WatchBillsView()
            case "payday": WatchPaydayEditor()
            case "plan": WatchPlanView()
            default: ContentUnavailableView("Item Unavailable", systemImage: "questionmark.folder")
            }
        }
    }
    private func consumeRoute() {
        let defaults = UserDefaults(suiteName: WatchSnapshotStore.suite)
        if let route = defaults?.string(forKey: "watchPendingRoute") {
            defaults?.removeObject(forKey: "watchPendingRoute"); path = [route]
        }
    }
    private func refresh() async {
        WatchThemeSync.shared.start()
        consumeRoute()
        do {
            try WatchFinanceService.refreshRecurringBills(context: context)
            try WatchSnapshotStore.publish(context: context)
            try await WatchReminders.refresh(bills: bills, configs: configs)
            refreshError = nil
        } catch { refreshError = error.localizedDescription }
    }
}
