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
    @Query private var manualSavingsAccounts: [ManualSavingsAccount]
    
    @State private var addingGoal = false
    @State private var editingSavingsBalance = false
    
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

    private var manualSavingsAccount: ManualSavingsAccount? {
        manualSavingsAccounts.first
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
                        Button("Savings Account", systemImage: "banknote") {
                            editingSavingsBalance.toggle()
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
            .sheet(isPresented: $editingSavingsBalance) {
                ManualSavingsBalanceView(
                    goals: goals,
                    nextPayday: paydayManager.nextPayday,
                    initialBalance: manualSavingsAccount?.balanceAmount ?? 0,
                    updatedAt: manualSavingsAccount?.updatedAt,
                    onApply: applySavingsBalance
                )
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
                editingSavingsBalance.toggle()
            } label: {
                MoneyMapActionListRow(
                    title: "Savings Account",
                    detail: manualSavingsDetail,
                    systemImage: "banknote",
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

    private var manualSavingsDetail: String {
        let balance = manualSavingsAccount?.balanceAmount ?? 0
        guard balance > 0 else {
            return "Type the total balance of your off-app savings account and split it across goals."
        }

        return "Manual balance: \(MoneyMapFormatters.currencyString(for: balance))"
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
    
    func applySavingsBalance(_ plan: SavingsBalancePlan) {
        let groupID = UUID()

        for allocation in plan.allocations {
            guard let goal = goals.first(where: { $0.id == allocation.goalID }) else { continue }
            let previousAmountSaved = goal.amountSaved
            goal.amountSaved = allocation.allocatedAmount
            AuditService.logGoalContribution(
                goal: goal,
                previousAmountSaved: previousAmountSaved,
                contributionAmount: allocation.deltaAmount,
                context: modelContext,
                groupID: groupID
            )
        }

        if let account = manualSavingsAccount {
            account.balanceAmount = plan.totalBalance
            account.updatedAt = Date()
        } else {
            modelContext.insert(ManualSavingsAccount(balance: plan.totalBalance))
        }

        try? modelContext.save()
        MoneyMapIntentDonations.donateSavingsSummary()
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

private struct ManualSavingsBalanceView: View {
    let goals: [Goal]
    let nextPayday: Date?
    let initialBalance: Double
    let updatedAt: Date?
    let onApply: (SavingsBalancePlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var balance: Double
    @FocusState private var balanceFocused: Bool

    init(
        goals: [Goal],
        nextPayday: Date?,
        initialBalance: Double,
        updatedAt: Date?,
        onApply: @escaping (SavingsBalancePlan) -> Void
    ) {
        self.goals = goals
        self.nextPayday = nextPayday
        self.initialBalance = initialBalance
        self.updatedAt = updatedAt
        self.onApply = onApply
        _balance = State(initialValue: initialBalance)
    }

    private var plan: SavingsBalancePlan {
        FinancialPlanningEngine.allocateSavingsBalance(
            balance: balance,
            goals: goals,
            nextPayday: nextPayday
        )
    }

    private var canApply: Bool {
        !plan.allocations.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                balanceSection
                allocationSection
                unallocatedSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Savings Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Split") {
                        onApply(plan)
                        dismiss()
                    }
                    .disabled(!canApply)
                }
                if balanceFocused {
                    ToolbarItem(placement: .keyboard) {
                        Spacer()
                    }
                    ToolbarItem(placement: .keyboard) {
                        Button("Done") {
                            balanceFocused = false
                        }
                    }
                }
            }
        }
    }

    private var balanceSection: some View {
        Section {
            TextField("Balance", value: $balance, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .focused($balanceFocused)

            if let updatedAt {
                Label("Last updated \(MoneyMapFormatters.mediumDateString(for: updatedAt))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Manual Balance")
        } footer: {
            Text("Use the total amount currently in the savings account. MoneyMap will reconcile goal totals to this balance.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var allocationSection: some View {
        Section("Goal Split") {
            if goals.filter({ ($0.targetAmount ?? 0) > 0 }).isEmpty {
                MoneyMapEmptyState(
                    title: "No Goals To Split",
                    message: "Add a target amount to at least one goal before splitting savings.",
                    systemImage: "target"
                )
            } else {
                ForEach(plan.allocations, id: \.goalID) { allocation in
                    ManualSavingsAllocationRow(allocation: allocation)
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var unallocatedSection: some View {
        if plan.unallocatedBalance > 0 {
            Section {
                MoneyMapActionListRow(
                    title: "Unassigned Savings",
                    detail: "\(MoneyMapFormatters.currencyString(for: plan.unallocatedBalance)) is left after fully funding your current goals.",
                    systemImage: "tray.full",
                    tint: .blue
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
    }
}

private struct ManualSavingsAllocationRow: View {
    let allocation: SavingsBalanceGoalAllocation

    private var progress: Double {
        guard allocation.targetAmount > 0 else { return 0 }
        return min(max(allocation.allocatedAmount / allocation.targetAmount, 0), 1)
    }

    private var deltaText: String {
        if allocation.deltaAmount > 0 {
            return "Add \(MoneyMapFormatters.currencyString(for: allocation.deltaAmount))"
        }
        if allocation.deltaAmount < 0 {
            return "Remove \(MoneyMapFormatters.currencyString(for: abs(allocation.deltaAmount)))"
        }
        return "No change"
    }

    private var deltaColor: Color {
        if allocation.deltaAmount > 0 {
            return MoneyMapDesign.calmGreen
        }
        if allocation.deltaAmount < 0 {
            return MoneyMapDesign.warningGold
        }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(allocation.goalName)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                MoneyMapMoneyText(
                    amount: allocation.allocatedAmount,
                    font: .body.weight(.semibold),
                    foregroundStyle: .primary
                )
            }

            ProgressView(value: progress)
                .tint(MoneyMapDesign.calmGreen)

            HStack(spacing: 8) {
                Label(deltaText, systemImage: allocation.deltaAmount < 0 ? "minus.circle" : "plus.circle")
                    .foregroundStyle(deltaColor)

                Spacer(minLength: 8)

                Text("\(MoneyMapFormatters.currencyString(for: allocation.remainingAfterAllocation)) left")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))

            if allocation.isBehindSchedule {
                Label("Behind pace", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(MoneyMapDesign.warningGold)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    GoalsView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .modelContainer(container)
    
}
