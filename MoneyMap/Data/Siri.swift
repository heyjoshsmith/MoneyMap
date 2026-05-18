//
//  Siri.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/27/25.
//

import Foundation
import AppIntents
import SwiftUI

enum BillCategoryIntentOption: String, AppEnum {
    case utilities
    case creditCard
    case rent
    case insurance
    case subscription
    case groceries
    case transportation
    case phone
    case internet
    case entertainment
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bill Category")
    static var caseDisplayRepresentations: [BillCategoryIntentOption: DisplayRepresentation] = [
        .utilities: "Utilities",
        .creditCard: "Credit Card",
        .rent: "Rent",
        .insurance: "Insurance",
        .subscription: "Subscription",
        .groceries: "Groceries",
        .transportation: "Transportation",
        .phone: "Phone",
        .internet: "Internet",
        .entertainment: "Entertainment",
        .other: "Other"
    ]

    var modelValue: BillCategory {
        switch self {
        case .utilities: return .utilities
        case .creditCard: return .creditCard
        case .rent: return .rent
        case .insurance: return .insurance
        case .subscription: return .subscription
        case .groceries: return .groceries
        case .transportation: return .transportation
        case .phone: return .phone
        case .internet: return .internet
        case .entertainment: return .entertainment
        case .other: return .other
        }
    }
}

enum RecurrenceUnitIntentOption: String, AppEnum {
    case day
    case week
    case month
    case year

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recurrence Unit")
    static var caseDisplayRepresentations: [RecurrenceUnitIntentOption: DisplayRepresentation] = [
        .day: "Day",
        .week: "Week",
        .month: "Month",
        .year: "Year"
    ]

    var modelValue: RecurrenceUnit {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }
}

struct BillEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bill")
    static var defaultQuery = BillEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GoalEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Goal")
    static var defaultQuery = GoalEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BillEntityQuery: EntityQuery {
    func entities(for identifiers: [BillEntity.ID]) async throws -> [BillEntity] {
        let bills = try MoneyMapBillStore.fetchBills()
        let identifierSet = Set(identifiers)
        return bills
            .filter { identifierSet.contains($0.id) }
            .map(BillEntity.init)
    }

    func suggestedEntities() async throws -> [BillEntity] {
        try MoneyMapBillStore.fetchBills()
            .sorted(by: Bill.byStatusDateUtilization)
            .map(BillEntity.init)
    }
}

struct GoalEntityQuery: EntityQuery {
    func entities(for identifiers: [GoalEntity.ID]) async throws -> [GoalEntity] {
        let goals = try MoneyMapPlanningStore.fetchGoals()
        let identifierSet = Set(identifiers)
        return goals
            .filter { identifierSet.contains($0.id) }
            .map(GoalEntity.init)
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        try MoneyMapPlanningStore.fetchGoals()
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .map(GoalEntity.init)
    }
}

private extension BillEntity {
    init(_ bill: Bill) {
        id = bill.id
        name = bill.name ?? "Untitled"
    }
}

private extension GoalEntity {
    init(_ goal: Goal) {
        id = goal.id
        name = goal.name ?? "Untitled"
    }
}

struct OpenBillIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Bill"
    static var description = IntentDescription("Open a specific bill in MoneyMap.")
    static var openAppWhenRun = true

    @Parameter(title: "Bill")
    var bill: BillEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$bill)")
    }

    func perform() async throws -> some IntentResult {
        PendingRouteStore.set(.openBill(bill.id))
        return .result()
    }
}

struct OpenGoalIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Goal"
    static var description = IntentDescription("Open a specific goal in MoneyMap.")
    static var openAppWhenRun = true

    @Parameter(title: "Goal")
    var goal: GoalEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$goal)")
    }

    func perform() async throws -> some IntentResult {
        PendingRouteStore.set(.openGoal(goal.id))
        return .result()
    }
}

