//
//  SavingsView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import SwiftData

struct SavingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @Query private var paydayConfig: [PaydayConfig] // Assuming only one config exists
    
    @State private var savingsPerPaycheck: String = ""
    @State private var allocation: [Goal: Double] = [:]
    @FocusState private var focused: Bool
    
    var body: some View {
        NavigationStack {
            List {
                
                Section("Savings per paycheck") {
                    TextField("Savings per paycheck", text: $savingsPerPaycheck)
                        .keyboardType(.numberPad)
                        .focused($focused)
                }
                
                Section("Goals") {
                    ForEach(goals) { goal in
                        VStack(alignment: .leading) {
                            Text(goal.name ?? "Goal").font(.headline)
                            Text("Saved: $\(goal.amountSaved, specifier: "%.2f") / $\(goal.targetAmount, specifier: "%.2f")")
                                .font(.subheadline)
                            if let allocated = allocation[goal] {
                                Text("Next Paycheck: $\(allocated, specifier: "%.2f")")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Savings")
            .onAppear {
                loadPaycheckAmount()
                if let amount = Double(savingsPerPaycheck) {
                    allocation = calculateSavingsDistribution(goals: goals, totalPerPaycheck: amount)
                }
            }
            .toolbar {
                if focused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            focused = false
                            savePaycheckAmount()
                        }
                    }
                }
            }
        }
    }
    
    func calculateSavingsDistribution(goals: [Goal], totalPerPaycheck: Double) -> [Goal: Double] {
        let filteredGoals = goals.filter { $0.remainingAmount > 0 } // Ignore fully saved goals
        guard !filteredGoals.isEmpty else { return [:] }
        
        let weightedGoals = filteredGoals.map { goal -> (Goal, Double) in
            let urgencyFactor = goal.daysUntilDeadline > 0 ? 1.0 / Double(goal.daysUntilDeadline) : 1.0
            let weightedValue = urgencyFactor * goal.weight
            return (goal, weightedValue)
        }
        
        let totalWeight = weightedGoals.reduce(0) { $0 + $1.1 }
        
        var allocation: [Goal: Double] = [:]
        for (goal, weight) in weightedGoals {
            let percentage = weight / totalWeight
            allocation[goal] = min(goal.remainingAmount, percentage * totalPerPaycheck)
        }
        
        return allocation
    }
    
    func loadPaycheckAmount() {
        if let config = paydayConfig.first {
            savingsPerPaycheck = String(format: "%.2f", config.savingsPerPaycheck ?? 0)
        }
    }
    
    func savePaycheckAmount() {
        if let amount = Double(savingsPerPaycheck) {
            if let config = paydayConfig.first {
                print("Saving Paycheck Amount: \(savingsPerPaycheck)")
                config.savingsPerPaycheck = amount
                allocation = calculateSavingsDistribution(goals: goals, totalPerPaycheck: amount)
            } else {
                print("No payday config found to save to.")
            }
        }
    }
}


#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    SavingsView()
        .environmentObject(paydayManager)
        .modelContainer(container)
    
}
