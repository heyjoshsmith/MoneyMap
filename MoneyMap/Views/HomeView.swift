//
//  HomeView.swift
//  MoneyMap
//
//  Created by Codex on 6/5/26.
//

import SwiftUI
import SwiftData
import AppIntents

enum HomeNavigationTarget: String, Identifiable {
    case payday
    case recommendations
    case upcomingBills
    case assistant

    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject private var paydayManager: PaydayManager
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @Query private var bills: [Bill]
    @Query(sort: \Goal.deadline, order: .forward) private var goals: [Goal]
    @Query private var paydayConfigs: [PaydayConfig]

    @State private var destination: HomeNavigationTarget?
    @State private var showingAddBill = false
    @State private var showingAddGoal = false
    @State private var showingSettings = false
    @State private var showingBillReview = false
    @State private var billsRefreshToken = 0
    @State private var didScheduleInitialDonations = false

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var hasPayday: Bool {
        paydayManager.nextPayday != nil
    }

    private var hasBills: Bool {
        !bills.isEmpty
    }

    private var hasGoals: Bool {
        !goals.isEmpty
    }

    private var payAmount: Double {
        paydayConfigs.first?.amountPerPayday ?? 0
    }

    private var setupIsComplete: Bool {
        hasPayday && hasBills
    }

    private var activeGoals: [Goal] {
        goals.filter { $0.remainingAmount > 0 }
    }

    private var dueBeforePaydayTotal: Double {
        billsBeforePayday.totalAmount
    }

    private var billsForReview: [Bill] {
        overdueBills.isEmpty ? billsBeforePayday : overdueBills
    }

    private var leftAfterBills: Double? {
        guard payAmount > 0 else { return nil }
        return payAmount - dueBeforePaydayTotal
    }

