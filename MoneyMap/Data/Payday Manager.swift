//
//  Payday Manager.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import Foundation
import SwiftData

@Model
class PaydayConfig {
    var nextPayday: Date?
    var amountPerPayday: Double?
    var savingsPerPaycheck: Double?
    
    private var storedStrategy: SaveStrategy? // Allow old data without a value
    var strategy: SaveStrategy {
        get { storedStrategy ?? SaveStrategy.oneItem } // Fallback for existing data
        set { storedStrategy = newValue }
    }
    
    init(nextPayday: Date?, strategy: SaveStrategy = .oneItem) {
        self.nextPayday = nextPayday
        self.strategy = strategy
    }
    
    
}

enum SaveStrategy: String, Codable, CaseIterable, Identifiable {
    case oneItem, allItems
    var id: String { rawValue }
}

// MARK: - Payday Manager
class PaydayManager: ObservableObject {
    
    @Published var nextPayday: Date?
    @Published var strategy: SaveStrategy?
    private var context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
        loadPayday()
    }
    
    func savePayday(_ date: Date) {
        nextPayday = date
        let paydayConfig = PaydayConfig(nextPayday: date)
        context.insert(paydayConfig)
        
        do {
            try context.save()
        } catch {
            print("Error saving payday:", error)
        }
    }
    
    private func loadPayday() {
        let request = FetchDescriptor<PaydayConfig>()
        
        if let savedPaydayConfig = try? context.fetch(request).first {
            var nextPayday = savedPaydayConfig.nextPayday ?? Date()
            let today = Date()
            
            // Keep advancing by 14 days if the stored payday is in the past
            while nextPayday < today {
                nextPayday = Calendar.current.date(byAdding: .day, value: 14, to: nextPayday)!
            }
            
            // Update `nextPayday` in the app
            self.nextPayday = nextPayday
            self.strategy = savedPaydayConfig.strategy
            
            // Save the new payday to SwiftData
            savedPaydayConfig.nextPayday = nextPayday
            do {
                try context.save()
            } catch {
                print("Error saving updated payday: \(error)")
            }
        } else {
            // No stored payday exists yet, keep `nextPayday` nil (until user selects one)
            self.nextPayday = nil
        }
    }
    
    /// Returns the number of paydays between the next payday and the specified end date.
    func numberOfPaydaysUntil(_ endDate: Date) -> Int {
        guard let start = nextPayday else { return 0 }
        var count = 0
        var current = start
        while current <= endDate {
            count += 1
            current = Calendar.current.date(byAdding: .day, value: 14, to: current)!
        }
        return count
    }
    
    /// Returns the number of days remaining until the next payday.
    func daysUntilNextPayday() -> Int {
        guard let payday = nextPayday else { return 0 }
        let components = Calendar.current.dateComponents([.day], from: Date(), to: payday)
        return components.day ?? 0
    }
    
    func paydaysSince(_ startDate: Date) -> Int {
        let today = Date()
        
        // Ensure the startDate is in the past
        guard startDate <= today else { return 0 }
        
        var paydayCount = 0
        var currentPayday = startDate
        
        // Keep adding 14 days to the payday count until reaching today
        while currentPayday <= today {
            paydayCount += 1
            currentPayday = Calendar.current.date(byAdding: .day, value: 14, to: currentPayday)!
        }
        
        return paydayCount
    }
    
}

// MARK: - Preview Data
struct PreviewDataProvider {
    @MainActor static func createContainer() -> (ModelContainer, PaydayManager) {
        let container = try! ModelContainer(
            for: Goal.self, PaydayConfig.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true) // In-memory store for previews
        )
        let mockContext = container.mainContext
        let paydayManager = PaydayManager(context: mockContext)
        
        // Add sample payday
        let samplePaydayConfig = PaydayConfig(nextPayday: Date().addingTimeInterval(60 * 60 * 24 * 7))
        mockContext.insert(samplePaydayConfig)
        
        // Add sample goals
        let deadline1 = Date().addingTimeInterval(60 * 60 * 24 * 30)
        let sampleGoal1 = Goal("iPhone 17", targetAmount: 1000, deadline: deadline1, weight: 1.0, imageURL: nil, paydaysUntil: paydayManager.numberOfPaydaysUntil(deadline1))
        let deadline2 = Date().addingTimeInterval(60 * 60 * 24 * 60)
        let sampleGoal2 = Goal("Mac Mini", targetAmount: 500, deadline: deadline2, weight: 1.0, imageURL: nil, paydaysUntil: paydayManager.numberOfPaydaysUntil(deadline2))
        mockContext.insert(sampleGoal1)
        mockContext.insert(sampleGoal2)
        
        return (container, paydayManager)
    }
}
