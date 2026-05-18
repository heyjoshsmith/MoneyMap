//
//  Payday.swift
//  AddMoneyMap
//
//  Created by Josh Smith on 7/17/25.
//

import Foundation
import SwiftData

// Diagnostic utility: Call from your app/extension to print and optionally delete the SwiftData store.
func deleteAndPrintStoreURL() {
    let appGroupId = "group.com.heyjoshsmith.MoneyMap"
    let fileNameBase = "shared.sqlite"
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
        print("[SwiftData Diagnostic] Could not find app group container.")
        return
    }
    let storeURL = containerURL.appendingPathComponent(fileNameBase)
    print("[SwiftData Diagnostic] storeURL: \(storeURL.path)")
    // Try deleting the base, -shm, and -wal files
    let paths = [storeURL,
                 storeURL.appendingPathExtension("shm"),
                 storeURL.appendingPathExtension("wal")]
    for url in paths {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                print("[SwiftData Diagnostic] Deleted: \(url.lastPathComponent)")
            } catch {
                print("[SwiftData Diagnostic] Failed to delete \(url.lastPathComponent): \(error)")
            }
        } else {
            print("[SwiftData Diagnostic] Not found: \(url.lastPathComponent)")
        }
    }
}

// Usage: In either your app or extension, temporarily call `deleteAndPrintStoreURL()` (e.g. from AppDelegate, SceneDelegate, or inside a SwiftUI button or .onAppear for testing).

@Model
public class PaydayConfig {
    public var nextPayday: Date?
    public var amountPerPayday: Double?
    public var savingsPerPaycheck: Double?
    
    private var storedStrategy: SaveStrategy? // Allow old data without a value
    public var strategy: SaveStrategy {
        get { storedStrategy ?? SaveStrategy.oneItem } // Fallback for existing data
        set { storedStrategy = newValue }
    }
    
    public init(nextPayday: Date?, strategy: SaveStrategy = .oneItem) {
        self.nextPayday = nextPayday
        self.strategy = strategy
    }
    
}

public enum SaveStrategy: String, Codable, CaseIterable, Identifiable {
    case oneItem, allItems
    public var id: String { rawValue }
}
