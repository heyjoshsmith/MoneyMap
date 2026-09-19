#if DEBUG && targetEnvironment(simulator)
import SwiftData
import Foundation

/// Deterministic simulator-only data for visual QA. Never connects a bank or writes to iCloud.
@MainActor enum WatchPreviewData {
    static func make() throws -> ModelContainer {
        let container = MoneyMapSharedContainerFactory.makeInMemory(fallbackReason: "Simulator preview")
        let context = container.mainContext
        let payday = PaydayConfig(nextPayday: Calendar.current.date(byAdding: .day, value: 4, to: .now))
        payday.amountPerPayday = 2450
        context.insert(payday)
        context.insert(Bill(name: "Electric", amount: 85, dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now), category: .utilities, recurrenceInterval: 1, recurrenceUnit: .month))
        context.insert(Bill(name: "Internet", amount: 65, dueDate: Calendar.current.date(byAdding: .day, value: -2, to: .now), category: .internet, recurrenceInterval: 1, recurrenceUnit: .month))
        context.insert(Bill(name: "Everyday Card", amount: 75, dueDate: Calendar.current.date(byAdding: .day, value: 6, to: .now), category: .creditCard, recurrenceInterval: 1, recurrenceUnit: .month, creditCardDetails: CreditCardDetails(creditLimit: 5000, cardBalance: 850)))
        let goal = Goal("Weekend Away", targetAmount: 1000, deadline: Calendar.current.date(byAdding: .month, value: 2, to: .now), weight: 1, paydaysUntil: 4)
        goal.totalSavedAmount = 640
        context.insert(goal)
        context.insert(ManualSavingsAccount(name: "Savings", balance: 1800))
        try context.save()
        return container
    }
}
#endif
