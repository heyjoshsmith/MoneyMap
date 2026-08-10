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
    @Query(sort: \ExtraMoneyPlan.createdAt, order: .reverse) private var savedPlans: [ExtraMoneyPlan]
    @Query private var savedPlanItems: [ExtraMoneyPlanItem]
    @Query private var manualSavingsAccounts: [ManualSavingsAccount]
    @AppStorage("hasSeenRecommendationsWelcome") private var hasSeenRecommendationsWelcome = false

    private let plaidContainer: ModelContainer

    @State private var showingAllocationFlow = false
    @State private var manualAvailableCash: Double = 0
    @State private var paycheckCashSource: PaycheckCashSource = RecommendationPreferencesStore.paycheckCashSource
    @State private var selectedPaycheckAccountID = RecommendationPreferencesStore.paycheckCashAccountID ?? ""
    @State private var paycheckAccounts: [PaycheckCashAccount] = []
    @State private var creditAccounts: [CreditCardPlanningAccount] = []
    @State private var paycheckAccountLoadError: String?
    @State private var payoffStrategy: CreditCardPayoffStrategy = RecommendationPreferencesStore.cardStrategy
    @State private var allocationStrategy: PaycheckAllocationStrategy = RecommendationPreferencesStore.paycheckStrategy
    @State private var didApplyGoalPlan = false
    @State private var didApplyCardPlan = false
    @State private var didSavePlan = false
    @State private var showingWelcome = false
    @State private var showingManualCashEditor = false
    @State private var showingDeletePlanConfirmation = false
    @State private var planPendingDeletion: ExtraMoneyPlan?
    @State private var selectedSavedPlan: ExtraMoneyPlan?
    @State private var generatedExplanation: String?
    @State private var explanationError: String?
    @State private var isGeneratingExplanation = false
    @FocusState private var amountFieldFocused: Bool

    init() {
        do {
            plaidContainer = try PlaidSyncContainerFactory.make()
        } catch {
            plaidContainer = PlaidSyncContainerFactory.makeInMemory(fallbackReason: "Recommendations could not open the Plaid sync store: \(error.localizedDescription)")
        }
    }

    private var creditCards: [Bill] {
        bills.filter { $0.category == .creditCard }
    }

    private var totalCreditCardDebt: Double {
        let creditAccountsByID = Dictionary(uniqueKeysWithValues: creditAccounts.map { ($0.accountID, $0) })
        return creditCards.reduce(0) { total, bill in
            let linkedBalance = bill.plaidAccountID.flatMap { creditAccountsByID[$0]?.balanceAmount } ?? 0
            return total + max(linkedBalance, abs(bill.creditCardDetails?.cardBalance ?? 0))
        }
    }

    private var totalGoalSavings: Double {
        goals.reduce(0) { total, goal in
            total + max(goal.amountSaved, 0)
        }
    }

    private var manualSavingsBalance: Double {
        manualSavingsAccounts.first?.balanceAmount ?? 0
    }

    private var highlightedSavingsTotal: Double {
        manualSavingsBalance > 0 ? manualSavingsBalance : totalGoalSavings
    }

    private var savingsSnapshotDetail: String {
        manualSavingsBalance > 0 ? "Manual savings balance" : "\(goals.count) goal\(goals.count == 1 ? "" : "s")"
    }

    private var orderedPaycheckAccounts: [PaycheckCashAccount] {
        paycheckAccounts.sorted { lhs, rhs in
            let lhsInstitution = lhs.institutionName ?? ""
            let rhsInstitution = rhs.institutionName ?? ""
            if lhsInstitution != rhsInstitution {
                return lhsInstitution.localizedCaseInsensitiveCompare(rhsInstitution) == .orderedAscending
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var selectedPaycheckAccount: PaycheckCashAccount? {
        orderedPaycheckAccounts.first { $0.accountID == selectedPaycheckAccountID }
    }

    private var selectedPaycheckAccountIDValue: String? {
        selectedPaycheckAccountID.isEmpty ? nil : selectedPaycheckAccountID
    }

    private var grossAvailableCash: Double {
        PaycheckCashResolver.availableCash(
            source: paycheckCashSource,
            manualAmount: manualAvailableCash,
            selectedAccountID: selectedPaycheckAccountIDValue,
            accounts: orderedPaycheckAccounts
        )
    }

    private var availableCash: Double {
        max(grossAvailableCash - activeAllocatedCash, 0)
    }

    private var activeAllocatedCash: Double {
        matchingActivePlans.reduce(0) { total, plan in
            total + plan.plannedCardAmount + plan.plannedGoalAmount
        }
    }

    private var matchingActivePlans: [ExtraMoneyPlan] {
        savedPlans.filter { plan in
            guard plan.status == .active, plan.source == planSource else { return false }
            switch paycheckCashSource {
            case .manual:
                return plan.sourceAccountIDText == nil
            case .linkedAccount:
                return plan.sourceAccountIDText == selectedPaycheckAccountIDValue
            }
        }
    }

    private var planSource: ExtraMoneyPlanSource {
        switch paycheckCashSource {
        case .manual:
            return .manual
        case .linkedAccount:
            return .linkedAccount
        }
    }

    private var sourceAccountName: String? {
        switch paycheckCashSource {
        case .manual:
            return "Manual amount"
        case .linkedAccount:
            guard let selectedPaycheckAccount else { return nil }
            return paycheckAccountPickerTitle(for: selectedPaycheckAccount)
        }
    }

    private var cashSourceSummary: String {
        switch paycheckCashSource {
        case .manual:
            return "Manual amount"
        case .linkedAccount:
            return selectedPaycheckAccount.map(paycheckAccountPickerTitle(for:)) ?? "Selected bank account unavailable"
        }
    }

    private var paycheckAccountSignature: String {
        orderedPaycheckAccounts
            .map { "\($0.accountID)|\($0.availableBalance ?? -1)|\($0.currentBalance ?? -1)" }
            .joined(separator: ";")
    }

    private var plan: PaycheckRecommendationPlan {
        FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            creditAccounts: creditAccounts,
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
            creditAccounts: creditAccounts,
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
            creditAccounts: creditAccounts,
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
            financialSnapshotSection
            allocationActionSection
            planHistorySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("Plan")
        .fullScreenCover(isPresented: $showingAllocationFlow) {
            NavigationStack {
                AllocationGuidedPlanView(
                    initialManualAvailableCash: manualAvailableCash,
                    initialPaycheckCashSource: paycheckCashSource,
                    initialSelectedPaycheckAccountID: selectedPaycheckAccountID,
                    initialPayoffStrategy: payoffStrategy,
                    initialAllocationStrategy: allocationStrategy,
                    orderedPaycheckAccounts: orderedPaycheckAccounts,
                    paycheckAccountLoadError: paycheckAccountLoadError,
                    activeAllocatedCash: activeAllocatedCash,
                    matchingActivePlanCount: matchingActivePlans.count,
                    goals: goals,
                    bills: bills,
                    creditAccounts: creditAccounts,
                    nextPayday: paydayManager.nextPayday,
                    onClose: commitPlanDraft,
                    onSave: saveCurrentPlan(from:)
                )
            }
            .interactiveDismissDisabled(true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingWelcome = true
                } label: {
                    Label("How It Works", systemImage: "questionmark.circle")
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
        .sheet(isPresented: $showingManualCashEditor) {
            ManualAvailableCashEditor(amount: $manualAvailableCash) {
                persistManualAvailableCash()
            }
        }
        .sheet(item: $selectedSavedPlan) { savedPlan in
            NavigationStack {
                SavedExtraMoneyPlanDetailView(
                    plan: savedPlan,
                    items: items(for: savedPlan),
                    onApplyPayments: {
                        applySavedCardPayments(savedPlan)
                    }
                )
            }
        }
        .confirmationDialog(
            "Delete this plan?",
            isPresented: $showingDeletePlanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Plan", role: .destructive) {
                if let planPendingDeletion {
                    delete(planPendingDeletion)
                }
                planPendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                planPendingDeletion = nil
            }
        } message: {
            Text("This permanently removes the saved plan and its decisions from history.")
        }
        .onAppear {
            if manualAvailableCash == 0 {
                manualAvailableCash = paydayConfigs.first?.amountPerPayday ?? 0
            }
            syncPaycheckCashSelection()
            if !hasSeenRecommendationsWelcome {
                showingWelcome = true
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            loadPaycheckAccounts()
            loadCreditAccounts()
        }
        .onChange(of: manualAvailableCash) { _, newValue in
            didApplyGoalPlan = false
            didApplyCardPlan = false
            didSavePlan = false
            clearExplanation()
        }
        .onChange(of: paycheckCashSource) { _, newValue in
            RecommendationPreferencesStore.paycheckCashSource = newValue
            syncPaycheckCashSelection()
            didApplyGoalPlan = false
            didApplyCardPlan = false
            didSavePlan = false
            clearExplanation()
        }
        .onChange(of: selectedPaycheckAccountID) { _, newValue in
            RecommendationPreferencesStore.paycheckCashAccountID = newValue
            didApplyGoalPlan = false
            didApplyCardPlan = false
            didSavePlan = false
            clearExplanation()
        }
        .onChange(of: paycheckAccountSignature) { _, _ in
            syncPaycheckCashSelection()
            didApplyGoalPlan = false
            didApplyCardPlan = false
            didSavePlan = false
            clearExplanation()
        }
        .onChange(of: payoffStrategy) { _, newValue in
            RecommendationPreferencesStore.cardStrategy = newValue
            didApplyGoalPlan = false
            didApplyCardPlan = false
            didSavePlan = false
            clearExplanation()
        }
        .onChange(of: allocationStrategy) { _, newValue in
            RecommendationPreferencesStore.paycheckStrategy = newValue
            didApplyGoalPlan = false
            didApplyCardPlan = false
            didSavePlan = false
            clearExplanation()
        }
    }

    private var financialSnapshotSection: some View {
        Section("Snapshot") {
            AllocationSnapshotPanel(
                debtTotal: totalCreditCardDebt,
                debtDetail: "\(creditCards.count) card\(creditCards.count == 1 ? "" : "s")",
                savingsTotal: highlightedSavingsTotal,
                savingsDetail: savingsSnapshotDetail,
                availableCash: availableCash,
                reservedCash: activeAllocatedCash
            )
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var allocationActionSection: some View {
        Section("Next Plan") {
            Button {
                showingAllocationFlow = true
            } label: {
                PlanPayoffActionCard(
                    availableCash: availableCash,
                    sourceSummary: cashSourceSummary,
                    reservedCash: activeAllocatedCash
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                cashSourceContextMenu
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if activeAllocatedCash > 0 {
                MoneyMapSummaryRow(
                    title: "Already Allocated",
                    value: MoneyMapFormatters.currencyString(for: activeAllocatedCash),
                    detail: "\(matchingActivePlans.count) active saved plan\(matchingActivePlans.count == 1 ? "" : "s") reserved from this source",
                    systemImage: "lock.fill",
                    tint: MoneyMapDesign.warningGold
                )
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
        }
    }

    @ViewBuilder
    private var cashSourceContextMenu: some View {
        Section("Available Money") {
            Button {
                chooseManualCashSource()
                showingManualCashEditor = true
            } label: {
                Label(
                    "Manual Amount",
                    systemImage: paycheckCashSource == .manual ? "checkmark.circle.fill" : "keyboard"
                )
            }
        }

        Section("Bank Accounts") {
            if orderedPaycheckAccounts.isEmpty {
                Button {
                    loadPaycheckAccounts()
                } label: {
                    Label("Refresh Accounts", systemImage: "arrow.clockwise")
                }
            } else {
                ForEach(orderedPaycheckAccounts) { account in
                    Button {
                        selectPaycheckAccount(account)
                    } label: {
                        Label(
                            paycheckAccountPickerTitle(for: account),
                            systemImage: selectedPaycheckAccountID == account.accountID ? "checkmark.circle.fill" : "building.columns"
                        )
                    }
                }
            }
        }
    }

    private var overviewSection: some View {
        Section {
            PaycheckPlanOverviewPanel(
                totalAvailable: plan.totalAvailable,
                cardPaymentTotal: cardPaymentTotal,
                goalContributionTotal: goalContributionTotal,
                unallocatedCash: plan.unallocatedCash,
                summary: plan.summary
            )
        } header: {
            Text("Allocation Plan")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var moneySection: some View {
        Section("Available Money") {
            Picker("Source", selection: $paycheckCashSource) {
                ForEach(PaycheckCashSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }

            Text(paycheckCashSource.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch paycheckCashSource {
            case .manual:
                TextField("Amount Available For Goals And Cards", value: $manualAvailableCash, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .focused($amountFieldFocused)

                Text("Only include money you want to put toward cards and goals right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .linkedAccount:
                if let paycheckAccountLoadError {
                    MoneyMapEmptyState(
                        title: "Bank Accounts Unavailable",
                        message: paycheckAccountLoadError,
                        systemImage: "exclamationmark.triangle"
                    )
                } else if orderedPaycheckAccounts.isEmpty {
                    MoneyMapEmptyState(
                        title: "No Bank Accounts Synced",
                        message: "Connect a bank account from Wallet before using a synced account balance.",
                        systemImage: "building.columns"
                    )
                } else {
                    Picker("Account", selection: $selectedPaycheckAccountID) {
                        ForEach(orderedPaycheckAccounts) { account in
                            Text(paycheckAccountPickerTitle(for: account))
                                .tag(account.accountID)
                        }
                    }

                    if let selectedPaycheckAccount {
                        MoneyMapSummaryRow(
                            title: "Synced Amount",
                            value: MoneyMapFormatters.currencyString(for: PaycheckCashResolver.balance(for: selectedPaycheckAccount)),
                            detail: paycheckAccountDetail(for: selectedPaycheckAccount),
                            systemImage: "building.columns",
                            tint: MoneyMapDesign.calmGreen
                        )
                    } else {
                        Text("Choose the account where your extra money lands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if paycheckCashSource == .linkedAccount, selectedPaycheckAccount != nil {
                Text("MoneyMap uses available balance when the bank provides it, otherwise current balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if activeAllocatedCash > 0 {
                MoneyMapSummaryRow(
                    title: "Already Allocated",
                    value: MoneyMapFormatters.currencyString(for: activeAllocatedCash),
                    detail: "\(matchingActivePlans.count) active saved plan\(matchingActivePlans.count == 1 ? "" : "s") reserved from this source",
                    systemImage: "lock.fill",
                    tint: MoneyMapDesign.warningGold
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

            Picker("Allocation Style", selection: $allocationStrategy) {
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
            Button {
                saveCurrentPlan()
            } label: {
                MoneyMapActionListRow(
                    title: didSavePlan || didApplyCardPlan ? "Plan Saved" : "Save Allocation Plan",
                    detail: didApplyCardPlan ? "Card payments are pending in Plan History." : didSavePlan ? "This money is now reserved in Plan History." : "Reserve these decisions so the same dollars are not planned twice.",
                    systemImage: didSavePlan || didApplyCardPlan ? "checkmark.circle.fill" : "square.and.arrow.down",
                    tint: didSavePlan || didApplyCardPlan ? MoneyMapDesign.calmGreen : .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(didSavePlan || didApplyCardPlan || plan.totalAvailable <= 0)

            if !plan.creditCardPayments.isEmpty {
                Button {
                    applyCardPlan()
                } label: {
                    MoneyMapActionListRow(
                        title: didApplyCardPlan ? "Payments Pending" : "Apply Card Payments",
                        detail: didApplyCardPlan ? "MoneyMap will confirm these when matching bank debits import." : "\(MoneyMapFormatters.currencyString(for: cardPaymentTotal)) across \(plan.creditCardPayments.count) card\(plan.creditCardPayments.count == 1 ? "" : "s")",
                        systemImage: didApplyCardPlan ? "clock.badge.checkmark" : "creditcard",
                        tint: didApplyCardPlan ? .green : .blue
                    )
                }
                .buttonStyle(.plain)
                .disabled(didApplyCardPlan || didSavePlan)
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

    private var planHistorySection: some View {
        Section("Saved Plans") {
            if savedPlans.isEmpty {
                MoneyMapEmptyState(
                    title: "No Plans Saved",
                    message: "Tap Plan Payoff to walk through an allocation and save it to history.",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                ForEach(savedPlans) { savedPlan in
                    SavedExtraMoneyPlanRow(
                        plan: savedPlan,
                        itemCount: savedPlanItems.filter { $0.planID == savedPlan.id }.count,
                        pendingPaymentCount: savedPlanItems.filter { $0.planID == savedPlan.id && $0.kind == .creditCardPayment && $0.matchedTransactionIDText == nil }.count,
                        matchedPaymentCount: savedPlanItems.filter { $0.planID == savedPlan.id && $0.kind == .creditCardPayment && $0.matchedTransactionIDText != nil }.count,
                        canApplyPayments: canApplySavedCardPayments(savedPlan),
                        onViewDetails: {
                            selectedSavedPlan = savedPlan
                        },
                        onApplyPayments: {
                            applySavedCardPayments(savedPlan)
                        },
                        onCancel: {
                            cancel(savedPlan)
                        },
                        onUndo: {
                            undo(savedPlan)
                        },
                        onDelete: {
                            requestDelete(savedPlan)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestDelete(savedPlan)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private func items(for savedPlan: ExtraMoneyPlan) -> [ExtraMoneyPlanItem] {
        savedPlanItems
            .filter { $0.planID == savedPlan.id }
            .sorted { lhs, rhs in
                if lhs.kindRaw != rhs.kindRaw {
                    return itemKindSortOrder(lhs.kind) < itemKindSortOrder(rhs.kind)
                }
                if lhs.amountValue != rhs.amountValue {
                    return lhs.amountValue > rhs.amountValue
                }
                return lhs.targetNameText.localizedStandardCompare(rhs.targetNameText) == .orderedAscending
            }
    }

    private func itemKindSortOrder(_ kind: ExtraMoneyPlanItemKind) -> Int {
        switch kind {
        case .creditCardPayment:
            return 0
        case .goalContribution:
            return 1
        case .flexibleCash:
            return 2
        }
    }

    private var beforePaydaySection: some View {
        Section("Timing") {
            MoneyMapSummaryRow(
                title: "Upcoming Bills",
                value: "\(digest.upcomingBillCount)",
                detail: paydayManager.nextPayday == nil ? "Set timing in Pay for better bill urgency" : "Included in the current planning window",
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
        savePlan(
            draft: currentPlanDraft,
            plan: plan,
            grossAvailableCash: grossAvailableCash,
            sourceAccountName: sourceAccountName,
            sourceAccountID: selectedPaycheckAccountIDValue,
            includesGoalContributions: false,
            appliedAt: Date(),
            marksPlanSaved: false
        )
        MoneyMapIntentDonations.donatePaycheckPlan(availableCash: availableCash)
        didApplyCardPlan = true
    }

    private func saveCurrentPlan() {
        savePlan(
            draft: currentPlanDraft,
            plan: plan,
            grossAvailableCash: grossAvailableCash,
            sourceAccountName: sourceAccountName,
            sourceAccountID: selectedPaycheckAccountIDValue
        )
    }

    private func saveCurrentPlan(from draft: AllocationPlanDraft) {
        let draftPlan = plan(for: draft)
        let draftGrossAvailableCash = grossAvailableCash(for: draft)
        savePlan(
            draft: draft,
            plan: draftPlan,
            grossAvailableCash: draftGrossAvailableCash,
            sourceAccountName: sourceAccountName(for: draft),
            sourceAccountID: draft.paycheckCashSource == .linkedAccount ? selectedAccountIDValue(for: draft) : nil
        )
        commitPlanDraft(draft)
    }

    private func savePlan(
        draft: AllocationPlanDraft,
        plan: PaycheckRecommendationPlan,
        grossAvailableCash: Double,
        sourceAccountName: String?,
        sourceAccountID: String?,
        includesGoalContributions: Bool = true,
        appliedAt: Date? = nil,
        marksPlanSaved: Bool = true
    ) {
        let plannedCardAmount = plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }
        let plannedGoalAmount = includesGoalContributions ? plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution } : 0
        let savedAvailableAmount = appliedAt == nil ? plan.totalAvailable : plannedCardAmount + plannedGoalAmount
        let savedPlan = ExtraMoneyPlan(
            source: source(for: draft),
            sourceAccountID: sourceAccountID,
            sourceAccountName: sourceAccountName,
            startingBalance: grossAvailableCash,
            alreadyAllocated: activeAllocatedCash,
            available: savedAvailableAmount,
            plannedCardAmount: plannedCardAmount,
            plannedGoalAmount: plannedGoalAmount,
            unallocatedAmount: appliedAt == nil ? plan.unallocatedCash : 0,
            strategyRaw: draft.allocationStrategy.rawValue,
            payoffStrategyRaw: draft.payoffStrategy.rawValue,
            appliedAt: appliedAt
        )
        modelContext.insert(savedPlan)

        for recommendation in plan.creditCardPayments {
            modelContext.insert(
                ExtraMoneyPlanItem(
                    planID: savedPlan.id,
                    kind: .creditCardPayment,
                    targetID: recommendation.billID,
                    targetName: recommendation.billName,
                    amount: recommendation.recommendedPayment,
                    rationale: recommendation.decisionExplanation
                )
            )
        }

        if includesGoalContributions {
            for insight in plan.goalContributions {
                modelContext.insert(
                    ExtraMoneyPlanItem(
                        planID: savedPlan.id,
                        kind: .goalContribution,
                        targetID: insight.goalID,
                        targetName: insight.goalName,
                        amount: insight.recommendedContribution,
                        rationale: insight.decisionExplanation
                    )
                )
            }
        }

        if appliedAt == nil && plan.unallocatedCash > 0 {
            modelContext.insert(
                ExtraMoneyPlanItem(
                    planID: savedPlan.id,
                    kind: .flexibleCash,
                    targetName: "Flexible Cash",
                    amount: plan.unallocatedCash,
                    rationale: "Left flexible because the plan did not need this amount for selected card payments or goal contributions."
                )
            )
        }

        try? modelContext.save()
        if marksPlanSaved {
            didSavePlan = true
        }
        showingAllocationFlow = false
        MoneyMapIntentDonations.donatePaycheckPlan(availableCash: plan.totalAvailable)
    }

    private var currentPlanDraft: AllocationPlanDraft {
        AllocationPlanDraft(
            manualAvailableCash: manualAvailableCash,
            paycheckCashSource: paycheckCashSource,
            selectedPaycheckAccountID: selectedPaycheckAccountID,
            payoffStrategy: payoffStrategy,
            allocationStrategy: allocationStrategy
        )
    }

    private func commitPlanDraft(_ draft: AllocationPlanDraft) {
        manualAvailableCash = draft.manualAvailableCash
        paycheckCashSource = draft.paycheckCashSource
        selectedPaycheckAccountID = draft.selectedPaycheckAccountID
        payoffStrategy = draft.payoffStrategy
        allocationStrategy = draft.allocationStrategy
        RecommendationPreferencesStore.paycheckCashSource = draft.paycheckCashSource
        RecommendationPreferencesStore.paycheckCashAccountID = selectedAccountIDValue(for: draft) ?? ""
        RecommendationPreferencesStore.cardStrategy = draft.payoffStrategy
        RecommendationPreferencesStore.paycheckStrategy = draft.allocationStrategy
        persistManualAvailableCash(draft.manualAvailableCash)
        didApplyGoalPlan = false
        didApplyCardPlan = false
        didSavePlan = false
        clearExplanation()
    }

    private func persistManualAvailableCash(_ value: Double? = nil) {
        guard let paydayConfig = paydayConfigs.first else { return }
        paydayConfig.amountPerPayday = max(value ?? manualAvailableCash, 0) > 0 ? value ?? manualAvailableCash : nil
        try? modelContext.save()
    }

    private func plan(for draft: AllocationPlanDraft) -> PaycheckRecommendationPlan {
        FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: availableCash(for: draft),
            goals: goals,
            bills: bills,
            nextPayday: paydayManager.nextPayday,
            creditAccounts: creditAccounts,
            allocationStrategy: draft.allocationStrategy,
            payoffStrategy: draft.payoffStrategy
        )
    }

    private func availableCash(for draft: AllocationPlanDraft) -> Double {
        max(grossAvailableCash(for: draft) - activeAllocatedCash, 0)
    }

    private func grossAvailableCash(for draft: AllocationPlanDraft) -> Double {
        PaycheckCashResolver.availableCash(
            source: draft.paycheckCashSource,
            manualAmount: draft.manualAvailableCash,
            selectedAccountID: selectedAccountIDValue(for: draft),
            accounts: orderedPaycheckAccounts
        )
    }

    private func source(for draft: AllocationPlanDraft) -> ExtraMoneyPlanSource {
        switch draft.paycheckCashSource {
        case .manual:
            return .manual
        case .linkedAccount:
            return .linkedAccount
        }
    }

    private func sourceAccountName(for draft: AllocationPlanDraft) -> String? {
        switch draft.paycheckCashSource {
        case .manual:
            return "Manual amount"
        case .linkedAccount:
            return selectedAccount(for: draft).map(paycheckAccountPickerTitle(for:))
        }
    }

    private func selectedAccount(for draft: AllocationPlanDraft) -> PaycheckCashAccount? {
        orderedPaycheckAccounts.first { $0.accountID == draft.selectedPaycheckAccountID }
    }

    private func selectedAccountIDValue(for draft: AllocationPlanDraft) -> String? {
        draft.selectedPaycheckAccountID.isEmpty ? nil : draft.selectedPaycheckAccountID
    }

    private func cancel(_ savedPlan: ExtraMoneyPlan) {
        savedPlan.status = .canceled
        savedPlan.canceledAt = Date()
        try? modelContext.save()
    }

    private func undo(_ savedPlan: ExtraMoneyPlan) {
        savedPlan.status = .undone
        savedPlan.undoneAt = Date()
        try? modelContext.save()
    }

    private func canApplySavedCardPayments(_ savedPlan: ExtraMoneyPlan) -> Bool {
        savedPlan.status == .active &&
            savedPlan.appliedAt == nil &&
            savedPlanItems.contains {
                $0.planID == savedPlan.id &&
                    $0.kind == .creditCardPayment &&
                    $0.matchedTransactionIDText == nil
            }
    }

    private func applySavedCardPayments(_ savedPlan: ExtraMoneyPlan) {
        guard canApplySavedCardPayments(savedPlan) else { return }

        savedPlan.appliedAt = Date()
        savedPlan.updatedAt = Date()
        try? modelContext.save()
    }

    private func requestDelete(_ savedPlan: ExtraMoneyPlan) {
        planPendingDeletion = savedPlan
        showingDeletePlanConfirmation = true
    }

    private func delete(_ savedPlan: ExtraMoneyPlan) {
        savedPlanItems
            .filter { $0.planID == savedPlan.id }
            .forEach { modelContext.delete($0) }
        modelContext.delete(savedPlan)
        try? modelContext.save()
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

    private func chooseManualCashSource() {
        paycheckCashSource = .manual
        RecommendationPreferencesStore.paycheckCashSource = .manual
        didApplyGoalPlan = false
        didApplyCardPlan = false
        didSavePlan = false
        clearExplanation()
    }

    private func selectPaycheckAccount(_ account: PaycheckCashAccount) {
        selectedPaycheckAccountID = account.accountID
        RecommendationPreferencesStore.paycheckCashAccountID = account.accountID
        paycheckCashSource = .linkedAccount
        RecommendationPreferencesStore.paycheckCashSource = .linkedAccount
        didApplyGoalPlan = false
        didApplyCardPlan = false
        didSavePlan = false
        clearExplanation()
    }

    private func syncPaycheckCashSelection() {
        guard paycheckCashSource == .linkedAccount else { return }

        let availableAccountIDs = Set(orderedPaycheckAccounts.map(\.accountID))
        if selectedPaycheckAccountID.isEmpty {
            if let storedAccountID = RecommendationPreferencesStore.paycheckCashAccountID,
               availableAccountIDs.contains(storedAccountID) {
                selectedPaycheckAccountID = storedAccountID
            } else if let firstAccountID = orderedPaycheckAccounts.first?.accountID {
                selectedPaycheckAccountID = firstAccountID
                RecommendationPreferencesStore.paycheckCashAccountID = firstAccountID
            } else {
                paycheckCashSource = .manual
                RecommendationPreferencesStore.paycheckCashSource = .manual
                RecommendationPreferencesStore.paycheckCashAccountID = ""
            }
            return
        }

        guard availableAccountIDs.contains(selectedPaycheckAccountID) else {
            if let firstAccountID = orderedPaycheckAccounts.first?.accountID {
                selectedPaycheckAccountID = firstAccountID
                RecommendationPreferencesStore.paycheckCashAccountID = firstAccountID
            } else {
                selectedPaycheckAccountID = ""
                paycheckCashSource = .manual
                RecommendationPreferencesStore.paycheckCashSource = .manual
                RecommendationPreferencesStore.paycheckCashAccountID = ""
            }
            return
        }

        RecommendationPreferencesStore.paycheckCashAccountID = selectedPaycheckAccountID
    }

    private func loadPaycheckAccounts() {
        do {
            paycheckAccounts = try MoneyMapDiagnostics.measure("plan.paycheckAccounts.fetch") {
                try MoneyMapPlanningStore.fetchPaycheckCashAccounts()
            }
            paycheckAccountLoadError = nil
            syncPaycheckCashSelection()
        } catch {
            paycheckAccounts = []
            paycheckAccountLoadError = error.localizedDescription
        }
    }

    private func loadCreditAccounts() {
        let context = ModelContext(plaidContainer)
        let accounts = MoneyMapDiagnostics.measure("plan.creditAccounts.fetch") {
            (try? context.fetch(FetchDescriptor<PlaidAccountSnapshot>())) ?? []
        }
        creditAccounts = accounts
            .filter { account in
                account.type.localizedCaseInsensitiveCompare("credit") == .orderedSame
                    || account.subtype?.localizedCaseInsensitiveCompare("credit card") == .orderedSame
            }
            .map {
                CreditCardPlanningAccount(
                    accountID: $0.accountID,
                    currentBalance: $0.currentBalance,
                    availableBalance: $0.availableBalance
                )
            }
    }

    private func paycheckAccountPickerTitle(for account: PaycheckCashAccount) -> String {
        let institution = account.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bankPrefix = institution.map { $0.isEmpty ? "" : "\($0) - " } ?? ""
        let suffix = account.lastFourLabel.map { " - \($0)" } ?? ""
        return "\(bankPrefix)\(account.displayName)\(suffix)"
    }

    private func paycheckAccountDetail(for account: PaycheckCashAccount) -> String {
        let balanceKind = account.availableBalance == nil && account.currentBalance != nil ? "current balance" : "available balance"
        let institution = account.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let institutionLabel = institution.flatMap { $0.isEmpty ? nil : $0 }
        let accountName = [institutionLabel, account.displayName]
            .compactMap { $0 }
            .joined(separator: " - ")
        return "\(balanceKind.capitalized) from \(accountName)"
    }
}

private enum AllocationGuidedStep: Int, CaseIterable, Identifiable {
    case money
    case priorities
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .money:
            return "Money"
        case .priorities:
            return "Priorities"
        case .review:
            return "Review"
        }
    }

    var detail: String {
        switch self {
        case .money:
            return "Choose the money you want to allocate today."
        case .priorities:
            return "Decide how MoneyMap should split the money."
        case .review:
            return "Review the decisions before saving the plan."
        }
    }

    var systemImage: String {
        switch self {
        case .money:
            return "banknote"
        case .priorities:
            return "slider.horizontal.3"
        case .review:
            return "checklist"
        }
    }

    var next: AllocationGuidedStep? {
        AllocationGuidedStep(rawValue: rawValue + 1)
    }

    var previous: AllocationGuidedStep? {
        AllocationGuidedStep(rawValue: rawValue - 1)
    }
}

private struct AllocationSnapshotPanel: View {
    let debtTotal: Double
    let debtDetail: String
    let savingsTotal: Double
    let savingsDetail: String
    let availableCash: Double
    let reservedCash: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SnapshotHeroMetric(
                    title: "Debt",
                    value: debtTotal,
                    detail: debtDetail,
                    systemImage: "creditcard",
                    tint: .blue
                )

                SnapshotHeroMetric(
                    title: "Savings",
                    value: savingsTotal,
                    detail: savingsDetail,
                    systemImage: "target",
                    tint: MoneyMapDesign.calmGreen
                )
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                MoneyMapMetricTile(
                    title: "Available",
                    value: MoneyMapFormatters.currencyString(for: availableCash),
                    systemImage: "banknote",
                    tint: MoneyMapDesign.calmGreen
                )
                MoneyMapMetricTile(
                    title: "Reserved",
                    value: MoneyMapFormatters.currencyString(for: reservedCash),
                    systemImage: "lock.fill",
                    tint: reservedCash > 0 ? MoneyMapDesign.warningGold : .secondary
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 118), spacing: 10)
        ]
    }
}

private struct SnapshotHeroMetric: View {
    let title: String
    let value: Double
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            MoneyMapMoneyText(
                amount: value,
                font: .title3.weight(.semibold),
                foregroundStyle: .primary
            )
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PlanPayoffActionCard: View {
    let availableCash: Double
    let sourceSummary: String
    let reservedCash: Double

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checklist")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Plan Payoff")
                    .font(.headline)
                    .foregroundStyle(.white)

                MoneyMapMoneyText(
                    amount: availableCash,
                    font: .title2.weight(.semibold),
                    foregroundStyle: .white
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Text(sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Start")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.blue)
                .frame(minWidth: 92, minHeight: 46)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

                if reservedCash > 0 {
                    Label(MoneyMapFormatters.currencyString(for: reservedCash), systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .center)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [.blue, MoneyMapDesign.calmGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ManualAvailableCashEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var amount: Double
    let onDone: () -> Void
    @FocusState private var amountFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Available Money") {
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .focused($amountFieldFocused)

                    Text("Only include money you want to put toward cards and goals right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .moneyMapListSectionBackground()
            }
            .moneyMapGroupedListBackground()
            .navigationTitle("Manual Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        amountFieldFocused = false
                    }
                }
            }
            .onAppear {
                amountFieldFocused = true
            }
            .onDisappear {
                onDone()
            }
        }
    }
}

private struct AllocationPlanDraft: Equatable {
    var manualAvailableCash: Double
    var paycheckCashSource: PaycheckCashSource
    var selectedPaycheckAccountID: String
    var payoffStrategy: CreditCardPayoffStrategy
    var allocationStrategy: PaycheckAllocationStrategy
}

private struct AllocationGuidedPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AllocationPlanDraft

    let orderedPaycheckAccounts: [PaycheckCashAccount]
    let paycheckAccountLoadError: String?
    let activeAllocatedCash: Double
    let matchingActivePlanCount: Int
    let goals: [Goal]
    let bills: [Bill]
    let creditAccounts: [CreditCardPlanningAccount]
    let nextPayday: Date?
    let onClose: (AllocationPlanDraft) -> Void
    let onSave: (AllocationPlanDraft) -> Void

    @State private var currentStep: AllocationGuidedStep = .money
    @State private var stepNavigationDirection = 1
    @FocusState private var amountFieldFocused: Bool

    init(
        initialManualAvailableCash: Double,
        initialPaycheckCashSource: PaycheckCashSource,
        initialSelectedPaycheckAccountID: String,
        initialPayoffStrategy: CreditCardPayoffStrategy,
        initialAllocationStrategy: PaycheckAllocationStrategy,
        orderedPaycheckAccounts: [PaycheckCashAccount],
        paycheckAccountLoadError: String?,
        activeAllocatedCash: Double,
        matchingActivePlanCount: Int,
        goals: [Goal],
        bills: [Bill],
        creditAccounts: [CreditCardPlanningAccount],
        nextPayday: Date?,
        onClose: @escaping (AllocationPlanDraft) -> Void,
        onSave: @escaping (AllocationPlanDraft) -> Void
    ) {
        _draft = State(initialValue: AllocationPlanDraft(
            manualAvailableCash: initialManualAvailableCash,
            paycheckCashSource: initialPaycheckCashSource,
            selectedPaycheckAccountID: initialSelectedPaycheckAccountID,
            payoffStrategy: initialPayoffStrategy,
            allocationStrategy: initialAllocationStrategy
        ))
        self.orderedPaycheckAccounts = orderedPaycheckAccounts
        self.paycheckAccountLoadError = paycheckAccountLoadError
        self.activeAllocatedCash = activeAllocatedCash
        self.matchingActivePlanCount = matchingActivePlanCount
        self.goals = goals
        self.bills = bills
        self.creditAccounts = creditAccounts
        self.nextPayday = nextPayday
        self.onClose = onClose
        self.onSave = onSave
    }

    private var selectedPaycheckAccount: PaycheckCashAccount? {
        orderedPaycheckAccounts.first { $0.accountID == draft.selectedPaycheckAccountID }
    }

    private var selectedPaycheckAccountIDValue: String? {
        draft.selectedPaycheckAccountID.isEmpty ? nil : draft.selectedPaycheckAccountID
    }

    private func syncDraftPaycheckCashSelection() {
        guard draft.paycheckCashSource == .linkedAccount else { return }
        let availableAccountIDs = Set(orderedPaycheckAccounts.map(\.accountID))

        if availableAccountIDs.contains(draft.selectedPaycheckAccountID) {
            return
        }

        if let firstAccountID = orderedPaycheckAccounts.first?.accountID {
            draft.selectedPaycheckAccountID = firstAccountID
        } else {
            draft.selectedPaycheckAccountID = ""
            draft.paycheckCashSource = .manual
        }
    }

    private var grossAvailableCash: Double {
        PaycheckCashResolver.availableCash(
            source: draft.paycheckCashSource,
            manualAmount: draft.manualAvailableCash,
            selectedAccountID: selectedPaycheckAccountIDValue,
            accounts: orderedPaycheckAccounts
        )
    }

    private var availableCash: Double {
        max(grossAvailableCash - activeAllocatedCash, 0)
    }

    private var plan: PaycheckRecommendationPlan {
        FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
            creditAccounts: creditAccounts,
            allocationStrategy: draft.allocationStrategy,
            payoffStrategy: draft.payoffStrategy
        )
    }

    private var scenarios: [RecommendationScenario] {
        FinancialPlanningEngine.scenarioPlans(
            baseAvailableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
            creditAccounts: creditAccounts,
            allocationStrategy: draft.allocationStrategy,
            payoffStrategy: draft.payoffStrategy
        )
    }

    private var digest: RecommendationDigest {
        FinancialPlanningEngine.digest(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
            creditAccounts: creditAccounts,
            allocationStrategy: draft.allocationStrategy,
            payoffStrategy: draft.payoffStrategy
        )
    }

    private var cardPaymentTotal: Double {
        plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }
    }

    private var goalContributionTotal: Double {
        plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }
    }

    private var primaryActionTitle: String {
        currentStep == .review ? "Save Plan" : "Continue"
    }

    private var primaryActionSystemImage: String {
        currentStep == .review ? "square.and.arrow.down" : "chevron.right"
    }

    private var primaryActionDisabled: Bool {
        switch currentStep {
        case .money:
            return draft.paycheckCashSource == .linkedAccount && selectedPaycheckAccount == nil
        case .priorities:
            return false
        case .review:
            return plan.totalAvailable <= 0
        }
    }

    private var stepTransition: AnyTransition {
        let insertionEdge: Edge = stepNavigationDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = stepNavigationDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .push(from: insertionEdge),
            removal: .push(from: removalEdge)
        )
    }

    var body: some View {
        List {
            stepHeader

            currentStepSections
                .id(currentStep)
                .transition(stepTransition)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("Plan Payoff")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            guidedNavigationFooter
        }
        .onAppear {
            syncDraftPaycheckCashSelection()
        }
        .onChange(of: draft.paycheckCashSource) { _, _ in
            syncDraftPaycheckCashSelection()
        }
        .onChange(of: orderedPaycheckAccounts.map(\.accountID)) { _, _ in
            syncDraftPaycheckCashSelection()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose(draft)
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    amountFieldFocused = false
                }
            }
        }
    }

    @ViewBuilder
    private var currentStepSections: some View {
        switch currentStep {
        case .money:
            moneyStepSection
        case .priorities:
            timingStepSection
            priorityStepSection
            scenarioStepSection
        case .review:
            reviewOverviewSection
            cardPaymentReviewSection
            goalContributionReviewSection
        }
    }

    private var stepHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: currentStep.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(MoneyMapDesign.calmGreen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Step \(currentStep.rawValue + 1) of \(AllocationGuidedStep.allCases.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(currentStep.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(currentStep.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: Double(currentStep.rawValue + 1), total: Double(AllocationGuidedStep.allCases.count))
                    .tint(MoneyMapDesign.calmGreen)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var guidedNavigationFooter: some View {
        HStack(spacing: 12) {
            if let previousStep = currentStep.previous {
                Button {
                    move(to: previousStep, direction: -1)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Button {
                advance()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(primaryActionDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var moneyStepSection: some View {
        Section("Available Money") {
            Picker("Source", selection: $draft.paycheckCashSource) {
                ForEach(PaycheckCashSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }

            Text(draft.paycheckCashSource.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch draft.paycheckCashSource {
            case .manual:
                TextField("Amount Available For Goals And Cards", value: $draft.manualAvailableCash, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .focused($amountFieldFocused)

                Text("Only include money you want to put toward cards and goals right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .linkedAccount:
                if let paycheckAccountLoadError {
                    MoneyMapEmptyState(
                        title: "Bank Accounts Unavailable",
                        message: paycheckAccountLoadError,
                        systemImage: "exclamationmark.triangle"
                    )
                } else if orderedPaycheckAccounts.isEmpty {
                    MoneyMapEmptyState(
                        title: "No Bank Accounts Synced",
                        message: "Connect a bank account from Wallet before using a synced account balance.",
                        systemImage: "building.columns"
                    )
                } else {
                    Picker("Account", selection: $draft.selectedPaycheckAccountID) {
                        ForEach(orderedPaycheckAccounts) { account in
                            Text(paycheckAccountPickerTitle(for: account))
                                .tag(account.accountID)
                        }
                    }

                    if let selectedPaycheckAccount {
                        MoneyMapSummaryRow(
                            title: "Synced Amount",
                            value: MoneyMapFormatters.currencyString(for: PaycheckCashResolver.balance(for: selectedPaycheckAccount)),
                            detail: paycheckAccountDetail(for: selectedPaycheckAccount),
                            systemImage: "building.columns",
                            tint: MoneyMapDesign.calmGreen
                        )
                    } else {
                        Text("Choose the account where your extra money lands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MoneyMapSummaryRow(
                title: "Available To Plan",
                value: MoneyMapFormatters.currencyString(for: plan.totalAvailable),
                detail: activeAllocatedCash > 0 ? "\(MoneyMapFormatters.currencyString(for: activeAllocatedCash)) is already reserved" : "No saved plan is reserving this source",
                systemImage: "banknote",
                tint: MoneyMapDesign.calmGreen
            )

            if activeAllocatedCash > 0 {
                MoneyMapSummaryRow(
                    title: "Already Allocated",
                    value: MoneyMapFormatters.currencyString(for: activeAllocatedCash),
                    detail: "\(matchingActivePlanCount) active saved plan\(matchingActivePlanCount == 1 ? "" : "s") reserved from this source",
                    systemImage: "lock.fill",
                    tint: MoneyMapDesign.warningGold
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var timingStepSection: some View {
        Section("Current Pressure") {
            MoneyMapSummaryRow(
                title: "Upcoming Bills",
                value: "\(digest.upcomingBillCount)",
                detail: digest.upcomingBillCount == 0 ? "No urgent bills in the planning window" : "Included in this plan",
                systemImage: "calendar.badge.exclamationmark",
                tint: digest.upcomingBillCount > 0 ? MoneyMapDesign.warningGold : .secondary
            )

            MoneyMapSummaryRow(
                title: "Behind Goals",
                value: "\(digest.behindGoalCount)",
                detail: digest.behindGoalCount == 0 ? "No goal shortfalls detected" : "Need extra attention",
                systemImage: "target",
                tint: digest.behindGoalCount > 0 ? .orange : MoneyMapDesign.calmGreen
            )
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var priorityStepSection: some View {
        Section("Priorities") {
            Picker("Card Payoff", selection: $draft.payoffStrategy) {
                ForEach(CreditCardPayoffStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            Text(draft.payoffStrategy.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Allocation Style", selection: $draft.allocationStrategy) {
                ForEach(PaycheckAllocationStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            Text(draft.allocationStrategy.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var scenarioStepSection: some View {
        Section("Compare") {
            ForEach(scenarios) { scenario in
                RecommendationScenarioRow(scenario: scenario)
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var reviewOverviewSection: some View {
        Section("Plan Summary") {
            PaycheckPlanOverviewPanel(
                totalAvailable: plan.totalAvailable,
                cardPaymentTotal: cardPaymentTotal,
                goalContributionTotal: goalContributionTotal,
                unallocatedCash: plan.unallocatedCash,
                summary: plan.summary
            )
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var cardPaymentReviewSection: some View {
        Section("Debt Payoff") {
            if plan.creditCardPayments.isEmpty {
                MoneyMapEmptyState(
                    title: "No Debt Payoff Yet",
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

    private var goalContributionReviewSection: some View {
        Section("Savings Goals") {
            if plan.goalContributions.isEmpty {
                MoneyMapEmptyState(
                    title: "No Savings Plan Yet",
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

    private func advance() {
        guard !primaryActionDisabled else { return }

            if let nextStep = currentStep.next {
                move(to: nextStep, direction: 1)
            } else {
            onSave(draft)
            dismiss()
        }
    }

    private func move(to step: AllocationGuidedStep, direction: Int) {
        stepNavigationDirection = direction
        withAnimation(.smooth(duration: 0.32)) {
            currentStep = step
        }
    }

    private func paycheckAccountPickerTitle(for account: PaycheckCashAccount) -> String {
        let institution = account.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bankPrefix = institution.map { $0.isEmpty ? "" : "\($0) - " } ?? ""
        let suffix = account.lastFourLabel.map { " - \($0)" } ?? ""
        return "\(bankPrefix)\(account.displayName)\(suffix)"
    }

    private func paycheckAccountDetail(for account: PaycheckCashAccount) -> String {
        let balanceKind = account.availableBalance == nil && account.currentBalance != nil ? "current balance" : "available balance"
        let institution = account.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let institutionLabel = institution.flatMap { $0.isEmpty ? nil : $0 }
        let accountName = [institutionLabel, account.displayName]
            .compactMap { $0 }
            .joined(separator: " - ")
        return "\(balanceKind.capitalized) from \(accountName)"
    }
}

private struct SavedExtraMoneyPlanRow: View {
    let plan: ExtraMoneyPlan
    let itemCount: Int
    let pendingPaymentCount: Int
    let matchedPaymentCount: Int
    let canApplyPayments: Bool
    let onViewDetails: () -> Void
    let onApplyPayments: () -> Void
    let onCancel: () -> Void
    let onUndo: () -> Void
    let onDelete: () -> Void

    private var allocatedTotal: Double {
        plan.plannedCardAmount + plan.plannedGoalAmount
    }

    private var statusColor: Color {
        switch plan.status {
        case .active:
            return plan.appliedAt == nil ? MoneyMapDesign.calmGreen : MoneyMapDesign.warningGold
        case .canceled, .undone:
            return MoneyMapDesign.warningGold
        case .completed:
            return .blue
        }
    }

    private var statusTitle: String {
        if plan.status == .active, plan.appliedAt != nil {
            return "Payment Pending"
        }

        return plan.status.title
    }

    private var statusImage: String {
        if plan.status == .active, plan.appliedAt != nil {
            return "clock"
        }

        return plan.status == .active ? "lock.fill" : "clock"
    }

    private var statusDetail: String {
        if plan.appliedAt != nil, pendingPaymentCount > 0 {
            return "\(pendingPaymentCount) pending bank match\(pendingPaymentCount == 1 ? "" : "es")"
        }

        if matchedPaymentCount > 0 {
            return "\(matchedPaymentCount) payment\(matchedPaymentCount == 1 ? "" : "s") confirmed"
        }

        return "\(itemCount) decision\(itemCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.sourceAccountNameText ?? "Extra Money")
                        .font(.body.weight(.semibold))
                    Text(plan.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                MoneyMapMoneyText(
                    amount: allocatedTotal,
                    font: .body.weight(.semibold),
                    foregroundStyle: .primary
                )
            }

            HStack(spacing: 8) {
                Label(statusTitle, systemImage: statusImage)
                    .foregroundStyle(statusColor)
                Text(statusDetail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .font(.caption.weight(.semibold))

            HStack(spacing: 10) {
                MoneyMapMetricTile(
                    title: "Cards",
                    value: MoneyMapFormatters.currencyString(for: plan.plannedCardAmount),
                    systemImage: "creditcard",
                    tint: .blue
                )
                MoneyMapMetricTile(
                    title: "Goals",
                    value: MoneyMapFormatters.currencyString(for: plan.plannedGoalAmount),
                    systemImage: "target",
                    tint: MoneyMapDesign.calmGreen
                )
            }

            if plan.status == .active {
                HStack(spacing: 14) {
                    if canApplyPayments {
                        Button("Apply Payments", action: onApplyPayments)
                    }
                    Button("View Details", action: onViewDetails)
                    Spacer(minLength: 0)
                    Menu {
                        if canApplyPayments {
                            Button(action: onApplyPayments) {
                                Label("Apply Payments", systemImage: "creditcard")
                            }
                        }

                        Button(role: .destructive, action: onCancel) {
                            Label("Cancel Plan", systemImage: "xmark.circle")
                        }

                        Button(action: onUndo) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }

                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
                .font(.caption.weight(.semibold))
            } else {
                HStack(spacing: 14) {
                    Button("View Details", action: onViewDetails)
                    Spacer(minLength: 0)
                    Button("Delete Plan", role: .destructive, action: onDelete)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(action: onViewDetails) {
                Label("View Details", systemImage: "list.bullet.rectangle")
            }

            if plan.status == .active {
                if canApplyPayments {
                    Button(action: onApplyPayments) {
                        Label("Apply Payments", systemImage: "creditcard")
                    }
                }

                Button(role: .destructive, action: onCancel) {
                    Label("Cancel Plan", systemImage: "xmark.circle")
                }

                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Plan", systemImage: "trash")
            }
        }
    }
}

private struct SavedExtraMoneyPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: ExtraMoneyPlan
    let items: [ExtraMoneyPlanItem]
    let onApplyPayments: () -> Void

    private var cardItems: [ExtraMoneyPlanItem] {
        items.filter { $0.kind == .creditCardPayment }
    }

    private var goalItems: [ExtraMoneyPlanItem] {
        items.filter { $0.kind == .goalContribution }
    }

    private var flexibleItems: [ExtraMoneyPlanItem] {
        items.filter { $0.kind == .flexibleCash }
    }

    private var canApplyPayments: Bool {
        plan.status == .active &&
            plan.appliedAt == nil &&
            cardItems.contains { $0.matchedTransactionIDText == nil }
    }

    private var allocatedTotal: Double {
        plan.plannedCardAmount + plan.plannedGoalAmount
    }

    private var sourceTitle: String {
        plan.sourceAccountNameText ?? (plan.source == .manual ? "Manual amount" : "Bank account")
    }

    var body: some View {
        List {
            Section("Summary") {
                MoneyMapSummaryRow(
                    title: "Source",
                    value: sourceTitle,
                    detail: plan.createdAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: plan.source == .linkedAccount ? "building.columns" : "keyboard",
                    tint: .blue
                )

                MoneyMapSummaryRow(
                    title: "Status",
                    value: statusTitle,
                    detail: statusDetail,
                    systemImage: statusImage,
                    tint: statusColor
                )

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    MoneyMapMetricTile(
                        title: "Available",
                        value: MoneyMapFormatters.currencyString(for: plan.availableAmount),
                        systemImage: "banknote",
                        tint: .purple
                    )
                    MoneyMapMetricTile(
                        title: "Allocated",
                        value: MoneyMapFormatters.currencyString(for: allocatedTotal),
                        systemImage: "checkmark.circle",
                        tint: MoneyMapDesign.calmGreen
                    )
                    MoneyMapMetricTile(
                        title: "Unallocated",
                        value: MoneyMapFormatters.currencyString(for: plan.unallocatedAmount),
                        systemImage: "dollarsign.circle",
                        tint: plan.unallocatedAmount > 0 ? MoneyMapDesign.warningGold : .secondary
                    )
                }
                .padding(.vertical, 4)
            }
            .moneyMapListSectionBackground()

            if canApplyPayments {
                Section("Payments") {
                    Button {
                        onApplyPayments()
                    } label: {
                        MoneyMapActionListRow(
                            title: "Apply Payments",
                            detail: "Move saved card payments into pending status until matching bank debits import.",
                            systemImage: "creditcard",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                }
                .moneyMapListSectionBackground()
            }

            planItemSection(
                title: "Card Payments",
                items: cardItems,
                emptyTitle: "No card payments saved"
            )

            planItemSection(
                title: "Goal Contributions",
                items: goalItems,
                emptyTitle: "No goal contributions saved"
            )

            if !flexibleItems.isEmpty {
                planItemSection(
                    title: "Flexible Cash",
                    items: flexibleItems,
                    emptyTitle: "No flexible cash saved"
                )
            }

            Section("Cash Accounting") {
                SavedExtraMoneyPlanAccountingRow(
                    title: "Starting balance",
                    amount: plan.startingBalanceAmount
                )
                SavedExtraMoneyPlanAccountingRow(
                    title: "Already reserved",
                    amount: plan.alreadyAllocatedAmount
                )
                SavedExtraMoneyPlanAccountingRow(
                    title: "Available for this plan",
                    amount: plan.availableAmount
                )
            }
            .moneyMapListSectionBackground()
        }
        .listStyle(.insetGrouped)
        .moneyMapGroupedListBackground()
        .navigationTitle("Plan Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func planItemSection(
        title: String,
        items: [ExtraMoneyPlanItem],
        emptyTitle: String
    ) -> some View {
        Section(title) {
            if items.isEmpty {
                Label(emptyTitle, systemImage: "tray")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    SavedExtraMoneyPlanItemRow(item: item, isAppliedPlan: plan.appliedAt != nil)
                }
            }
        }
        .moneyMapListSectionBackground()
    }

    private var payoffStrategyTitle: String {
        CreditCardPayoffStrategy(rawValue: plan.payoffStrategyRaw)?.title ?? "Balanced"
    }

    private var allocationStrategyTitle: String {
        PaycheckAllocationStrategy(rawValue: plan.strategyRaw)?.title ?? "Balanced"
    }

    private var statusColor: Color {
        switch plan.status {
        case .active:
            return plan.appliedAt == nil ? MoneyMapDesign.calmGreen : MoneyMapDesign.warningGold
        case .canceled, .undone:
            return MoneyMapDesign.warningGold
        case .completed:
            return .blue
        }
    }

    private var statusTitle: String {
        if plan.status == .active, plan.appliedAt != nil {
            return "Payment Pending"
        }

        return plan.status.title
    }

    private var statusImage: String {
        if plan.status == .active, plan.appliedAt != nil {
            return "clock"
        }

        return plan.status == .active ? "lock.fill" : "clock"
    }

    private var statusDetail: String {
        if let appliedAt = plan.appliedAt {
            return plan.status == .completed
                ? "Confirmed from bank transactions"
                : "Applied \(appliedAt.formatted(date: .abbreviated, time: .shortened)); waiting for bank match"
        }

        return "\(allocationStrategyTitle) allocation, \(payoffStrategyTitle) payoff"
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 104), spacing: 10)
        ]
    }
}

private struct SavedExtraMoneyPlanItemRow: View {
    let item: ExtraMoneyPlanItem
    let isAppliedPlan: Bool
    @State private var isShowingReason = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.targetNameText)
                        .font(.body.weight(.semibold))
                    Text(kindTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                MoneyMapMoneyText(
                    amount: item.amountValue,
                    font: .body.weight(.semibold),
                    foregroundStyle: .primary
                )
            }

            if let paymentStatusText {
                Label(paymentStatusText, systemImage: paymentStatusImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paymentStatusTint)
                    .padding(.leading, 38)
            }

            if let rationale = item.rationaleText?.nilIfBlank {
                DisclosureGroup(isExpanded: $isShowingReason) {
                    Text(rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } label: {
                    Label("Why this", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 3)
    }

    private var kindTitle: String {
        switch item.kind {
        case .creditCardPayment:
            if item.matchedTransactionIDText != nil {
                return "Card payment confirmed"
            }

            if isAppliedPlan {
                return "Card payment pending"
            }

            return "Card payment"
        case .goalContribution:
            return "Goal contribution"
        case .flexibleCash:
            return "Flexible cash"
        }
    }

    private var systemImage: String {
        switch item.kind {
        case .creditCardPayment:
            return "creditcard"
        case .goalContribution:
            return "target"
        case .flexibleCash:
            return "dollarsign.circle"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .creditCardPayment:
            return .blue
        case .goalContribution:
            return MoneyMapDesign.calmGreen
        case .flexibleCash:
            return MoneyMapDesign.warningGold
        }
    }

    private var paymentStatusText: String? {
        guard item.kind == .creditCardPayment else { return nil }

        if let matchedAt = item.matchedAt {
            return "Confirmed \(matchedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        if isAppliedPlan {
            return "Waiting for a matching posted bank debit"
        }

        return nil
    }

    private var paymentStatusImage: String {
        item.matchedTransactionIDText == nil ? "clock" : "checkmark.circle.fill"
    }

    private var paymentStatusTint: Color {
        item.matchedTransactionIDText == nil ? MoneyMapDesign.warningGold : MoneyMapDesign.calmGreen
    }
}

private struct SavedExtraMoneyPlanAccountingRow: View {
    let title: String
    let amount: Double

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            MoneyMapMoneyText(
                amount: amount,
                font: .body,
                foregroundStyle: .primary
            )
        }
    }
}

private struct PaycheckPlanOverviewPanel: View {
    let totalAvailable: Double
    let cardPaymentTotal: Double
    let goalContributionTotal: Double
    let unallocatedCash: Double
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Available to allocate now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MoneyMapMoneyText(
                        amount: totalAvailable,
                        font: .title2.weight(.semibold),
                        foregroundStyle: .primary
                    )
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
    @State private var isShowingReason = false

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

                Text(recommendation.decisionSummary)
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

                DisclosureGroup(isExpanded: $isShowingReason) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(recommendation.decisionDetails, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                } label: {
                    Label("Why this", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GoalContributionRecommendationRow: View {
    let insight: GoalSavingInsight
    @State private var isShowingReason = false

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

                Text("Target each cycle: \(MoneyMapFormatters.currencyString(for: insight.targetPerPaycheck))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(scheduleDetail)
                    .font(.subheadline)
                    .foregroundStyle(insight.isBehindSchedule ? .orange : .secondary)

                DisclosureGroup(isExpanded: $isShowingReason) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(insight.decisionDetails, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                } label: {
                    Label("Why this", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(insight.isBehindSchedule ? .orange : MoneyMapDesign.calmGreen)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension CreditCardPaymentRecommendation {
    var decisionSummary: String {
        if recommendedPayment >= activeBalance - 0.01 {
            return "Pays off the active balance."
        }

        if minimumPayment > 0, recommendedPayment >= minimumPayment {
            return "Covers the minimum, then adds extra toward the active balance."
        }

        return rationale
    }

    var decisionExplanation: String {
        decisionDetails.joined(separator: " ")
    }

    var decisionDetails: [String] {
        var details: [String] = [
            rationale,
            "Active balance considered: \(MoneyMapFormatters.currencyString(for: activeBalance)).",
            "Recommended payment: \(MoneyMapFormatters.currencyString(for: recommendedPayment))."
        ]

        if minimumPayment > 0 {
            details.append("Minimum payment: \(MoneyMapFormatters.currencyString(for: minimumPayment)).")
        }

        if let dueDate {
            details.append("Due date: \(MoneyMapFormatters.mediumDateString(for: dueDate)).")
        }

        if utilization > 0 {
            details.append("Utilization: \(utilization.formatted(.percent.precision(.fractionLength(0)))).")
        }

        if let annualPercentageRate {
            details.append("APR: \(annualPercentageRate.formatted(.percent.precision(.fractionLength(1)))).")
        }

        if recommendedPayment < activeBalance - 0.01 {
            details.append("This is a partial payoff because the plan spreads available card cash across active cards by urgency, utilization, APR, and balance.")
        }

        return details
    }
}

private extension GoalSavingInsight {
    var decisionExplanation: String {
        decisionDetails.joined(separator: " ")
    }

    var decisionDetails: [String] {
        var details: [String] = [
            "Recommended contribution: \(MoneyMapFormatters.currencyString(for: recommendedContribution)).",
            "Target each cycle: \(MoneyMapFormatters.currencyString(for: targetPerPaycheck))."
        ]

        if isBehindSchedule {
            details.insert("Included because this goal is behind schedule.", at: 0)
            if shortfallAmount > 0 {
                details.append("Estimated shortfall: \(MoneyMapFormatters.currencyString(for: shortfallAmount)).")
            }
        } else {
            details.insert("Included because there was room for goal progress after higher-priority card needs.", at: 0)
        }

        return details
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
                        Text("Allocation Plan")
                            .font(.largeTitle.bold())
                        Text("This screen helps you decide what to do with money you have available right now.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        WelcomeStep(
                            number: 1,
                            title: "Choose the money to allocate",
                            message: "Start with the money you want to put toward credit cards and savings goals right now."
                        )
                        WelcomeStep(
                            number: 2,
                            title: "Pick your strategy",
                            message: "Card Payoff changes which credit cards get priority. Allocation Style changes how much of your cash leans toward debt versus savings goals."
                        )
                        WelcomeStep(
                            number: 3,
                            title: "Review and save the plan",
                            message: "Save the allocation when it looks right so MoneyMap knows those dollars are already spoken for."
                        )
                        WelcomeStep(
                            number: 4,
                            title: "Apply only when needed",
                            message: "Apply buttons update your cards and goals immediately. Use them only when you want MoneyMap to record those changes now."
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Best Results")
                            .font(.headline)

                        WelcomeStatusRow(
                            title: "Planning timing is set",
                            detail: "Useful for bill urgency and goal pacing.",
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
