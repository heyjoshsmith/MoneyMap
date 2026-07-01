//
//  GoalsView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import SwiftData


struct GoalsView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject var paydayManager: PaydayManager
    @Query(sort: \Goal.deadline, order: .forward) var goals: [Goal]
    
    @State private var addingGoal = false
    @State private var addingSavings = false
    @State private var savingsAmount = ""
    @State private var allocation: [Goal: Double] = [:]
    
    @State private var showingResetAlert = false
    @State private var viewingGoal: Goal?
    
    let listView = false
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                if listView {
                    GoalsListView()
                } else {
                    GoalsCardView()
                }
                
            }
            .navigationDestination(item: $viewingGoal) { goal in
                GoalDetailView(goal)
            }
            .navigationTitle("Goals")
            .onAppear {
                routeToRequestedGoalIfNeeded()
            }
            .onChange(of: deepLinkManager.requestedGoalID) { _, _ in
                routeToRequestedGoalIfNeeded()
            }
            .onChange(of: goals.count) { _, _ in
                routeToRequestedGoalIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Goal", systemImage: "plus") {
                        addingGoal.toggle()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "ellipsis.circle") {
                        
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
            MoneyMapIntentDonations.donateSavingsSummary()
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

    func routeToRequestedGoalIfNeeded() {
        guard let requestedGoalID = deepLinkManager.requestedGoalID,
              let targetGoal = goals.first(where: { $0.id == requestedGoalID }) else {
            return
        }
        viewingGoal = targetGoal
        deepLinkManager.requestedGoalID = nil
    }
    
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    GoalsView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .modelContainer(container)
    
}
