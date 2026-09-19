#if os(watchOS)
import AppIntents
import Foundation

struct OpenWatchFinanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open MoneyMap"
    static var openAppWhenRun = true
    @Parameter(title: "Destination") var route: String
    init() {}
    init(route: String) { self.route = route }
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WatchSnapshotStore.suite)?.set(route, forKey: "watchPendingRoute")
        return .result()
    }
}
struct WatchRecordSpendingIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Spending"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WatchSnapshotStore.suite)?.set("record", forKey: "watchPendingRoute")
        return .result()
    }
}
struct WatchShowPaydayIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Payday"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WatchSnapshotStore.suite)?.set("plan", forKey: "watchPendingRoute")
        return .result()
    }
}
struct WatchFinanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WatchRecordSpendingIntent(), phrases: ["Record spending in \(.applicationName)"], shortTitle: "Record Spending", systemImageName: "cart.badge.plus")
        AppShortcut(intent: WatchShowPaydayIntent(), phrases: ["Show payday in \(.applicationName)"], shortTitle: "Payday", systemImageName: "banknote")
    }
}
#endif
