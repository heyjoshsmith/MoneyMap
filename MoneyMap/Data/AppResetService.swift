//
//  AppResetService.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SwiftData
import UserNotifications

enum AppResetService {
    private static let appGroupSuiteName = "group.com.heyjoshsmith.MoneyMap"
    private static let legacyImagesFolderName = "Images"

    static func removeAllAppData(modelContext: ModelContext) async throws {
        try deleteAllModels(from: modelContext)
        clearStoredPreferences()
        clearNotifications()
        clearSearchIndex()
        removeLegacySharedFiles()
    }

    private static func deleteAllModels(from modelContext: ModelContext) throws {
        for auditEvent in try modelContext.fetch(FetchDescriptor<AuditEvent>()) {
            modelContext.delete(auditEvent)
        }
        for goal in try modelContext.fetch(FetchDescriptor<Goal>()) {
            modelContext.delete(goal)
        }
        for bill in try modelContext.fetch(FetchDescriptor<Bill>()) {
            modelContext.delete(bill)
        }
        for paydayConfig in try modelContext.fetch(FetchDescriptor<PaydayConfig>()) {
            modelContext.delete(paydayConfig)
        }

        // Saving model deletions lets SwiftData propagate the same removals to CloudKit.
        try modelContext.save()
    }

    private static func clearStoredPreferences() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        if let sharedDefaults = UserDefaults(suiteName: appGroupSuiteName) {
            sharedDefaults.removePersistentDomain(forName: appGroupSuiteName)
            sharedDefaults.synchronize()
        }

        PendingRouteStore.clear()
    }

    private static func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private static func clearSearchIndex() {
        SpotlightIndexer.removeAllBillEntries()
    }

    private static func removeLegacySharedFiles() {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName) else {
            return
        }

        let legacyImagesURL = groupURL.appendingPathComponent(legacyImagesFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: legacyImagesURL.path) {
            try? fileManager.removeItem(at: legacyImagesURL)
        }
    }
}
