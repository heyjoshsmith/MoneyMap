//
//  Goal.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI
import SwiftData

// MARK: - Model (SwiftData)
@Model
public class Goal: Identifiable {
    public var id = UUID()
    public var name: String?
    public var targetAmount: Double?
    public var deadline: Date?
    public var amountPerPaycheck: Double?
    public var createdDate: Date = Date()
    public var urls: [URL]?
    // Store image data for CloudKit syncing and general use
    public var imageData: Data?
    
    @available(*, deprecated, message: "Use imageData instead. imageFileName is only for legacy migration.")
    public var imageFileName: String?

    
    public var priorityWeight: Double? // Allow old data without a value
    public var amountSaved: Double = 0
    
    public var weight: Double {
        get { priorityWeight ?? 1.0 } // Fallback for existing data
        set { priorityWeight = newValue }
    }
    
    public init(_ name: String?, targetAmount: Double?, deadline: Date?, weight: Double, paydaysUntil: Int?, imageData: Data? = nil) {
        self.name = name
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.weight = weight
        if let targetAmount = targetAmount, let paydaysUntil = paydaysUntil, paydaysUntil != 0 {
            self.amountPerPaycheck = targetAmount / Double(paydaysUntil)
        } else {
            self.amountPerPaycheck = nil
        }
        if let imageData = imageData {
            self.imageData = imageData
        } else {
            self.imageData = nil
        }
    }
    
    public var remainingAmount: Double {
        guard let target = targetAmount else { return 0 }
        return max(0, target - amountSaved)
    }
    
    public var daysUntilDeadline: Int {
        guard let deadline = deadline else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
    }
    
    public func addURL(_ string: String) {
        if let url = URL(string: string) {
            if self.urls != nil {
                self.urls?.append(url)
            } else {
                self.urls = [url]
            }
        }
    }
    
    
    
    
    // Classic
    
    // TODO: Add payday info
    func getExpectedAmount(for paydays: Int) -> Double {
        if (paydays == 0) { return 0 }
        return (amountPerPaycheck ?? 0) * Double(paydays)
    }
    
    /// Progress toward the goal (0 to 1).
    public func progress() -> Double {
        guard let target = targetAmount, target > 0 else { return 0 }
        return amountSaved / target
    }
    
    @available(*, deprecated, message: "Use imageData/uiImage instead. imageURL is only for legacy migration.")
    public var imageURL: URL? {
        guard let fileName = imageFileName else { return nil }
        // Point to the shared App Group container
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")?
            .appendingPathComponent("Images", isDirectory: true) else {
            return nil
        }
        return groupURL.appendingPathComponent(fileName)
    }

    /// Returns the loaded UIImage for this goal, using imageData if available.
    public var uiImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    /// Loads the image for this goal. Returns the image from imageData if present,
    /// otherwise attempts to load from imageURL (for migrated/legacy goals).
    /// If migration from file is successful, imageData is updated.
    @available(*, deprecated, message: "Use imageData/uiImage instead. imageURL is only for legacy migration.")
    public func loadImage() -> UIImage? {
        if let data = imageData {
            return UIImage(data: data)
        } else if let imageURL,
                  FileManager.default.fileExists(atPath: imageURL.path),
                  let data = try? Data(contentsOf: imageURL) {
            // Migrate legacy file-based image to imageData
            self.imageData = data
            return UIImage(data: data)
        }
        return nil
    }
    
}

extension Goal {
    
    public static var example: Goal {
        return Goal("Nintendo Switch 2", targetAmount: 500, deadline: .distantFuture, weight: 1, paydaysUntil: 5)
    }
    
}
