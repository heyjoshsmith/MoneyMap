import Foundation
import UserNotifications
import WatchKit
import SwiftData

final class WatchNotificationDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let snooze = UNNotificationAction(identifier: "snooze", title: "Remind in One Hour", options: [])
        let details = UNNotificationAction(identifier: "details", title: "View Details", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "watch-finance", actions: [details, snooze], intentIdentifiers: [])])
    }
    func applicationDidBecomeActive() { scheduleRefresh() }
    private func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(3600), userInfo: nil) { error in
            if let error { print("Watch background refresh deferred: \(error.localizedDescription)") }
        }
    }
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard task is WKApplicationRefreshBackgroundTask else { task.setTaskCompletedWithSnapshot(false); continue }
            Task { @MainActor in
                defer { task.setTaskCompletedWithSnapshot(false); scheduleRefresh() }
                do {
                    let context = ModelContext(try MoneyMapSharedContainerFactory.make())
                    try WatchFinanceService.refreshRecurringBills(context: context)
                    WatchAfterSave.update(context)
                } catch { print("Watch background update failed: \(error.localizedDescription)") }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        if response.actionIdentifier == "snooze", let copy = content.mutableCopy() as? UNMutableNotificationContent {
            try? await center.add(UNNotificationRequest(identifier: "watch-snooze/" + UUID().uuidString, content: copy, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
        } else if let route = content.userInfo["route"] as? String {
            UserDefaults(suiteName: WatchSnapshotStore.suite)?.set(route, forKey: "watchPendingRoute")
            await MainActor.run { NotificationCenter.default.post(name: .init("WatchRouteRequested"), object: nil) }
        }
    }
}
