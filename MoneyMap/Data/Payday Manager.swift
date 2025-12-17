//
//  Payday Manager.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import Foundation
import SwiftData


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
        guard let startOfDay = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: payday) else { return 0 }
        let components = Calendar.current.dateComponents([.day], from: Date(), to: startOfDay)
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
    
    /// Returns an array of all paydays for the next year, starting from the nextPayday.
    func upcomingPaydaysForNextYear() -> [Date] {
        guard let start = nextPayday else { return [] }
        guard let startOfDay = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: start) else { return [] }
        var paydays: [Date] = []
        var current = startOfDay
        let oneYearLater = Calendar.current.date(byAdding: .year, value: 1, to: startOfDay)!
        
        while current <= oneYearLater {
            paydays.append(current)
            current = Calendar.current.date(byAdding: .day, value: 14, to: current)!
        }
        
        return paydays
    }
    
}

// MARK: - Preview Data
struct PreviewDataProvider {
    @MainActor static func createContainer() -> (ModelContainer, PaydayManager) {
        let container = try! ModelContainer(
            for: Goal.self, PaydayConfig.self, Bill.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true) // In-memory store for previews
        )
        let mockContext = container.mainContext
        let paydayManager = PaydayManager(context: mockContext)
        
        // Add sample payday
        let samplePaydayConfig = PaydayConfig(nextPayday: Date().addingTimeInterval(60 * 60 * 24 * 7))
        mockContext.insert(samplePaydayConfig)
        
        // Add sample goals
        let deadline1 = Date().addingTimeInterval(60 * 60 * 24 * 30)
        let sampleGoal1 = Goal("iPhone 17", targetAmount: 1000, deadline: deadline1, weight: 1.0, paydaysUntil: paydayManager.numberOfPaydaysUntil(deadline1))
        
        let deadline2 = Date().addingTimeInterval(60 * 60 * 24 * 60)
        let sampleGoal2 = Goal("Mac Mini", targetAmount: 500, deadline: deadline2, weight: 1.0, paydaysUntil: paydayManager.numberOfPaydaysUntil(deadline2))
        
        
        let endOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
            .addingTimeInterval(60 * 60 * 24 * 32)
        let lastDayOfMonth = Calendar.current.date(byAdding: .day, value: -Calendar.current.component(.day, from: endOfMonth), to: endOfMonth)!
        
        let sampleCards: [Bill] = [
            Bill(
                name: "Apple Card",
                amount: 0,
                dueDate: lastDayOfMonth,
                category: .creditCard,
                recurrenceInterval: 1,
                recurrenceUnit: .month,
                creditCardDetails: CreditCardDetails(creditLimit: 15000, cardBalance: 2500)
            ),
            Bill(
                name: "Chase Sapphire",
                amount: 0,
                dueDate: Calendar.current.date(byAdding: .day, value: -20, to: lastDayOfMonth)!,
                category: .creditCard,
                recurrenceInterval: 1,
                recurrenceUnit: .month,
                creditCardDetails: CreditCardDetails(creditLimit: 12000, cardBalance: 3200)
            ),
            Bill(
                name: "Amex Gold",
                amount: 0,
                dueDate: Calendar.current.date(byAdding: .day, value: -10, to: lastDayOfMonth)!,
                category: .creditCard,
                recurrenceInterval: 1,
                recurrenceUnit: .month,
                creditCardDetails: CreditCardDetails(creditLimit: 9000, cardBalance: 1500)
            ),
            Bill(
                name: "Citi Double Cash",
                amount: 0,
                dueDate: Calendar.current.date(byAdding: .day, value: -5, to: lastDayOfMonth)!,
                category: .creditCard,
                recurrenceInterval: 1,
                recurrenceUnit: .month,
                creditCardDetails: CreditCardDetails(creditLimit: 8000, cardBalance: 650)
            )
        ]
        sampleCards.forEach { mockContext.insert($0) }
        
        mockContext.insert(sampleGoal1)
        mockContext.insert(sampleGoal2)
        try! mockContext.save()
        
        return (container, paydayManager)
    }
}