    private var billsBeforePayday: [Bill] {
        guard let nextPayday = paydayManager.nextPayday else { return [] }
        return bills.withoutCreditCards
            .filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                return dueDate <= nextPayday && bill.status != .paid
            }
            .sorted(by: Bill.byDate)
    }

    private var overdueBills: [Bill] {
        bills.withoutCreditCards
            .filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                return Calendar.current.startOfDay(for: dueDate) < today && bill.status != .paid
            }
            .sorted(by: Bill.byDate)
    }

    private var setupSteps: [SetupStep] {
        [
            SetupStep(
                title: "Set your next payday",
                detail: "Everything in MoneyMap gets easier once the app knows your next paycheck date.",
                isComplete: hasPayday,
                actionTitle: "Set Payday",
                action: .payday
            ),
            SetupStep(
                title: "Add the bills you need to cover",
                detail: "Start with the bills due before your next payday.",
                isComplete: hasBills,
                actionTitle: "Add Bill",
                action: .addBill
            ),
            SetupStep(
                title: "Add a savings goal",
                detail: "Optional, but useful if you want the app to split money between debt and savings.",
                isComplete: hasGoals,
                actionTitle: "Add Goal",
                action: .addGoal
            )
        ]
    }

    private var todayAnswer: TodayAnswer {
        if !hasPayday {
            return TodayAnswer(
                eyebrow: "First step",
                title: "Set your next payday",
                metric: "Start here",
                detail: "MoneyMap uses payday timing to decide which bills and goals matter first.",
                systemImage: "calendar.badge.plus",
                tint: .blue,
                actionTitle: "Set Payday",
                action: .payday
            )
        }

        if !hasBills {
            return TodayAnswer(
                eyebrow: "Next step",
                title: "Add the bills you need to cover",
                metric: "No bills yet",
                detail: "Once bills are in, Today can show what needs attention before payday.",
                systemImage: "list.bullet.clipboard",
                tint: .blue,
                actionTitle: "Add Bill",
                action: .addBill
            )
        }

        if !overdueBills.isEmpty {
            return TodayAnswer(
                eyebrow: "Needs attention",
                title: "\(overdueBills.count) bill\(overdueBills.count == 1 ? "" : "s") overdue",
                metric: MoneyMapFormatters.currencyString(for: overdueBills.totalAmount),
                detail: "Handle overdue bills before using the paycheck plan.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .red,
                actionTitle: "Review Bills",
                action: .reviewBills
            )
        }

        if let leftAfterBills {
            if leftAfterBills < 0 {
                return TodayAnswer(
                    eyebrow: "Before payday",
                    title: "Payday needs attention",
                    metric: "\(MoneyMapFormatters.currencyString(for: abs(leftAfterBills))) short",
                    detail: "Bills due before payday are higher than the paycheck amount currently saved in MoneyMap.",
                    systemImage: "exclamationmark.circle.fill",
                    tint: .orange,
                    actionTitle: "Plan Paycheck",
                    action: .recommendations
                )
            }

            if !hasGoals {
                return TodayAnswer(
                    eyebrow: "Before payday",
                    title: dueBeforePaydayTotal > 0 ? "Bills are mapped through payday" : "No bills due before payday",
                    metric: "\(MoneyMapFormatters.currencyString(for: leftAfterBills)) left",
                    detail: "Add a savings goal when you want MoneyMap to guide what happens after bills.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    actionTitle: "Add Goal",
                    action: .addGoal
                )
            }

            return TodayAnswer(
                eyebrow: "Before payday",
                title: dueBeforePaydayTotal > 0 ? "You're covered through payday" : "No bills due before payday",
                metric: "\(MoneyMapFormatters.currencyString(for: leftAfterBills)) left",
                detail: "Use Plan when you're ready to split the remaining money across cards and goals.",
                systemImage: "checkmark.circle.fill",
                tint: .green,
                actionTitle: "Plan Paycheck",
                action: .recommendations
            )
        }

        return TodayAnswer(
            eyebrow: "Before payday",
            title: "Ready for a paycheck plan",
            metric: dueBeforePaydayTotal > 0 ? MoneyMapFormatters.currencyString(for: dueBeforePaydayTotal) : "No bills due",
            detail: "Add the money you want to plan so MoneyMap can split it across bills, cards, and goals.",
            systemImage: "wand.and.stars",
            tint: .purple,
            actionTitle: "Plan Paycheck",
            action: .recommendations
        )
    }

    var body: some View {
        NavigationStack {
            List {
                answerSection

                if !setupIsComplete {
                    setupSection
                }

                glanceSection

                if setupIsComplete {
                    beforePaydaySection
                }

                actionsSection
            }
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingAddBill) {
                BillEditor()
            }
            .sheet(isPresented: $showingAddGoal) {
                NavigationStack {
                    AddGoalView()
                }
            }
            .sheet(isPresented: $showingSettings) {
                Settings()
            }
            .fullScreenCover(isPresented: $showingBillReview) {
                BillReviewFlowView(bills: billsForReview)
            }
            .navigationDestination(item: $destination) { target in
                switch target {
                case .payday:
                    PaydayView()
                case .recommendations:
                    RecommendationsView()
                case .upcomingBills:
                    BillsView(mode: .upcoming)
                case .assistant:
                    MoneyMapAssistantView()
                }
            }
            .userActivity("com.heyjoshsmith.MoneyMap.viewingHome") { activity in
                let paydayConfig = paydayConfigs.first
                let entity = PaydayStatusEntity(
                    nextPayday: paydayManager.nextPayday ?? paydayConfig?.nextPayday,
                    amountPerPayday: paydayConfig?.amountPerPayday,
                    savingsPerPaycheck: paydayConfig?.savingsPerPaycheck
                )
                activity.title = "Viewing Today"
                activity.appEntityIdentifier = EntityIdentifier(for: entity)
            }
            .onAppear {
                routeToRequestedDestinationIfNeeded()
                scheduleInitialIntentDonations()
            }
            .onChange(of: deepLinkManager.requestedPayDestination) { _, _ in
                routeToRequestedDestinationIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppRefreshEvents.billsDidChange)) { _ in
                billsRefreshToken += 1
            }
        }
    }

    private var answerSection: some View {
        Section {
            let _ = billsRefreshToken
            TodayAnswerPanel(answer: todayAnswer) {
                run(todayAnswer.action)
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var setupSection: some View {
        Section("Get Started") {
            Text("Start with your next payday and the bills you need to cover before then. Goals can come after that.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(setupSteps) { step in
                SetupStepRow(step: step) {
                    run(step.action)
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private func scheduleInitialIntentDonations() {
        guard !didScheduleInitialDonations else { return }
        didScheduleInitialDonations = true

        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            MoneyMapIntentDonations.donateNextPayday()
            MoneyMapIntentDonations.donateCashAfterBills()
        }
    }

    private var glanceSection: some View {
        Section("At a Glance") {
            if let nextPayday = paydayManager.nextPayday {
                MoneyMapSummaryRow(
                    title: "Next Payday",
                    value: MoneyMapFormatters.mediumDateString(for: nextPayday),
                    detail: "\(paydayManager.daysUntilNextPayday()) day\(paydayManager.daysUntilNextPayday() == 1 ? "" : "s") away",
                    systemImage: "calendar"
                )
            } else {
                MoneyMapSummaryRow(
                    title: "Next Payday",
                    value: "Not set",
                    detail: "Set it to unlock clearer planning.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            }

            MoneyMapSummaryRow(
                title: "Bills Before Payday",
                value: "\(billsBeforePayday.count)",
                detail: MoneyMapFormatters.currencyString(for: billsBeforePayday.totalAmount),
                systemImage: "banknote"
            )

            MoneyMapSummaryRow(
                title: "Goals",
                value: "\(goals.count)",
                detail: hasGoals ? "\(activeGoals.count) still in progress" : "Optional for now",
                systemImage: "target"
            )

            if payAmount > 0 {
                let leftAfterBills = max(payAmount - billsBeforePayday.totalAmount, 0)
                MoneyMapSummaryRow(
                    title: "Left After Bills",
                    value: MoneyMapFormatters.currencyString(for: leftAfterBills),
                    detail: "Based on your current paycheck amount",
                    systemImage: "dollarsign.circle"
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                destination = .recommendations
                MoneyMapIntentDonations.donatePaycheckPlan(availableCash: payAmount > 0 ? payAmount : nil)
            } label: {
                MoneyMapActionListRow(
                    title: "Plan This Paycheck",
                    detail: "Review suggested card payments and goal contributions.",
                    systemImage: "wand.and.stars"
                )
            }
            .buttonStyle(.plain)

            if !billsBeforePayday.isEmpty {
                Button {
                    destination = .upcomingBills
                } label: {
                    MoneyMapActionListRow(
                        title: "Review Upcoming Bills",
                        detail: "See every bill due before the next payday.",
                        systemImage: "calendar.badge.exclamationmark",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                destination = .assistant
            } label: {
                MoneyMapActionListRow(
                    title: "Ask MoneyMap",
                    detail: "Search your data or ask a question.",
                    systemImage: "sparkles",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)

            Button {
                showingAddBill = true
            } label: {
                Label("Add Bill", systemImage: "plus")
            }

            Button {
                showingAddGoal = true
            } label: {
                Label("Add Goal", systemImage: "target")
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var beforePaydaySection: some View {
        Section("Before Payday") {
            if billsBeforePayday.isEmpty {
                MoneyMapEmptyState(
                    title: "Nothing due before payday",
                    message: "Your next pay cycle has breathing room.",
                    systemImage: "checkmark.circle"
                )
            } else {
                ForEach(billsBeforePayday.prefix(4)) { bill in
                    NavigationLink {
                        BillView(bill: bill)
                    } label: {
                        TodayBillDueRow(bill: bill)
                    }
                }

                if billsBeforePayday.count > 4 {
                    Button("See All Upcoming Bills") {
                        destination = .upcomingBills
                    }
                }
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private func routeToRequestedDestinationIfNeeded() {
        guard let requested = deepLinkManager.requestedPayDestination else { return }
        switch requested {
        case .recommendations:
            destination = .recommendations
        }
        deepLinkManager.requestedPayDestination = nil
    }

    private func run(_ action: HomeAction) {
        switch action {
        case .payday:
            destination = .payday
        case .recommendations:
            destination = .recommendations
        case .reviewBills:
            showingBillReview = true
        case .upcomingBills:
            destination = .upcomingBills
        case .addBill:
            showingAddBill = true
        case .addGoal:
            showingAddGoal = true
        }
    }
}

private struct SetupStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
    let actionTitle: String
    let action: HomeAction
}

private struct SetupStepRow: View {
    let step: SetupStep
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(step.isComplete ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if !step.isComplete {
                Button(step.actionTitle, action: onTap)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TodayAnswer {
    let eyebrow: String
    let title: String
    let metric: String
    let detail: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let action: HomeAction
}

private struct TodayAnswerPanel: View {
    let answer: TodayAnswer
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(answer.eyebrow, systemImage: answer.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(answer.tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(answer.title)
                    .font(.title3.weight(.semibold))
                Text(answer.metric)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(answer.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: action) {
                MoneyMapNeutralButtonLabel(
                    title: answer.actionTitle,
                    systemImage: answer.systemImage,
                    iconColor: answer.tint,
                    fillsWidth: false
                )
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct TodayBillDueRow: View {
    let bill: Bill

    private var dueText: String {
        if bill.lifecycleState != .active {
            return bill.lifecycleState.title
        }
        guard let dueDate = bill.dueDate else { return "No due date" }
        if bill.status == .paid {
            return "Paid"
        }
        if Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date()) {
            return "Overdue"
        }
        return "Due \(MoneyMapFormatters.mediumDateString(for: dueDate))"
    }

    private var statusColor: Color {
        bill.displayStatusColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: bill.category?.icon ?? "questionmark.circle")
                .font(.headline)
                .foregroundStyle(statusColor)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(bill.name ?? "Untitled")
                    .font(.headline)
                    .lineLimit(1)
                Text(dueText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 12)

            MoneyMapMoneyText(amount: bill.amount ?? 0)
        }
        .padding(.vertical, 3)
    }
}

private enum HomeAction {
    case payday
    case recommendations
    case reviewBills
    case upcomingBills
    case addBill
    case addGoal
}

#Preview {
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    HomeView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .modelContainer(container)
}
