//
//  Settings.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/19/25.
//

import SwiftUI
import UserNotifications
import SwiftData
import CloudKit

struct Settings: View {
    @State private var showDeleteAllDataConfirmation = false
    @State private var isDeletingAllData = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
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
            // 1. Delete all SwiftData models
            for goal in try modelContext.fetch(FetchDescriptor<Goal>()) {
                modelContext.delete(goal)
            }
            for bill in try modelContext.fetch(FetchDescriptor<Bill>()) {
                modelContext.delete(bill)
            }
            for paydayConfig in try modelContext.fetch(FetchDescriptor<PaydayConfig>()) {
                modelContext.delete(paydayConfig)
            }
            try modelContext.save()

            // 2. Remove all UserDefaults for known keys
            let keys = ["notifyDayBeforeEnabled", "notifyDayOfEnabled", "notificationTime"]
            let defaults = UserDefaults(suiteName: "group.com.heyjoshsmith.MoneyMap") ?? .standard
            for key in keys { defaults.removeObject(forKey: key) }
            defaults.synchronize()

            // 3. Remove all files in shared app group container
            let fm = FileManager.default
            if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") {
                let contents = try? fm.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil)
                contents?.forEach { try? fm.removeItem(at: $0) }
            }
            // 4. Remove iCloud/CloudKit records
            let privateDB = CKContainer.default().privateCloudDatabase
            do {
                // Fetch all record zones
                let zonesResult = try await privateDB.allRecordZones()
                for _ in zonesResult {
                    // Query all records in each zone
                    let query = CKQuery(recordType: "__default__", predicate: NSPredicate(value: true))
                    let op = CKQueryOperation(query: query)
                    var recordIDs: [CKRecord.ID] = []
                    op.recordMatchedBlock = { recordID, result in
                        switch result {
                        case .success(let record):
                            recordIDs.append(record.recordID)
                        case .failure(let error):
                            print("Error fetching record \(recordID): \(error)")
                        }
                    }
                    let _: Void = await withCheckedContinuation { continuation in
                        op.queryResultBlock = { _ in continuation.resume() }
                        privateDB.add(op)
                    }
                    if !recordIDs.isEmpty {
                        let deleteOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
                        deleteOp.savePolicy = .ifServerRecordUnchanged
                        privateDB.add(deleteOp)
                    }
                }
            } catch {
                print("CloudKit data removal failed: \(error)")
            }
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