struct AddBillIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Bill"
    static var description = IntentDescription("Create a new bill or credit card in MoneyMap.")
    static var openAppWhenRun = true

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Amount")
    var amount: Double?

    @Parameter(title: "Due Date")
    var dueDate: Date

    @Parameter(title: "Category")
    var category: BillCategoryIntentOption

    @Parameter(title: "Every")
    var recurrenceInterval: Int

    @Parameter(title: "Recurrence Unit")
    var recurrenceUnit: RecurrenceUnitIntentOption

    @Parameter(title: "Autopay")
    var autopayEnabled: Bool

    @Parameter(title: "Autopay Source")
    var autopaySource: String?

    @Parameter(title: "Notes")
    var notes: String?

    @Parameter(title: "Grace Period Days")
    var gracePeriodDays: Int?

    @Parameter(title: "Credit Limit")
    var creditLimit: Double?

    @Parameter(title: "Current Balance")
    var cardBalance: Double?

    @Parameter(title: "APR")
    var annualPercentageRate: Double?

    @Parameter(title: "Minimum Payment")
    var minimumPayment: Double?

    @Parameter(title: "Statement Balance")
    var statementBalance: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) due \(\.$dueDate)")
    }

    init() {
        name = ""
        amount = nil
        dueDate = .now
        category = .utilities
        recurrenceInterval = 1
        recurrenceUnit = .month
        autopayEnabled = false
        autopaySource = nil
        notes = nil
        gracePeriodDays = nil
        creditLimit = nil
        cardBalance = nil
        annualPercentageRate = nil
        minimumPayment = nil
        statementBalance = nil
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bill = try MoneyMapBillStore.addBill(
            name: name,
            amount: amount,
            dueDate: dueDate,
            category: category.modelValue,
            recurrenceInterval: recurrenceInterval,
            recurrenceUnit: recurrenceUnit.modelValue,
            autopayEnabled: autopayEnabled,
            notes: notes,
            autopaySource: autopaySource,
            gracePeriodDays: gracePeriodDays,
            creditLimit: creditLimit,
            cardBalance: cardBalance,
            annualPercentageRate: annualPercentageRate,
            minimumPayment: minimumPayment,
            statementBalance: statementBalance
        )
        let billName = bill.name ?? "bill"
        PendingRouteStore.set(.openBill(bill.id))
        return .result(dialog: IntentDialog(stringLiteral: "Added \(billName) to MoneyMap."))
    }
}

struct OpenRecommendationsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recommendations"
    static var description = IntentDescription("Open paycheck recommendations in MoneyMap.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRouteStore.set(.showRecommendations)
        return .result()
    }
}

struct GetPaycheckRecommendationIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Paycheck Plan"
    static var description = IntentDescription("Get recommended paycheck allocations for cards and goals.")

    @Parameter(title: "Available Cash")
    var availableCash: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Get paycheck plan")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let snapshot = try MoneyMapPlanningStore.snapshot()
        let cash = max(availableCash ?? snapshot.amountPerPayday, 0)
        let plan = FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: cash,
            goals: snapshot.goals,
            bills: snapshot.bills,
            nextPayday: snapshot.nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )

        let topCard = plan.creditCardPayments.first.map {
            "\($0.billName) \(MoneyMapFormatters.currencyString(for: $0.recommendedPayment))"
        } ?? "no card payment"
        let topGoal = plan.goalContributions.first.map {
            "\($0.goalName) \(MoneyMapFormatters.currencyString(for: $0.recommendedContribution))"
        } ?? "no goal contribution"
        let spoken = "For \(MoneyMapFormatters.currencyString(for: cash)), start with \(topCard), then \(topGoal)."
        let visual = [
            plan.summary,
            "Top card: \(topCard)",
            "Top goal: \(topGoal)"
        ].joined(separator: "\n")

        return .result(value: visual, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct ComparePaycheckScenariosIntent: AppIntent {
    static var title: LocalizedStringResource = "Compare Paycheck Scenarios"
    static var description = IntentDescription("Compare lean, planned, and stretch paycheck strategies.")

    @Parameter(title: "Base Cash")
    var baseCash: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Compare paycheck scenarios")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let snapshot = try MoneyMapPlanningStore.snapshot()
        let cash = max(baseCash ?? snapshot.amountPerPayday, 0)
        let scenarios = FinancialPlanningEngine.scenarioPlans(
            baseAvailableCash: cash,
            goals: snapshot.goals,
            bills: snapshot.bills,
            nextPayday: snapshot.nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )

        let lines = scenarios.map { scenario in
            "\(scenario.title): \(scenario.plan.summary)"
        }
        let spoken = lines.first ?? "No scenarios available."
        return .result(value: lines.joined(separator: "\n"), dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct ShowCardUtilizationIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Card Utilization"
    static var description = IntentDescription("Review overall credit-card utilization in MoneyMap.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cards = try MoneyMapBillStore.fetchBills().filter { $0.category == .creditCard }
        let totalBalance = cards.reduce(0) { $0 + ($1.creditCardDetails?.cardBalance ?? 0) }
        let totalLimit = cards.reduce(0) { $0 + ($1.creditCardDetails?.creditLimit ?? 0) }
        let utilization = totalLimit > 0 ? totalBalance / totalLimit : 0

        let utilizationText = utilization.formatted(.percent.precision(.fractionLength(0)))
        let balanceText = MoneyMapFormatters.currencyString(for: totalBalance)
        let limitText = MoneyMapFormatters.currencyString(for: totalLimit)

        let dialog = IntentDialog(
            stringLiteral: "Card utilization is \(utilizationText), \(balanceText) of \(limitText)."
        )
        PendingRouteStore.set(.showCardUtilization)
        return .result(dialog: dialog)
    }
}

struct MarkBillPaidIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Bill Paid"
    static var description = IntentDescription("Mark a bill as paid. For credit cards, optionally apply a payment amount.")
    static var openAppWhenRun = true

    @Parameter(title: "Bill")
    var bill: BillEntity

    @Parameter(title: "Payment Amount")
    var paymentAmount: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$bill) paid")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let updatedBill = try MoneyMapBillStore.markPaid(billID: bill.id, amount: paymentAmount)
        let name = updatedBill.name ?? "Bill"
        let dialog = IntentDialog(stringLiteral: "Marked \(name) as paid.")
        PendingRouteStore.set(.openBill(updatedBill.id))
        return .result(dialog: dialog)
    }
}

