//
//  PaydayView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import SwiftData
import UserNotifications

struct PaydayRow: Identifiable {
    let id = UUID()
    let items: [Date]
    let bonuses: [Bool]
    let isPriority: Bool
}

struct PaydayView: View {
    
    @EnvironmentObject var paydayManager: PaydayManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var selectedDate = Date()
    @AppStorage("notifyDayBeforeEnabled") private var notifyDayBeforeEnabled: Bool = true
    @AppStorage("notifyDayOfEnabled") private var notifyDayOfEnabled: Bool = true
    @AppStorage("notifyGoalBehindEnabled") private var notifyGoalBehindEnabled: Bool = true
    @AppStorage("notificationTime") private var notificationTime: Date = {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    @State private var showingTimePicker = false
    
    @Query private var bills: [Bill]
    @Query(sort: \Goal.deadline, order: .forward) private var goals: [Goal]
    private var timeString: String {
        notificationTime.formatted(.dateTime.hour().minute())
    }

    private var upcomingPaydays: [Date] {
        paydayManager.upcomingPaydaysForNextYear()
    }

    private var billsBeforeNextPayday: [Bill] {
        guard let nextPayday = paydayManager.nextPayday else { return [] }
        return bills.withoutCreditCards
            .filter { bill in
                guard bill.status != .paid, bill.lifecycleState == .active, let dueDate = bill.dueDate else {
                    return false
                }
                return dueDate <= nextPayday
            }
            .sorted(by: Bill.byDate)
    }

    private var behindGoalCount: Int {
        FinancialPlanningEngine.goalProgressInsights(goals: goals, nextPayday: paydayManager.nextPayday)
            .filter(\.isBehindSchedule)
            .count
    }
    
    var body: some View {
        NavigationStack {
            List {
                if let nextPayday = paydayManager.nextPayday {
                    Section {
                        MoneyMapSummaryRow(
                            title: "Next Payday",
                            value: MoneyMapFormatters.mediumDateString(for: nextPayday),
                            detail: "\(paydayManager.daysUntilNextPayday()) day\(paydayManager.daysUntilNextPayday() == 1 ? "" : "s") away",
                            systemImage: "banknote",
                            tint: MoneyMapDesign.calmGreen
                        )

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MoneyMapDesign.compactSpacing) {
                            MoneyMapMetricTile(
                                title: "Bills Before Payday",
                                value: MoneyMapFormatters.currencyString(for: billsBeforeNextPayday.totalAmount),
                                systemImage: "calendar.badge.exclamationmark",
                                detail: "\(billsBeforeNextPayday.count) bill\(billsBeforeNextPayday.count == 1 ? "" : "s")",
                                tint: billsBeforeNextPayday.isEmpty ? .secondary : MoneyMapDesign.warningGold
                            )
                            MoneyMapMetricTile(
                                title: "Goals Behind",
                                value: "\(behindGoalCount)",
                                systemImage: "target",
                                detail: behindGoalCount == 0 ? "On pace" : "Need attention",
                                tint: behindGoalCount == 0 ? MoneyMapDesign.calmGreen : MoneyMapDesign.warningGold
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)

                    Section("Upcoming Paydays") {
                        ForEach(Array(upcomingPaydays.prefix(8).enumerated()), id: \.offset) { index, payday in
                            PaydayDateRow(
                                date: payday,
                                isNext: index == 0,
                                isBonus: payday.isExtraPayDay(in: upcomingPaydays)
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                } else {
                    Section {
                        MoneyMapSummaryRow(
                            title: "Payday not set",
                            value: "Choose a date",
                            detail: "MoneyMap uses payday timing to organize bills, goals, and paycheck plans.",
                            systemImage: "calendar.badge.plus",
                            tint: MoneyMapDesign.warningGold
                        )

                        DatePicker("Next Payday", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)

                        Button {
                            paydayManager.savePayday(selectedDate)
                        } label: {
                            MoneyMapNeutralButtonLabel(
                                title: "Set Next Payday",
                                systemImage: "checkmark.circle",
                                iconColor: MoneyMapDesign.calmGreen
                            )
                        }
                    }
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }

                Section("Notifications") {
                    Button {
                        notificationManager.requestAuthorizationIfNeeded { granted in
                            guard granted else { return }
                            Task { @MainActor in
                                rescheduleNotifications()
                            }
                        }
                    } label: {
                        MoneyMapActionListRow(
                            title: "Allow Notifications",
                            detail: "Enable payday and goal pacing alerts.",
                            systemImage: "bell.badge",
                            tint: MoneyMapDesign.calmGreen
                        )
                    }
                    .buttonStyle(.plain)

                    Toggle("Day before payday", isOn: $notifyDayBeforeEnabled)
                    Toggle("On payday", isOn: $notifyDayOfEnabled)
                    Toggle("Goals behind schedule", isOn: $notifyGoalBehindEnabled)

                    Button {
                        showingTimePicker = true
                    } label: {
                        MoneyMapActionListRow(
                            title: "Notification Time",
                            detail: timeString,
                            systemImage: "clock",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Pay")
            .background(MoneyMapDesign.groupedBackground)
            .onAppear {
                rescheduleNotifications()
            }
            .onChange(of: notifyDayBeforeEnabled) {
                rescheduleNotifications()
            }
            .onChange(of: notifyDayOfEnabled) {
                rescheduleNotifications()
            }
            .onChange(of: notifyGoalBehindEnabled) {
                rescheduleNotifications()
            }
            .onChange(of: notificationTime) {
                rescheduleNotifications()
            }
            .onChange(of: paydayManager.nextPayday) {
                rescheduleNotifications()
            }
            .popover(isPresented: $showingTimePicker) {
                ZStack {
                    MoneyMapDesign.groupedBackground
                        .ignoresSafeArea()
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            Button("Done") {
                                showingTimePicker = false
                            }
                        }
                        DatePicker("Notification time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(WheelDatePickerStyle())
                            .labelsHidden()
                    }
                    .padding()
                }
                .presentationDetents([.fraction(0.4)])
            }
        }
    }
}

private struct PaydayDateRow: View {
    let date: Date
    let isNext: Bool
    let isBonus: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isBonus ? "sparkles" : "calendar")
                .font(.headline)
                .foregroundStyle(isNext || isBonus ? MoneyMapDesign.calmGreen : .secondary)
                .frame(width: 34, height: 34)
                .background(
                    (isNext || isBonus ? MoneyMapDesign.calmGreen.opacity(0.14) : Color.secondary.opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isNext ? "Next Payday" : date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isBonus {
                Text("Extra")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MoneyMapDesign.calmGreen.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private extension PaydayView {
    func rescheduleNotifications() {
        schedulePaydayNotificationsIfAuthorized(paydayManager.upcomingPaydaysForNextYear())
        notificationManager.scheduleGoalProgressNotifications(
            for: goals,
            nextPayday: paydayManager.nextPayday
        )
    }

    func schedulePaydayNotificationsIfAuthorized(_ paydays: [Date]) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard NotificationManager.canDeliverNotifications(settings) else { return }
            Task { @MainActor in
                scheduleNotifications(paydays)
            }
        }
    }

    private func batchedPaydays(_ paydays: [Date]) -> [PaydayRow] {
        var rows: [PaydayRow] = []
        var i = 0
        while i < paydays.count {
            let payday = paydays[i]
            let bonus = payday.isExtraPayDay(in: paydays)
            let isPriority = (i == 0 || bonus)
            if isPriority {
                rows.append(PaydayRow(items: [payday], bonuses: [bonus], isPriority: true))
                i += 1
            } else {
                if i + 1 < paydays.count {
                    let nextPayday = paydays[i + 1]
                    let nextBonus = nextPayday.isExtraPayDay(in: paydays)
                    let nextIsPriority = ((i + 1) == 0 || nextBonus)
                    if !nextIsPriority {
                        rows.append(PaydayRow(items: [payday, nextPayday], bonuses: [bonus, nextBonus], isPriority: false))
                        i += 2
                    } else {
                        rows.append(PaydayRow(items: [payday], bonuses: [bonus], isPriority: false))
                        i += 1
                    }
                } else {
                    rows.append(PaydayRow(items: [payday], bonuses: [bonus], isPriority: false))
                    i += 1
                }
            }
        }
        return rows
    }
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    PaydayView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .environmentObject(NotificationManager())
        .modelContainer(container)
}


private extension PaydayView {
    func scheduleNotifications(_ paydays: [Date]) {
        let center = UNUserNotificationCenter.current()
        let identifiers = paydays.flatMap { payday in
            [
                "paydayBefore_\(payday.timeIntervalSince1970)",
                "paydayOn_\(payday.timeIntervalSince1970)"
            ]
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        
        let sortedPaydays = paydays.sorted()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d"
        
        for (index, payday) in sortedPaydays.enumerated() {
            let nextPayday: Date? = (index + 1 < sortedPaydays.count) ? sortedPaydays[index + 1] : nil
            
            // Filter bills due between this payday (exclusive) and next payday (inclusive)
            let billsDue: [Bill]
            if let next = nextPayday {
                billsDue = bills.filter { bill in
                    guard let dueDate = bill.dueDate else { return false }
                    return dueDate > payday && dueDate <= next
                }
            } else {
                // If no next payday, consider bills due after this payday only
                billsDue = bills.filter { bill in
                    guard let dueDate = bill.dueDate else { return false }
                    return dueDate > payday
                }
            }
            
            func billsSummary() -> String? {
                guard !billsDue.isEmpty else { return nil }
                let sortedBillsDue = billsDue.sorted { (lhs, rhs) in
                    guard let lhsDate = lhs.dueDate, let rhsDate = rhs.dueDate else { return false }
                    return lhsDate < rhsDate
                }
                let names = sortedBillsDue.compactMap { $0.name ?? nil }
                let totalAmount = sortedBillsDue.reduce(0.0) { $0 + ($1.amount ?? 0.0) }
                let formattedAmount: String
                if totalAmount.truncatingRemainder(dividingBy: 1) == 0 {
                    formattedAmount = "$\(Int(totalAmount))"
                } else {
                    formattedAmount = String(format: "$%.2f", totalAmount)
                }
                return "Upcoming bills: \(names.joined(separator: ", ")) — Total: \(formattedAmount)"
            }
            
            if notifyDayBeforeEnabled,
               let beforeDate = Calendar.current.date(byAdding: .day, value: -1, to: payday) {
                let defaultBody = "Your payday is tomorrow."
                let body = billsSummary() ?? defaultBody
                scheduleNotification(
                    identifier: "paydayBefore_\(payday.timeIntervalSince1970)",
                    date: beforeDate,
                    title: "Payday Tomorrow",
                    body: body
                )
            }
            if notifyDayOfEnabled {
                let defaultBody = "Today is payday!"
                let body = billsSummary() ?? defaultBody
                scheduleNotification(
                    identifier: "paydayOn_\(payday.timeIntervalSince1970)",
                    date: payday,
                    title: "Payday Today",
                    body: body
                )
            }
        }
    }

    func scheduleNotification(identifier: String, date: Date, title: String, body: String) {
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error.localizedDescription)")
            }
        }
    }
}
