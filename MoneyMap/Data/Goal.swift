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
class Goal: Identifiable {
    var id = UUID()
    var name: String?
    var targetAmount: Double
    var deadline: Date
    var amountPerPaycheck: Double?
    var createdDate: Date = Date()
    var imageFileName: String?
    var urls: [URL]?
    
    
    private var priorityWeight: Double? // Allow old data without a value
    var weight: Double {
        get { priorityWeight ?? 1.0 } // Fallback for existing data
        set { priorityWeight = newValue }
    }
    
    // Added later
    var amountSaved: Double = 0
    
    init(_ name: String?, targetAmount: Double, deadline: Date, weight: Double, imageURL: URL?, paydaysUntil: Int) {
        self.name = name
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.weight = weight
        self.imageFileName = imageURL?.lastPathComponent
        self.amountPerPaycheck = targetAmount / Double(paydaysUntil)
    }
    
    var remainingAmount: Double {
        return max(0, targetAmount - amountSaved)
    }
    
    var daysUntilDeadline: Int {
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
    }
    
    func addURL(_ string: String) {
        if let url = URL(string: string) {
            if let urls = self.urls {
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
    func progress() -> Double {
        if targetAmount > 0 {
            return amountSaved / targetAmount
        }
        return 0
    }
    
    private var imageURL: URL? {
        guard let fileName = imageFileName else { return nil }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    func loadImage() -> UIImage? {
        guard let imageURL, FileManager.default.fileExists(atPath: imageURL.path),
              let data = try? Data(contentsOf: imageURL) else { return nil }
        return UIImage(data: data)
    }
    
}
