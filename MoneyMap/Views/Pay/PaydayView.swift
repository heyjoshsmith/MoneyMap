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
    @State private var selectedDate = Date()
    @AppStorage("notifyDayBeforeEnabled") private var notifyDayBeforeEnabled: Bool = true
    @AppStorage("notifyDayOfEnabled") private var notifyDayOfEnabled: Bool = true
    @AppStorage("notificationTime") private var notificationTime: Date = {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    @State private var showingTimePicker = false
    
    @Query private var bills: [Bill]

    private var timeString: String {
        notificationTime.formatted(.dateTime.hour().minute())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    if let _ = paydayManager.nextPayday {
                        let paydays = paydayManager.upcomingPaydaysForNextYear()
                        let batched = batchedPaydays(paydays)
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            ForEach(batched) { row in
                                GridRow {
                                    if row.isPriority {
                                        CalendarView(for: row.items[0], priority: true, bonus: row.bonuses[0])
                                            .gridCellColumns(2)
                                    } else {
                                        CalendarView(for: row.items[0], priority: false, bonus: row.bonuses[0])
                                        if row.items.count > 1 {
                                            CalendarView(for: row.items[1], priority: false, bonus: row.bonuses[1])
                                        } else {
                                            Color.clear
                                        }
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                    } else {
                        Text("Please select your next payday")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 10))
                        
                        // Calendar picker for selecting the next payday.
                        DatePicker("Select Next Payday", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                            .padding()
                        
                        Spacer()
                                            
                        Button(action: {
                            paydayManager.savePayday(selectedDate)
                        }) {
                            Label("Set Next Payday", systemImage: "checkmark.circle")
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(gradient: Gradient(colors: [.green, .blue]),
                                                   startPoint: .leading,
                                                   endPoint: .trailing)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Pay")
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Section("Notification Settings") {
                            Toggle("Notify Day Before", isOn: $notifyDayBeforeEnabled)
                            Toggle("Notify on Payday", isOn: $notifyDayOfEnabled)
                            Button("Time: \(timeString)") {
                                showingTimePicker = true
                            }
                        }
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                }
            }
            .onAppear {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                scheduleNotifications(paydayManager.upcomingPaydaysForNextYear())
            }
            .onChange(of: notifyDayBeforeEnabled) {
                scheduleNotifications(paydayManager.upcomingPaydaysForNextYear())
            }
            .onChange(of: notifyDayOfEnabled) {
                scheduleNotifications(paydayManager.upcomingPaydaysForNextYear())
            }
            .onChange(of: notificationTime) {
                scheduleNotifications(paydayManager.upcomingPaydaysForNextYear())
            }
            .popover(isPresented: $showingTimePicker) {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
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

private extension PaydayView {
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
