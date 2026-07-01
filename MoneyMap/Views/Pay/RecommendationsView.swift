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

    var body: some View {
        Form {
            Section {
                TipView(RecommendationStrategiesTip())
            }

            Section("Money To Plan") {
                TextField("Amount Available For Goals And Cards", value: $availableCash, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .focused($amountFieldFocused)
                Text("Enter only the money you want to use for savings goals and credit-card payments right now. This does not have to be your full paycheck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextPayday = paydayManager.nextPayday {
                    LabeledContent("Next Payday") {
                        Text(nextPayday.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("Days Away") {
                        Text("\(paydayManager.daysUntilNextPayday())")
                    }
                }
            }

            Section("Strategies") {
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
            }

            Section("Summary") {
                LabeledContent("Total Available") {
                    Text(plan.totalAvailable, format: .currency(code: "USD"))
                }
                LabeledContent("Planned for Cards") {
                    Text(plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }, format: .currency(code: "USD"))
                }
                LabeledContent("Planned for Goals") {
                    Text(plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }, format: .currency(code: "USD"))
                }
                LabeledContent("Left Unallocated") {
                    Text(plan.unallocatedCash, format: .currency(code: "USD"))
                }
                Text(plan.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("What Matters Before Payday") {
                LabeledContent("Upcoming Bills") {
                    Text("\(digest.upcomingBillCount)")
                }
                LabeledContent("Behind Goals") {
                    Text("\(digest.behindGoalCount)")
                }
                if let cardName = digest.topCardName {
                    LabeledContent("Top Card Action") {
                        Text(cardName)
                    }
                }
                if let goalName = digest.topGoalName {
                    LabeledContent("Top Goal Action") {
                        Text(goalName)
                    }
                }
            }

            Section("Apple Intelligence") {
                if let availabilityMessage {
                    Label(availabilityMessage, systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Use the on-device model to explain why this plan favors certain cards, goals, and timing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let generatedExplanation, !generatedExplanation.isEmpty {
                    Text(generatedExplanation)
                        .font(.subheadline)
                }

                if let explanationError {
                    Text(explanationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await generateExplanation()
                    }
                } label: {
                    if isGeneratingExplanation {
                        Label("Explaining Plan...", systemImage: "sparkles")
                    } else if generatedExplanation == nil {
                        Label("Explain This Plan", systemImage: "sparkles")
                    } else {
                        Label("Refresh Explanation", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isGeneratingExplanation || availabilityMessage != nil)
            }

            Section("Scenario Compare") {
                ForEach(scenarios) { scenario in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(scenario.title)
                                .font(.headline)
                            Spacer()
                            Text(scenario.availableCash, format: .currency(code: "USD"))
                                .font(.headline)
                        }
                        Text(scenario.plan.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label(
                                MoneyMapFormatters.currencyString(
                                    for: scenario.plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }
                                ),
                                systemImage: "creditcard"
                            )
                            Label(
                                MoneyMapFormatters.currencyString(
                                    for: scenario.plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }
                                ),
                                systemImage: "target"
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Card Payment Calculator") {
                if plan.creditCardPayments.isEmpty {
                    Text("No credit-card payment recommendations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(plan.creditCardPayments, id: \.billID) { recommendation in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(recommendation.billName)
                                    .font(.headline)
                                Spacer()
                                Text(recommendation.recommendedPayment, format: .currency(code: "USD"))
                                    .font(.headline)
                            }
                            Text(recommendation.rationale)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
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
                        .padding(.vertical, 4)
                    }
                    Button(didApplyCardPlan ? "Applied Card Plan" : "Apply Recommended Card Payments") {
                        applyCardPlan()
                    }
                    .disabled(didApplyCardPlan)
                }
            }

            Section("Goal Contributions") {
                if plan.goalContributions.isEmpty {
                    Text("No goal contribution recommendations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(plan.goalContributions, id: \.goalID) { insight in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(insight.goalName)
                                    .font(.headline)
                                Spacer()
                                Text(insight.recommendedContribution, format: .currency(code: "USD"))
                                    .font(.headline)
                            }
                            Text("Target each paycheck: \(insight.targetPerPaycheck, format: .currency(code: "USD"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if insight.isBehindSchedule {
                                Text(insight.shortfallAmount > 0
                                     ? "Behind schedule by about \(insight.shortfallAmount, format: .currency(code: "USD"))."
                                     : "Behind schedule.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            } else {
                                Text("On track with this contribution.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button(didApplyGoalPlan ? "Applied Goal Plan" : "Apply Goal Contributions") {
                        applyGoalPlan()
                    }
                    .disabled(didApplyGoalPlan)
                }
            }

            Section {
                TipView(RecommendationApplyTip())
            }
        }
        .navigationTitle("Recommendations")
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
                        Text("Recommendations")
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
                Button("Start Using Recommendations") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
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
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
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
