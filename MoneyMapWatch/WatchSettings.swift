import SwiftUI
import UserNotifications
import SwiftData

struct WatchSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("watchFollowPhoneTheme") private var followPhone = true
    @AppStorage("moneyMapAppearanceStyle") private var appearance = "warm"
    @AppStorage("watchRemindersEnabled") private var reminders = false
    @AppStorage("watchSmartSuggestions", store: UserDefaults(suiteName: "group.com.heyjoshsmith.MoneyMap")) private var suggestions = true
    @State private var error: String?
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Match iPhone", isOn: $followPhone)
                if !followPhone {
                    Picker("Theme", selection: $appearance) { Text("Warm").tag("warm"); Text("System").tag("system") }
                        .onChange(of: appearance) { _, value in MoneyMapSharedDesign.setAppearanceStyleRawValue(value) }
                }
            }
            Section("Reminders") {
                Toggle("Remind on Watch", isOn: $reminders).onChange(of: reminders) { _, enabled in
                    Task {
                        do {
                            if enabled {
                                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                if !allowed { reminders = false; error = "Enable notifications in Watch settings."; return }
                            }
                            try await WatchReminders.refresh(bills: context.fetch(FetchDescriptor<Bill>()), configs: context.fetch(FetchDescriptor<PaydayConfig>()))
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Text("Use Watch reminders for standalone use. Turn off phone reminders to avoid duplicates.").font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Smart Stack Suggestions", isOn: $suggestions)
            NavigationLink("Payday") { WatchPaydayEditor() }
            NavigationLink("Bank Connections") { WatchBankConnectionsView() }
            Section("Storage") {
                Text(MoneyMapSharedContainerFactory.lastReport.mode.displayName)
                Text("Saved changes sync through iCloud when available.").font(.caption2).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption) }
        }.navigationTitle("Settings")
    }
}

@MainActor enum WatchReminders {
    static func refresh(bills: [Bill], configs: [PaydayConfig]) async throws {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("watch-finance/") || $0.identifier.hasPrefix("watch-snooze/") }.map(\.identifier))
        guard UserDefaults.standard.bool(forKey: "watchRemindersEnabled") else { return }
        let calendar = Calendar.current
        var reminders: [(String, String, Date, String)] = bills
            .filter { $0.lifecycleState == .active && $0.datePaid == nil && $0.reminderNotificationsEnabled }
            .compactMap { bill in bill.dueDate.map { (bill.id.uuidString, bill.name ?? "Bill", $0, "bill/\(bill.id)") } }
        if let date = configs.compactMap({ $0.nextScheduledPayday(onOrAfter: .now) }).min() { reminders.append(("payday", "Payday", date, "plan")) }
        for (id, name, date, route) in reminders.sorted(by: { $0.2 < $1.2 }).prefix(40) {
            guard let time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date), time > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = name; content.body = id == "payday" ? "Review your payday plan." : "Your bill is due today."
            content.sound = .default; content.userInfo = ["route": route]; content.categoryIdentifier = "watch-finance"
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time), repeats: false)
            try await center.add(UNNotificationRequest(identifier: "watch-finance/\(id)", content: content, trigger: trigger))
        }
    }
}
