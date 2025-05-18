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
    public var targetAmount: Double
    public var deadline: Date
    public var amountPerPaycheck: Double?
    public var createdDate: Date = Date()
    public var imageFileName: String?
    public var urls: [URL]?
    
    
    public var priorityWeight: Double? // Allow old data without a value
    public var amountSaved: Double = 0
    
    public var weight: Double {
        get { priorityWeight ?? 1.0 } // Fallback for existing data
        set { priorityWeight = newValue }
    }
    
    public init(_ name: String?, targetAmount: Double, deadline: Date, weight: Double, imageURL: URL?, paydaysUntil: Int) {
        self.name = name
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.weight = weight
        self.imageFileName = imageURL?.lastPathComponent
        self.amountPerPaycheck = targetAmount / Double(paydaysUntil)
    }
    
    public var remainingAmount: Double {
        return max(0, targetAmount - amountSaved)
    }
    
    public var daysUntilDeadline: Int {
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
        if targetAmount > 0 {
            return amountSaved / targetAmount
        }
        return 0
    }
    
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
    
    public func loadImage() -> UIImage? {
        guard let imageURL, FileManager.default.fileExists(atPath: imageURL.path),
              let data = try? Data(contentsOf: imageURL) else { return nil }
        return UIImage(data: data)
    }
    
}

extension Goal {
    
    public static var example: Goal {
        return Goal("Nintendo Switch 2", targetAmount: 500, deadline: .distantFuture, weight: 1, imageURL: nil, paydaysUntil: 5)
    }
    
}