struct OpenUpcomingBillsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Upcoming Bills"
    static var description = IntentDescription("Open upcoming bills in MoneyMap.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRouteStore.set(.showUpcomingBills)
        return .result()
    }
}

struct OpenNextDueBillIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Next Due Bill"
    static var description = IntentDescription("Show the next unpaid bill due in MoneyMap with details you can tap to open.")
    static var openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Get next due bill")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let bill = try MoneyMapBillStore.fetchNextDueUnpaidBill() else {
            let dialog = IntentDialog(stringLiteral: "No unpaid bills with due dates were found.")
            return .result(
                dialog: dialog,
                view: NextDueBillEmptySnippet()
            )
        }

        let name = bill.name ?? "bill"
        let dueDate = bill.dueDate
        let dueDateText = dueDate.map { MoneyMapFormatters.mediumDateString(for: $0) } ?? "No due date"
        let relativeDueText = dueDate.map(relativeDuePhrase(for:)) ?? "soon"
        let amountText = bill.amount.map(MoneyMapFormatters.currencyString(for:)) ?? "Not set"
        let icon = bill.category?.icon ?? "calendar"
        let dialog = IntentDialog(stringLiteral: "Your \(name) bill is coming up \(relativeDueText). The expected amount is \(amountText).")
        let details = NextDueBillSnippetData(
            name: name,
            dueDateText: dueDateText,
            amountText: amountText,
            iconSystemName: icon,
            billEntity: BillEntity(bill)
        )
        return .result(dialog: dialog, view: NextDueBillSnippet(details: details))
    }

    private func relativeDuePhrase(for dueDate: Date) -> String {
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: Date())
        let startDue = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 0

        switch days {
        case ..<0:
            let absDays = abs(days)
            if absDays == 1 { return "since yesterday" }
            return "\(absDays) days ago"
        case 0:
            return "today"
        case 1:
            return "in 1 day"
        default:
            return "in \(days) days"
        }
    }
}

struct PayRecommendedCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Pay Recommended Card Amount"
    static var description = IntentDescription("Apply a recommended payment to your most utilized card and open it.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let card = try MoneyMapBillStore.fetchMostUtilizedCard() else {
            PendingRouteStore.set(.showCardUtilization)
            return .result(dialog: IntentDialog(stringLiteral: "No credit cards were found."))
        }

        let updated = try MoneyMapBillStore.payRecommendedAmount(billID: card.id)
        let name = updated.name ?? "card"
        let dialog = IntentDialog(stringLiteral: "Applied a recommended payment to \(name).")
        PendingRouteStore.set(.openBill(updated.id))
        return .result(dialog: dialog)
    }
}

private struct NextDueBillSnippetData {
    let name: String
    let dueDateText: String
    let amountText: String
    let iconSystemName: String
    let billEntity: BillEntity
}

private struct NextDueBillSnippet: View {
    let details: NextDueBillSnippetData

    private var openBillIntent: OpenBillIntent {
        let intent = OpenBillIntent()
        intent.bill = details.billEntity
        return intent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: details.iconSystemName)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.tint)

                Text(details.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Due: \(details.dueDateText)", systemImage: "calendar")
                    .font(.subheadline)
                Label("Expected: \(details.amountText)", systemImage: "dollarsign.circle")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)

            Button(intent: openBillIntent) {
                Label("Open in MoneyMap", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

private struct NextDueBillEmptySnippet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No unpaid bills with due dates were found.")
                .font(.headline)
            Text("Open upcoming bills to review your full list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(intent: OpenUpcomingBillsIntent()) {
                Label("Open Upcoming Bills", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}
