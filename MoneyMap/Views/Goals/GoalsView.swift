//
//  GoalsView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import SwiftData
import AppIntents


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
    
    private var activeGoals: [Goal] {
        goals.filter { $0.remainingAmount > 0 }
    }

    private var completedGoals: [Goal] {
        goals.filter { $0.remainingAmount <= 0 && (($0.targetAmount ?? 0) > 0) }
    }

    private var totalSaved: Double {
        goals.reduce(0) { $0 + $1.amountSaved }
    }

    private var totalTarget: Double {
        goals.reduce(0) { $0 + ($1.targetAmount ?? 0) }
    }

    private var totalRemaining: Double {
        goals.reduce(0) { $0 + $1.remainingAmount }
    }

    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return min(max(totalSaved / totalTarget, 0), 1)
    }
    
    
    var body: some View {
        NavigationStack {
            List {
                overviewSection

                if paydayManager.nextPayday == nil {
                    paydayTimingSection
                }

                activeGoalsSection
                completedGoalsSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
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
                    Menu("Goal Actions", systemImage: "ellipsis.circle") {
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

    private var overviewSection: some View {
        Section {
            GoalOverviewPanel(
                goalCount: goals.count,
                activeCount: activeGoals.count,
                totalSaved: totalSaved,
                totalRemaining: totalRemaining,
                progress: overallProgress
            )
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var paydayTimingSection: some View {
        Section("Payday Timing") {
            MoneyMapActionListRow(
                title: "Payday not set",
                detail: "Goals still work, but payday pacing and paycheck recommendations get better after you set the next payday.",
                systemImage: "calendar.badge.exclamationmark",
                tint: MoneyMapDesign.warningGold
            )
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var activeGoalsSection: some View {
        Section("Active Goals") {
            if activeGoals.isEmpty {
                MoneyMapEmptyState(
                    title: goals.isEmpty ? "No Goals Yet" : "No Active Goals",
                    message: goals.isEmpty ? "Add a savings goal to track progress toward something specific." : "Completed goals move out of your active list.",
                    systemImage: "target"
                )
            } else {
                ForEach(activeGoals) { goal in
                    goalNavigationLink(goal)
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var completedGoalsSection: some View {
        if !completedGoals.isEmpty {
            Section("Completed") {
                ForEach(completedGoals) { goal in
                    goalNavigationLink(goal)
                }
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                addingSavings.toggle()
            } label: {
                MoneyMapActionListRow(
                    title: "Add Savings",
                    detail: "Distribute a savings amount across active goals by urgency and priority.",
                    systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90",
                    tint: MoneyMapDesign.calmGreen
                )
            }
            .buttonStyle(.plain)

            Button {
                modelContext.insert(Goal.example)
            } label: {
                MoneyMapActionListRow(
                    title: "Add Example Goal",
                    detail: "Create a sample goal to try the goals workflow.",
                    systemImage: "text.badge.star",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)

            if !goals.isEmpty {
                Button(role: .destructive) {
                    showingResetAlert.toggle()
                } label: {
                    MoneyMapActionListRow(
                        title: "Reset Savings",
                        detail: "Set every goal's saved amount back to zero.",
                        systemImage: "trash",
                        tint: MoneyMapDesign.attentionRed
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private func goalNavigationLink(_ goal: Goal) -> some View {
        Button {
            viewingGoal = goal
            MoneyMapIntentDonations.donateOpenGoal(goal)
        } label: {
            GoalRowView(goal: goal)
        }
        .buttonStyle(.plain)
        .userActivity("com.heyjoshsmith.MoneyMap.viewingGoalRow") { activity in
            let entity = GoalEntity(goal)
            activity.title = "Reviewing \(entity.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(goal)
            }
        }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(goal)
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

private struct GoalOverviewPanel: View {
    let goalCount: Int
    let activeCount: Int
    let totalSaved: Double
    let totalRemaining: Double
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goalCount == 1 ? "1 goal tracked" : "\(goalCount) goals tracked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MoneyMapMoneyText(
                        amount: totalSaved,
                        font: .title2.weight(.semibold),
                        foregroundStyle: .primary
                    )
                    Text(activeCount == 1 ? "1 still in progress" : "\(activeCount) still in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "target")
                    .font(.title3)
                    .foregroundStyle(MoneyMapDesign.calmGreen)
                    .frame(width: 30, alignment: .center)
            }

            ProgressView(value: progress)
                .tint(MoneyMapDesign.calmGreen)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                MoneyMapMetricTile(
                    title: "Saved",
                    value: MoneyMapFormatters.currencyString(for: totalSaved),
                    systemImage: "banknote",
                    tint: MoneyMapDesign.calmGreen
                )
                MoneyMapMetricTile(
                    title: "Remaining",
                    value: MoneyMapFormatters.currencyString(for: totalRemaining),
                    systemImage: "dollarsign.circle",
                    tint: .blue
                )
                MoneyMapMetricTile(
                    title: "Progress",
                    value: progress.formatted(.percent.precision(.fractionLength(0))),
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .purple
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    GoalsView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .modelContainer(container)
    
}
