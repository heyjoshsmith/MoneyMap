//
//  Settings.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/19/25.
//

import SwiftUI

struct Settings: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Notifications") {
                    ScheduledNotificationsView()
                }
            }
            .navigationTitle("Settings")
        }
    }
}

import UserNotifications

struct ScheduledNotificationsView: View {
    @State private var notifications: [UNNotificationRequest] = []

    var body: some View {
        List(notifications, id: \.identifier) { request in
            VStack(alignment: .leading) {
                Text(request.content.title).bold()
                Text(request.content.body)
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTriggerDate = trigger.nextTriggerDate() {
                    Text("Scheduled for: \(nextTriggerDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear(perform: fetchNotifications)
        .navigationTitle("Scheduled Notifications")
    }

    func fetchNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.notifications = requests
            }
        }
    }
}

#Preview {
    Settings()
}
