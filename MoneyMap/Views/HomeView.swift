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
    @State private var billsRefreshToken = 0

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

    private var nextAction: NextAction {
        if !hasPayday {
            return .setPayday
        }
        if !hasBills {
            return .addBill
        }
        if !overdueBills.isEmpty {
            return .reviewBills
        }
        if payAmount <= 0 {
            return .planPaycheck
        }
        if !hasGoals {
            return .addGoal
        }
        return .planPaycheck
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

    var body: some View {
        NavigationStack {
            List {
                if !hasPayday || !hasBills {
                    setupSection
                }

                overviewSection
                nextActionSection
                quickActionsSection

                if !billsBeforePayday.isEmpty {
                    dueBeforePaydaySection
                }
            }
            .navigationTitle("Home")
            .sheet(isPresented: $showingAddBill) {
                BillEditor()
            }
            .sheet(isPresented: $showingAddGoal) {
                NavigationStack {
                    AddGoalView()
                }
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
                activity.title = "Viewing Home"
                activity.appEntityIdentifier = EntityIdentifier(for: entity)
            }
            .onAppear {
                routeToRequestedDestinationIfNeeded()
                MoneyMapIntentDonations.donateNextPayday()
                MoneyMapIntentDonations.donateCashAfterBills()
            }
            .onChange(of: deepLinkManager.requestedPayDestination) { _, _ in
                routeToRequestedDestinationIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppRefreshEvents.billsDidChange)) { _ in
                billsRefreshToken += 1
            }
        }
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
    }

    private var overviewSection: some View {
        Section("Overview") {
            if let nextPayday = paydayManager.nextPayday {
                HomeSummaryRow(
                    title: "Next Payday",
                    value: MoneyMapFormatters.mediumDateString(for: nextPayday),
                    detail: "\(paydayManager.daysUntilNextPayday()) day\(paydayManager.daysUntilNextPayday() == 1 ? "" : "s") away",
                    systemImage: "calendar"
                )
            } else {
                HomeSummaryRow(
                    title: "Next Payday",
                    value: "Not set",
                    detail: "Set it to unlock clearer planning.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            }

            HomeSummaryRow(
                title: "Bills Before Payday",
                value: "\(billsBeforePayday.count)",
                detail: MoneyMapFormatters.currencyString(for: billsBeforePayday.totalAmount),
                systemImage: "banknote"
            )

            HomeSummaryRow(
                title: "Goals",
                value: "\(goals.count)",
                detail: hasGoals ? "\(goals.filter { $0.remainingAmount > 0 }.count) still in progress" : "Optional for now",
                systemImage: "target"
            )

            if payAmount > 0 {
                let leftAfterBills = max(payAmount - billsBeforePayday.totalAmount, 0)
                HomeSummaryRow(
                    title: "Left After Bills",
                    value: MoneyMapFormatters.currencyString(for: leftAfterBills),
                    detail: "Based on your current paycheck amount",
                    systemImage: "dollarsign.circle"
                )
            }
        }
    }

    private var nextActionSection: some View {
        Section("What To Do Next") {
            VStack(alignment: .leading, spacing: 8) {
                let _ = billsRefreshToken
                Text(nextAction.title)
                    .font(.headline)
                Text(nextAction.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(nextAction.buttonTitle) {
                    run(nextAction.action)
                }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private var quickActionsSection: some View {
        Section("Quick Actions") {
            Button {
                destination = .recommendations
                MoneyMapIntentDonations.donatePaycheckPlan(availableCash: payAmount > 0 ? payAmount : nil)
            } label: {
                Label("Plan This Paycheck", systemImage: "wand.and.stars")
            }

            Button {
                destination = .upcomingBills
            } label: {
                Label("Review Upcoming Bills", systemImage: "calendar.badge.exclamationmark")
            }

            Button {
                destination = .assistant
            } label: {
                Label("Search and Ask", systemImage: "magnifyingglass")
            }

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
    }

    private var dueBeforePaydaySection: some View {
        Section("Due Before Payday") {
            ForEach(billsBeforePayday.prefix(4)) { bill in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(bill.name ?? "Untitled")
                        Spacer()
                        Text((bill.amount ?? 0), format: .currency(code: "USD"))
                    }
                    .font(.subheadline.weight(.semibold))

                    if let dueDate = bill.dueDate {
                        Text("Due \(MoneyMapFormatters.mediumDateString(for: dueDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            if billsBeforePayday.count > 4 {
                Button("See All Upcoming Bills") {
                    destination = .upcomingBills
                }
            }
        }
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

private struct HomeSummaryRow: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.accent)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private enum HomeAction {
    case payday
    case recommendations
    case upcomingBills
    case addBill
    case addGoal
}

private enum NextAction {
    case setPayday
    case addBill
    case reviewBills
    case planPaycheck
    case addGoal

    var title: String {
        switch self {
        case .setPayday:
            return "Set your next payday first"
        case .addBill:
            return "Add your first bill"
        case .reviewBills:
            return "Review bills due before payday"
        case .planPaycheck:
            return "Plan what to do with this paycheck"
        case .addGoal:
            return "Add a goal if you want savings guidance"
        }
    }

    var detail: String {
        switch self {
        case .setPayday:
            return "That gives MoneyMap the timing it needs to organize everything else."
        case .addBill:
            return "Start with the bills you know are coming up next."
        case .reviewBills:
            return "You have unpaid bills that need attention before your next paycheck."
        case .planPaycheck:
            return "Use the planning engine once your payday and bills are in place."
        case .addGoal:
            return "Goals are optional, but they make the paycheck plan more useful."
        }
    }

    var buttonTitle: String {
        switch self {
        case .setPayday:
            return "Set Payday"
        case .addBill:
            return "Add Bill"
        case .reviewBills:
            return "Review Bills"
        case .planPaycheck:
            return "Plan Paycheck"
        case .addGoal:
            return "Add Goal"
        }
    }

    var action: HomeAction {
        switch self {
        case .setPayday:
            return .payday
        case .addBill:
            return .addBill
        case .reviewBills:
            return .upcomingBills
        case .planPaycheck:
            return .recommendations
        case .addGoal:
            return .addGoal
        }
    }
}

#Preview {
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    HomeView()
        .environmentObject(paydayManager)
        .environmentObject(DeepLinkManager())
        .modelContainer(container)
}
