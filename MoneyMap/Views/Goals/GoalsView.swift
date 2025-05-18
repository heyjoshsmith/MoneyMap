//
//  GoalsView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import SwiftData
import MoneyMapShared

struct GoalsView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var paydayManager: PaydayManager
    @Query(sort: \Goal.deadline, order: .forward) var goals: [Goal]
    
    @State private var editingPayday = false
    @State private var addingGoal = false
    @State private var addingSavings = false
    @State private var savingsAmount = ""
    @State private var allocation: [Goal: Double] = [:]
    
    @State private var showingResetAlert = false
    
    let listView = false
    
    
    var body: some View {
        NavigationView {
            ZStack {
                
                if listView {
                    GoalsListView()
                } else {
                    GoalsCardView()
                }
                
            }
            .navigationTitle("Goals")
            .onAppear {
                DispatchQueue.main.async {
                    if paydayManager.nextPayday == nil {
                        editingPayday = true
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PaydayView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "ellipsis.circle") {
                        Button("Add Goal", systemImage: "text.badge.star") {
                            addingGoal.toggle()
                        }
                        Button("Add Savings", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90") {
                            addingSavings.toggle()
                        }
                        Divider()
                        Button("Add Example Goal", systemImage: "text.badge.star") {
                            modelContext.insert(Goal.example)
                        }
                        Button("Reset Savings", systemImage: "trash", role: .destructive) {
                            showingResetAlert.toggle()
                        }
                    }
                }
            }
            .sheet(isPresented: $editingPayday) {
                PaydayView()
                    .interactiveDismissDisabled(paydayManager.nextPayday == nil)
            }
            .sheet(isPresented: $addingGoal) {
                NavigationStack {
                    AddGoalView()
                }
            }
            .alert("Add Savings", isPresented: $addingSavings) {
                TextField("$500", text: $savingsAmount)
                Button("Cancel", role: .cancel) {
                    
                }
                Button("Add") {
                    savePaycheckAmount()
                    savingsAmount.removeAll()
                }
            } message: {
                Text("How much money would you like to add to your savings?")
            }
            .alert("Reset Savings", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive) {
                    withAnimation {
                        goals.forEach { goal in
                            goal.amountSaved = 0
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to reset your savings? This action can't be undone.")
            }

        }
    }
    
    func savePaycheckAmount() {
        if let amount = Double(savingsAmount) {
            let allocation = calculateSavingsDistribution(goals: goals, totalPerPaycheck: amount)
            goals.forEach { goal in
                if let allocatedAmount = allocation[goal] {
                    goal.amountSaved += allocatedAmount
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
    
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    GoalsView()
        .environmentObject(paydayManager)
        .modelContainer(container)
    
}
