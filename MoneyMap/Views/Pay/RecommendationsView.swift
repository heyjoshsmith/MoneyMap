//
//  RecommendationsView.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import SwiftUI
import SwiftData
import TipKit
import FoundationModels

struct RecommendationsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var paydayManager: PaydayManager
    @Query(sort: \Goal.deadline, order: .forward) private var goals: [Goal]
    @Query private var bills: [Bill]
    @Query private var paydayConfigs: [PaydayConfig]
    @AppStorage("hasSeenRecommendationsWelcome") private var hasSeenRecommendationsWelcome = false

    @State private var availableCash: Double = 0
    @State private var payoffStrategy: CreditCardPayoffStrategy = RecommendationPreferencesStore.cardStrategy
    @State private var allocationStrategy: PaycheckAllocationStrategy = RecommendationPreferencesStore.paycheckStrategy
    @State private var didApplyGoalPlan = false
    @State private var didApplyCardPlan = false
    @State private var showingWelcome = false
    @State private var generatedExplanation: String?
    @State private var explanationError: String?
    @State private var isGeneratingExplanation = false
    @FocusState private var amountFieldFocused: Bool

    private var creditCards: [Bill] {
        bills.filter { $0.category == .creditCard }
    }

    private var plan: PaycheckRecommendationPlan {
        FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            allocationStrategy: allocationStrategy,
            payoffStrategy: payoffStrategy
        )
    }

    private var scenarios: [RecommendationScenario] {
        FinancialPlanningEngine.scenarioPlans(
            baseAvailableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            allocationStrategy: allocationStrategy,
            payoffStrategy: payoffStrategy
        )
    }

    private var digest: RecommendationDigest {
        FinancialPlanningEngine.digest(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            allocationStrategy: allocationStrategy,
            payoffStrategy: payoffStrategy
        )
    }

    private var modelAvailability: SystemLanguageModel.Availability {
        RecommendationPlanExplainer.model.availability
    }

    private var availabilityMessage: String? {
        RecommendationPlanExplainer.availabilityMessage(for: modelAvailability)
    }

    private var cardPaymentTotal: Double {
        plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }
    }

    private var goalContributionTotal: Double {
        plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }
    }

    var body: some View {
        List {
            overviewSection
            moneySection
            strategySection
            nextActionsSection
            beforePaydaySection
            scenarioSection
            cardPaymentSection
            goalContributionSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingWelcome = true
                } label: {
                    Label("How It Works", systemImage: "questionmark.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    amountFieldFocused = false
                }
            }
        }
        .sheet(isPresented: $showingWelcome) {
            RecommendationsWelcomeSheet(
                hasPayday: paydayManager.nextPayday != nil,
                hasCreditCards: !creditCards.isEmpty,
                hasGoals: !goals.isEmpty
            ) {
                hasSeenRecommendationsWelcome = true
                showingWelcome = false
            }
        }
        .onAppear {
            if availableCash == 0 {
                availableCash = paydayConfigs.first?.amountPerPayday ?? 0
            }
            if !hasSeenRecommendationsWelcome {
                showingWelcome = true
            }
        }
        .onChange(of: plan) { _, _ in
            clearExplanation()
        }
        .onChange(of: availableCash) { _, newValue in
            guard let paydayConfig = paydayConfigs.first else { return }
            paydayConfig.amountPerPayday = newValue > 0 ? newValue : nil
            try? modelContext.save()
            didApplyGoalPlan = false
            didApplyCardPlan = false
            clearExplanation()
        }
        .onChange(of: payoffStrategy) { _, newValue in
            RecommendationPreferencesStore.cardStrategy = newValue
            didApplyGoalPlan = false
            didApplyCardPlan = false
            clearExplanation()
        }
        .onChange(of: allocationStrategy) { _, newValue in
            RecommendationPreferencesStore.paycheckStrategy = newValue
            didApplyGoalPlan = false
            didApplyCardPlan = false
            clearExplanation()
        }
    }

    private var overviewSection: some View {
        Section {
            PaycheckPlanOverviewPanel(
                totalAvailable: plan.totalAvailable,
                cardPaymentTotal: cardPaymentTotal,
                goalContributionTotal: goalContributionTotal,
                unallocatedCash: plan.unallocatedCash,
                summary: plan.summary,
                nextPayday: paydayManager.nextPayday,
                daysUntilNextPayday: paydayManager.nextPayday == nil ? nil : paydayManager.daysUntilNextPayday()
            )
        } header: {
            Text("Paycheck Plan")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var moneySection: some View {
        Section("Money To Plan") {
            TextField("Amount Available For Goals And Cards", value: $availableCash, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .focused($amountFieldFocused)

            Text("Only include money you want to put toward cards and goals right now.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let nextPayday = paydayManager.nextPayday {
                MoneyMapSummaryRow(
                    title: "Next Payday",
                    value: MoneyMapFormatters.mediumDateString(for: nextPayday),
                    detail: "\(paydayManager.daysUntilNextPayday()) day\(paydayManager.daysUntilNextPayday() == 1 ? "" : "s") away",
                    systemImage: "calendar"
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var strategySection: some View {
        Section("Strategy") {
            Picker("Card Payoff", selection: $payoffStrategy) {
                ForEach(CreditCardPayoffStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            Text(payoffStrategy.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Paycheck Plan", selection: $allocationStrategy) {
                ForEach(PaycheckAllocationStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            Text(allocationStrategy.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            TipView(RecommendationStrategiesTip())
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var nextActionsSection: some View {
        Section("Next Actions") {
            if !plan.creditCardPayments.isEmpty {
                Button {
                    applyCardPlan()
                } label: {
                    MoneyMapActionListRow(
                        title: didApplyCardPlan ? "Applied Card Plan" : "Apply Card Payments",
                        detail: "\(MoneyMapFormatters.currencyString(for: cardPaymentTotal)) across \(plan.creditCardPayments.count) card\(plan.creditCardPayments.count == 1 ? "" : "s")",
                        systemImage: didApplyCardPlan ? "checkmark.circle.fill" : "creditcard",
                        tint: didApplyCardPlan ? .green : .blue
                    )
                }
                .buttonStyle(.plain)
                .disabled(didApplyCardPlan)
            }

            if !plan.goalContributions.isEmpty {
                Button {
                    applyGoalPlan()
                } label: {
                    MoneyMapActionListRow(
                        title: didApplyGoalPlan ? "Applied Goal Plan" : "Apply Goal Contributions",
                        detail: "\(MoneyMapFormatters.currencyString(for: goalContributionTotal)) across \(plan.goalContributions.count) goal\(plan.goalContributions.count == 1 ? "" : "s")",
                        systemImage: didApplyGoalPlan ? "checkmark.circle.fill" : "target",
                        tint: didApplyGoalPlan ? .green : MoneyMapDesign.calmGreen
                    )
                }
                .buttonStyle(.plain)
                .disabled(didApplyGoalPlan)
            }

            Button {
                Task {
                    await generateExplanation()
                }
            } label: {
                MoneyMapActionListRow(
                    title: explanationActionTitle,
                    detail: explanationActionDetail,
                    systemImage: "sparkles",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingExplanation || availabilityMessage != nil)

            if let generatedExplanation, !generatedExplanation.isEmpty {
                Text(generatedExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            if let explanationError {
                Text(explanationError)
                    .font(.caption)
                    .foregroundStyle(MoneyMapDesign.attentionRed)
            }

            TipView(RecommendationApplyTip())
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var beforePaydaySection: some View {
        Section("Before Payday") {
            MoneyMapSummaryRow(
                title: "Upcoming Bills",
                value: "\(digest.upcomingBillCount)",
                detail: paydayManager.nextPayday == nil ? "Set payday for better timing" : "Due before your next payday",
                systemImage: "calendar.badge.exclamationmark",
                tint: digest.upcomingBillCount > 0 ? MoneyMapDesign.warningGold : .secondary
            )

            MoneyMapSummaryRow(
                title: "Behind Goals",
                value: "\(digest.behindGoalCount)",
                detail: digest.behindGoalCount == 0 ? "No goal shortfalls detected" : "Need extra attention this cycle",
                systemImage: "target",
                tint: digest.behindGoalCount > 0 ? .orange : MoneyMapDesign.calmGreen
            )

            if let cardName = digest.topCardName {
                MoneyMapActionListRow(
                    title: "Top Card Action",
                    detail: cardName,
                    systemImage: "creditcard",
                    tint: .blue
                )
            }

            if let goalName = digest.topGoalName {
                MoneyMapActionListRow(
                    title: "Top Goal Action",
                    detail: goalName,
                    systemImage: "target",
                    tint: MoneyMapDesign.calmGreen
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var scenarioSection: some View {
        Section("Scenario Compare") {
            ForEach(scenarios) { scenario in
                RecommendationScenarioRow(scenario: scenario)
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var cardPaymentSection: some View {
        Section("Card Payments") {
            if plan.creditCardPayments.isEmpty {
                MoneyMapEmptyState(
                    title: "No Card Plan Yet",
                    message: "Add credit cards or increase the money available to plan.",
                    systemImage: "creditcard"
                )
            } else {
                ForEach(plan.creditCardPayments, id: \.billID) { recommendation in
                    CardPaymentRecommendationRow(recommendation: recommendation)
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var goalContributionSection: some View {
        Section("Goal Contributions") {
            if plan.goalContributions.isEmpty {
                MoneyMapEmptyState(
                    title: "No Goal Plan Yet",
                    message: "Add goals or increase the money available to plan.",
                    systemImage: "target"
                )
            } else {
                ForEach(plan.goalContributions, id: \.goalID) { insight in
                    GoalContributionRecommendationRow(insight: insight)
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var explanationActionTitle: String {
        if isGeneratingExplanation {
            return "Explaining Plan"
        }

        if generatedExplanation == nil {
            return "Explain This Plan"
        }

        return "Refresh Explanation"
    }

    private var explanationActionDetail: String {
        if let availabilityMessage {
            return availabilityMessage
        }

        return "Use Apple Intelligence to explain the recommendation."
    }

    private func applyGoalPlan() {
        let groupID = UUID()
        for insight in plan.goalContributions {
            guard let goal = goals.first(where: { $0.id == insight.goalID }) else { continue }
            let previousAmountSaved = goal.amountSaved
            goal.amountSaved += insight.recommendedContribution
            AuditService.logGoalContribution(
                goal: goal,
                previousAmountSaved: previousAmountSaved,
                contributionAmount: insight.recommendedContribution,
                context: modelContext,
                source: .recommendations,
                groupID: groupID
            )
        }
        let totalAmount = plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }
        AuditService.logRecommendationBatch(cardCount: 0, goalCount: plan.goalContributions.count, totalAmount: totalAmount, context: modelContext, groupID: groupID)
        try? modelContext.save()
        MoneyMapIntentDonations.donatePaycheckPlan(availableCash: availableCash)
        didApplyGoalPlan = true
    }

    private func applyCardPlan() {
        let groupID = UUID()
        for recommendation in plan.creditCardPayments {
            guard let bill = bills.first(where: { $0.id == recommendation.billID }) else { continue }
            let previousBalance = bill.creditCardDetails?.cardBalance
            let previousDatePaid = bill.datePaid
            let previousDueDate = bill.dueDate
            let previousStatus = bill.status
            bill.makePayment(of: recommendation.recommendedPayment)
            AuditService.logBillPayment(
                bill: bill,
                previousBalance: previousBalance,
                previousDatePaid: previousDatePaid,
                previousDueDate: previousDueDate,
                previousStatus: previousStatus,
                amount: recommendation.recommendedPayment,
                context: modelContext,
                source: .recommendations,
                groupID: groupID
            )
        }
        let totalAmount = plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }
        AuditService.logRecommendationBatch(cardCount: plan.creditCardPayments.count, goalCount: 0, totalAmount: totalAmount, context: modelContext, groupID: groupID)
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
        MoneyMapIntentDonations.donatePaycheckPlan(availableCash: availableCash)
        didApplyCardPlan = true
    }

    @MainActor
    private func generateExplanation() async {
        guard availabilityMessage == nil else { return }
        isGeneratingExplanation = true
        explanationError = nil

        do {
            generatedExplanation = try await RecommendationPlanExplainer.explain(
                plan: plan,
                digest: digest,
                nextPayday: paydayManager.nextPayday
            )
        } catch {
            explanationError = "MoneyMap couldn't generate an explanation right now."
        }

        isGeneratingExplanation = false
    }

    private func clearExplanation() {
        generatedExplanation = nil
        explanationError = nil
    }
}

private struct PaycheckPlanOverviewPanel: View {
    let totalAvailable: Double
    let cardPaymentTotal: Double
    let goalContributionTotal: Double
    let unallocatedCash: Double
    let summary: String
    let nextPayday: Date?
    let daysUntilNextPayday: Int?

    private var paydayDetail: String {
        guard let nextPayday, let daysUntilNextPayday else {
            return "Set payday for better timing"
        }

        let dayLabel = daysUntilNextPayday == 1 ? "day" : "days"
        return "\(MoneyMapFormatters.mediumDateString(for: nextPayday)) - \(daysUntilNextPayday) \(dayLabel) away"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready to move")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MoneyMapMoneyText(
                        amount: totalAvailable,
                        font: .title2.weight(.semibold),
                        foregroundStyle: .primary
                    )
                    Text(paydayDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 30, alignment: .center)
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: metricColumns, spacing: 10) {
                MoneyMapMetricTile(
                    title: "Cards",
                    value: MoneyMapFormatters.currencyString(for: cardPaymentTotal),
                    systemImage: "creditcard",
                    tint: .blue
                )
                MoneyMapMetricTile(
                    title: "Goals",
                    value: MoneyMapFormatters.currencyString(for: goalContributionTotal),
                    systemImage: "target",
                    tint: MoneyMapDesign.calmGreen
                )
                MoneyMapMetricTile(
                    title: "Unallocated",
                    value: MoneyMapFormatters.currencyString(for: unallocatedCash),
                    systemImage: "dollarsign.circle",
                    tint: unallocatedCash > 0 ? MoneyMapDesign.warningGold : .secondary
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 104), spacing: 10)
        ]
    }
}

private struct RecommendationScenarioRow: View {
    let scenario: RecommendationScenario

    private var cardTotal: Double {
        scenario.plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }
    }

    private var goalTotal: Double {
        scenario.plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(scenario.title)
                    .font(.headline)
                Spacer(minLength: 8)
                MoneyMapMoneyText(amount: scenario.availableCash, font: .headline)
            }

            Text(scenario.plan.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Label(MoneyMapFormatters.currencyString(for: cardTotal), systemImage: "creditcard")
                Label(MoneyMapFormatters.currencyString(for: goalTotal), systemImage: "target")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct CardPaymentRecommendationRow: View {
    let recommendation: CreditCardPaymentRecommendation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "creditcard")
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 26, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(recommendation.billName)
                        .font(.headline)
                    Spacer(minLength: 8)
                    MoneyMapMoneyText(amount: recommendation.recommendedPayment, font: .headline)
                }

                Text(recommendation.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    if let dueDate = recommendation.dueDate {
                        Label(MoneyMapFormatters.mediumDateString(for: dueDate), systemImage: "calendar")
                    }
                    Label(recommendation.utilization.formatted(.percent.precision(.fractionLength(0))), systemImage: "chart.pie")
                    if let apr = recommendation.annualPercentageRate {
                        Label(apr.formatted(.percent.precision(.fractionLength(1))), systemImage: "percent")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct GoalContributionRecommendationRow: View {
    let insight: GoalSavingInsight

    private var scheduleDetail: String {
        if insight.isBehindSchedule {
            if insight.shortfallAmount > 0 {
                return "Behind by about \(MoneyMapFormatters.currencyString(for: insight.shortfallAmount))"
            }

            return "Behind schedule"
        }

        return "On track with this contribution"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "target")
                .font(.headline)
                .foregroundStyle(insight.isBehindSchedule ? .orange : MoneyMapDesign.calmGreen)
                .frame(width: 26, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(insight.goalName)
                        .font(.headline)
                    Spacer(minLength: 8)
                    MoneyMapMoneyText(amount: insight.recommendedContribution, font: .headline)
                }

                Text("Target each paycheck: \(MoneyMapFormatters.currencyString(for: insight.targetPerPaycheck))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(scheduleDetail)
                    .font(.subheadline)
                    .foregroundStyle(insight.isBehindSchedule ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct RecommendationsWelcomeSheet: View {
    let hasPayday: Bool
    let hasCreditCards: Bool
    let hasGoals: Bool
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paycheck Plan")
                            .font(.largeTitle.bold())
                        Text("This screen helps you decide what to do with one paycheck at a time.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        WelcomeStep(
                            number: 1,
                            title: "Enter the amount you want to plan",
                            message: "Start with only the money you want to put toward credit cards and savings goals right now. This can be your full paycheck or just one part of it."
                        )
                        WelcomeStep(
                            number: 2,
                            title: "Pick your strategy",
                            message: "Card Payoff changes which credit cards get priority. Paycheck Plan changes how much of your cash leans toward debt versus savings goals."
                        )
                        WelcomeStep(
                            number: 3,
                            title: "Review the plan",
                            message: "Summary shows the big picture, Card Payment Calculator suggests how much to pay each card, and Goal Contributions shows how much to save per goal."
                        )
                        WelcomeStep(
                            number: 4,
                            title: "Apply only when ready",
                            message: "Apply buttons update your cards and goals immediately. Use them when the recommendation looks right for this pay period."
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Best Results")
                            .font(.headline)

                        WelcomeStatusRow(
                            title: "Next payday is set",
                            detail: "Needed for better timing and goal pacing.",
                            isReady: hasPayday
                        )
                        WelcomeStatusRow(
                            title: "At least one credit card exists",
                            detail: "Needed for card payment recommendations.",
                            isReady: hasCreditCards
                        )
                        WelcomeStatusRow(
                            title: "At least one goal exists",
                            detail: "Needed for savings recommendations.",
                            isReady: hasGoals
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Good First Try")
                            .font(.headline)
                        Text("Enter the amount you want to use right now, leave the strategies on Balanced, review the top card payment and top goal contribution, then decide if you want to apply them.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onDone()
                } label: {
                    MoneyMapNeutralButtonLabel(
                        title: "Start Planning",
                        systemImage: "play.circle",
                        iconColor: MoneyMapDesign.calmGreen
                    )
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
        }
    }

}

private struct WelcomeStep: View {
    let number: Int
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(MoneyMapDesign.calmGreen)
                .frame(width: 28, height: 28)
                .background(MoneyMapDesign.calmGreen.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WelcomeStatusRow: View {
    let title: String
    let detail: String
    let isReady: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(isReady ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    NavigationStack {
        RecommendationsView()
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
}
