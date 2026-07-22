//
//  NotificationManager.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation
@preconcurrency import UserNotifications
import WidgetKit

final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let billDueCategoryID = "BILL_DUE_REMINDER"
    static let autopayBillDueCategoryID = "AUTOPAY_BILL_DUE_REMINDER"
    static let openBillActionID = "OPEN_BILL"
    static let markPaidActionID = "MARK_BILL_PAID"
    static let snoozeActionID = "SNOOZE_BILL_REMINDER"
    static let billIDUserInfoKey = "bill_id"
    static let billReminderPrefix = "bill_due_"
    static let goalReminderPrefix = "goal_progress_"
    static let goalDeadlineReminderPrefix = "goal_deadline_"
    static let notifyGoalBehindEnabledKey = "notifyGoalBehindEnabled"
    static let notificationTimeKey = "notificationTime"

    weak var deepLinkManager: DeepLinkManager?

    private struct BillReminderCandidate: Sendable {
        let billID: UUID
        let name: String
        let amount: Double
        let dueDate: Date
        let reminderDate: Date
        let autopayEnabled: Bool
    }

    private struct GoalReminderPlan: Sendable {
        let requests: [GoalReminderRequest]
        let activeIdentifiers: Set<String>
    }

    private struct GoalReminderRequest: Sendable {
        let identifier: String
        let date: Date
        let title: String
        let body: String
    }

    func attach(deepLinkManager: DeepLinkManager) {
        self.deepLinkManager = deepLinkManager
        configureCenter()
    }

    func configureCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if Self.canDeliverNotifications(settings) {
                completion?(true)
                return
            }

            guard settings.authorizationStatus == .notDetermined else {
                completion?(false)
                return
            }

            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                completion?(granted)
            }
        }
    }

    func scheduleBillDueNotifications(for bills: [Bill]) {
        let candidates = billReminderCandidates(for: bills)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard Self.canDeliverNotifications(settings) else { return }
            Task { @MainActor in
                self.scheduleAuthorizedBillDueNotifications(for: candidates)
            }
        }
    }

    private func billReminderCandidates(for bills: [Bill]) -> [BillReminderCandidate] {
        let now = Date()

        return bills.compactMap { bill -> BillReminderCandidate? in
            guard bill.datePaid == nil, let dueDate = bill.dueDate else { return nil }
            guard let reminderDate = reminderDate(for: dueDate), reminderDate > now.addingTimeInterval(60) else {
                return nil
            }
            return BillReminderCandidate(
                billID: bill.id,
                name: bill.name ?? "Your bill",
                amount: bill.amount ?? 0,
                dueDate: dueDate,
                reminderDate: reminderDate,
                autopayEnabled: bill.autopayEnabled
            )
        }
    }

    @MainActor
    private func scheduleAuthorizedBillDueNotifications(for candidates: [BillReminderCandidate]) {
        let center = UNUserNotificationCenter.current()
        let activeIdentifiers = Set(candidates.map { reminderIdentifier(for: $0.billID) })
        center.getPendingNotificationRequests { requests in
            let stale = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.billReminderPrefix) && !activeIdentifiers.contains($0) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }
        }

        for candidate in candidates {
            let content = UNMutableNotificationContent()
            let amount = MoneyMapFormatters.currencyString(for: candidate.amount)
            let dueText = MoneyMapFormatters.mediumDateString(for: candidate.dueDate)
            content.title = candidate.autopayEnabled ? "Autopay Bill Due Soon" : "Bill Due Soon"
            content.body = candidate.autopayEnabled
                ? "\(candidate.name) for \(amount) is due \(dueText). Autopay is on, so no manual checkoff is needed."
                : "\(candidate.name) for \(amount) is due \(dueText)."
            content.sound = .default
            content.categoryIdentifier = candidate.autopayEnabled ? Self.autopayBillDueCategoryID : Self.billDueCategoryID
            content.userInfo = [Self.billIDUserInfoKey: candidate.billID.uuidString]

            let triggerDate = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: candidate.reminderDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(for: candidate.billID),
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if let error {
                    print("Bill reminder scheduling error: \(error.localizedDescription)")
                }
            }
        }
    }

    func scheduleGoalProgressNotifications(for goals: [Goal], nextPayday: Date?) {
        let plan = goalReminderPlan(for: goals, nextPayday: nextPayday)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard Self.canDeliverNotifications(settings) else { return }
            Task { @MainActor in
                self.scheduleAuthorizedGoalProgressNotifications(plan)
            }
        }
    }

    private func goalReminderPlan(for goals: [Goal], nextPayday: Date?) -> GoalReminderPlan {
        let shouldNotify = boolSetting(for: Self.notifyGoalBehindEnabledKey, defaultValue: true)
        let insights = FinancialPlanningEngine.goalProgressInsights(goals: goals, nextPayday: nextPayday)
            .filter(\.isBehindSchedule)
        var requests: [GoalReminderRequest] = []
        var activeIdentifiers: Set<String> = []

        guard shouldNotify, !insights.isEmpty else {
            return GoalReminderPlan(requests: [], activeIdentifiers: [])
        }

        if let nextPayday, let reminderDate = scheduledDate(on: nextPayday) {
            let topInsights = Array(insights.prefix(3))
            let totalCatchUp = topInsights.reduce(0) { $0 + $1.shortfallAmount }
            let body: String
            if topInsights.count == 1, let first = topInsights.first {
                body = "You're behind on \(first.goalName) by about \(MoneyMapFormatters.currencyString(for: first.shortfallAmount))."
            } else {
                let names = topInsights.map(\.goalName).joined(separator: ", ")
                body = "You're behind on \(insights.count) goals. Catch up about \(MoneyMapFormatters.currencyString(for: totalCatchUp)) across \(names)."
            }

            let identifier = "\(Self.goalReminderPrefix)payday"
            activeIdentifiers.insert(identifier)
            requests.append(GoalReminderRequest(
                identifier: identifier,
                date: reminderDate,
                title: "Goal Check-In",
                body: body
            ))
        }

        for insight in insights.prefix(3) {
            guard
                let goal = goals.first(where: { $0.id == insight.goalID }),
                let deadline = goal.deadline,
                let reminderDate = urgentGoalReminderDate(for: deadline)
            else {
                continue
            }

            let identifier = "\(Self.goalDeadlineReminderPrefix)\(goal.id.uuidString)"
            activeIdentifiers.insert(identifier)
            requests.append(GoalReminderRequest(
                identifier: identifier,
                date: reminderDate,
                title: "Goal Deadline Coming Up",
                body: "\(insight.goalName) is behind by about \(MoneyMapFormatters.currencyString(for: insight.shortfallAmount))."
            ))
        }

        return GoalReminderPlan(requests: requests, activeIdentifiers: activeIdentifiers)
    }

    @MainActor
    private func scheduleAuthorizedGoalProgressNotifications(_ plan: GoalReminderPlan) {
        let center = UNUserNotificationCenter.current()

        guard !plan.requests.isEmpty else {
            clearPendingGoalNotifications()
            return
        }

        for request in plan.requests {
            scheduleNotification(
                center: center,
                identifier: request.identifier,
                date: request.date,
                title: request.title,
                body: request.body
            )
        }

        center.getPendingNotificationRequests { requests in
            let stale = requests
                .map(\.identifier)
                .filter {
                    ($0.hasPrefix(Self.goalReminderPrefix) || $0.hasPrefix(Self.goalDeadlineReminderPrefix)) &&
                    !plan.activeIdentifiers.contains($0)
                }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }
        }
    }

    static func canDeliverNotifications(_ settings: UNNotificationSettings) -> Bool {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func registerCategories() {
        let center = UNUserNotificationCenter.current()
        let openBillAction = UNNotificationAction(
            identifier: Self.openBillActionID,
            title: "Open Bill",
            options: [.foreground]
        )
        let markPaidAction = UNNotificationAction(
            identifier: Self.markPaidActionID,
            title: "Mark Paid",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "Snooze 1h",
            options: []
        )
        let manualCategory = UNNotificationCategory(
            identifier: Self.billDueCategoryID,
            actions: [openBillAction, markPaidAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        let autopayCategory = UNNotificationCategory(
            identifier: Self.autopayBillDueCategoryID,
            actions: [openBillAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([manualCategory, autopayCategory])
    }

    private func reminderDate(for dueDate: Date) -> Date? {
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: dueDate) else {
            return nil
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components)
    }

    private func scheduledDate(on day: Date) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let storedTime = UserDefaults.standard.object(forKey: Self.notificationTimeKey) as? Date
        let time = storedTime ?? defaultNotificationTime()
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return Calendar.current.date(from: components)
    }

    private func urgentGoalReminderDate(for deadline: Date) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let reminderBase = calendar.date(byAdding: .day, value: -3, to: deadline) ?? deadline
        let targetDay = max(today, calendar.startOfDay(for: reminderBase))
        guard targetDay <= calendar.startOfDay(for: deadline) else {
            return nil
        }
        return scheduledDate(on: targetDay)
    }

    private func reminderIdentifier(for billID: UUID) -> String {
        "\(Self.billReminderPrefix)\(billID.uuidString)"
    }

    private func clearPendingGoalNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter {
                    $0.hasPrefix(Self.goalReminderPrefix) || $0.hasPrefix(Self.goalDeadlineReminderPrefix)
                }
            if !identifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }

    private func scheduleNotification(
        center: UNUserNotificationCenter,
        identifier: String,
        date: Date,
        title: String,
        body: String
    ) {
        guard date > Date().addingTimeInterval(60) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("Goal reminder scheduling error: \(error.localizedDescription)")
            }
        }
    }

    private func boolSetting(for key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func defaultNotificationTime() -> Date {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func billID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let rawID = userInfo[Self.billIDUserInfoKey] as? String else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    private func queueRouteToBill(_ billID: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.deepLinkManager?.pendingRoute = .openBill(billID)
            self?.deepLinkManager?.requestedBillID = billID
        }
    }

    private func handleMarkPaid(billID: UUID) {
        do {
            try MoneyMapBillStore.markPaid(billID: billID, amount: nil)
            clearPendingBillNotifications(for: billID)
            scheduleBillDueNotifications(for: try MoneyMapBillStore.fetchBills())
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Mark paid from notification failed: \(error.localizedDescription)")
        }
    }

    private func handleSnooze(response: UNNotificationResponse, billID: UUID) {
        let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent
            ?? UNMutableNotificationContent()
        content.userInfo = [Self.billIDUserInfoKey: billID.uuidString]
        content.categoryIdentifier = Self.billDueCategoryID

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(response.notification.request.identifier)_snooze",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Snooze scheduling error: \(error.localizedDescription)")
            }
        }
    }

    private func clearPendingBillNotifications(for billID: UUID) {
        let identifierPrefix = reminderIdentifier(for: billID)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0 == identifierPrefix || $0.hasPrefix("\(identifierPrefix)_") }
            if !identifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let billID = billID(from: response.notification.request.content.userInfo) else {
            return
        }

        switch response.actionIdentifier {
        case Self.markPaidActionID:
            handleMarkPaid(billID: billID)
        case Self.snoozeActionID:
            handleSnooze(response: response, billID: billID)
        case Self.openBillActionID, UNNotificationDefaultActionIdentifier:
            queueRouteToBill(billID)
        default:
            break
        }
    }
}
