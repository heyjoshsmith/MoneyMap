//
//  Settings.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/19/25.
//

import SwiftUI
import UserNotifications
import SwiftData

struct Settings: View {
    @State private var showDeleteAllDataConfirmation = false
    @State private var isDeletingAllData = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Activity") {
                    ActivityFeedView(title: "Activity")
                }
                NavigationLink("Smart Features") {
                    SmartFeaturesGuideView()
                }
                NavigationLink("What's New") {
                    WhatsNewView(releases: WhatsNewRepository.releases, onDone: nil)
                }
                NavigationLink("Notifications") {
                    ScheduledNotificationsView()
                }
                Section {
                    Button(role: .destructive, action: { showDeleteAllDataConfirmation = true }) {
                        Label("Remove All Data", systemImage: "trash")
                    }
                    .disabled(isDeletingAllData)
                    .confirmationDialog("Are you sure you want to permanently remove ALL app data from this device and iCloud? This cannot be undone.", isPresented: $showDeleteAllDataConfirmation, titleVisibility: .visible) {
                        Button("Remove All Data", role: .destructive) {
                            Task { await removeAllAppData() }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
}

extension Settings {
    func removeAllAppData() async {
        isDeletingAllData = true
        defer { isDeletingAllData = false }
        do {
            try await AppResetService.removeAllAppData(modelContext: modelContext)
        } catch {
            print("Failed to remove all app data: \(error)")
        }
    }
}

struct ScheduledNotificationsView: View {
    @State private var notifications: [UNNotificationRequest] = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Remove All", systemImage: "trash")
                }
                .disabled(notifications.isEmpty || isDeleting)
                .confirmationDialog("Are you sure you want to remove all scheduled notifications? This action cannot be undone.", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("Remove All", role: .destructive) {
                        removeAllNotifications()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    func fetchNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.notifications = requests
            }
        }
    }

    func removeAllNotifications() {
        isDeleting = true
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // Wait a bit to let the system update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            fetchNotifications()
            isDeleting = false
        }
    }
}

#Preview {
    Settings()
}
