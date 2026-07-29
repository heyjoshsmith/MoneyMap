//
//  Siri.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/27/25.
//

import Foundation
import AppIntents
import CoreSpotlight
import SwiftUI

enum BillCategoryIntentOption: String, AppEnum {
    case utilities
    case creditCard
    case rent
    case mortgage
    case insurance
    case subscription
    case streaming
    case software
    case membership
    case groceries
    case transportation
    case phone
    case internet
    case entertainment
    case healthcare
    case childcare
    case education
    case loans
    case taxes
    case banking
    case homeServices
    case security
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bill Category")
    static var caseDisplayRepresentations: [BillCategoryIntentOption: DisplayRepresentation] = [
        .utilities: "Utilities",
        .creditCard: "Credit Card",
        .rent: "Rent",
        .mortgage: "Mortgage",
        .insurance: "Insurance",
        .subscription: "Subscription",
        .streaming: "Streaming",
        .software: "Software",
        .membership: "Membership",
        .groceries: "Groceries",
        .transportation: "Transportation",
        .phone: "Phone",
        .internet: "Internet",
        .entertainment: "Entertainment",
        .healthcare: "Healthcare",
        .childcare: "Childcare",
        .education: "Education",
        .loans: "Loans",
        .taxes: "Taxes",
        .banking: "Banking",
        .homeServices: "Home Services",
        .security: "Security",
        .other: "Other"
    ]

    var modelValue: BillCategory {
        switch self {
        case .utilities: return .utilities
        case .creditCard: return .creditCard
        case .rent: return .rent
        case .mortgage: return .mortgage
        case .insurance: return .insurance
        case .subscription: return .subscription
        case .streaming: return .streaming
        case .software: return .software
        case .membership: return .membership
        case .groceries: return .groceries
        case .transportation: return .transportation
        case .phone: return .phone
        case .internet: return .internet
        case .entertainment: return .entertainment
        case .healthcare: return .healthcare
        case .childcare: return .childcare
        case .education: return .education
        case .loans: return .loans
        case .taxes: return .taxes
        case .banking: return .banking
        case .homeServices: return .homeServices
        case .security: return .security
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

enum SpendingWindowIntentOption: String, AppEnum {
    case thisMonth
    case lastMonth
    case last30Days
    case thisYear

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spending Window")
    static var caseDisplayRepresentations: [SpendingWindowIntentOption: DisplayRepresentation] = [
        .thisMonth: "This Month",
        .lastMonth: "Last Month",
        .last30Days: "Last 30 Days",
        .thisYear: "This Year"
    ]
}

private let moneyMapCurrencyCode = Locale.current.currency?.identifier ?? "USD"

private func makeCurrencyAmount(_ value: Double?) -> IntentCurrencyAmount? {
    guard let value else { return nil }
    return IntentCurrencyAmount(amount: Decimal(value), currencyCode: moneyMapCurrencyCode)
}

private func billDueDateText(_ date: Date?) -> String {
    guard let date else { return "no due date set" }
    return MoneyMapFormatters.mediumDateString(for: date)
}

private func goalDeadlineText(_ date: Date?) -> String {
    guard let date else { return "no deadline set" }
    return MoneyMapFormatters.mediumDateString(for: date)
}

func transactionEntityID(for transaction: Transaction) -> String {
    let merchant = transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "unknown"
    let date = transaction.transactionDate ?? transaction.clearingDate ?? .distantPast
    let cardID = transaction.creditCard?.id.uuidString ?? "no-card"
    let cents = Int((abs(transaction.amountUSD ?? 0) * 100).rounded())
    return "\(cardID)|\(merchant.lowercased())|\(date.timeIntervalSince1970)|\(cents)"
}

func transactionHeadline(_ transaction: Transaction) -> String {
    transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Unknown transaction"
}

private func spendingWindowStart(_ window: SpendingWindowIntentOption) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    switch window {
    case .thisMonth:
        return calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
    case .lastMonth:
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? today
    case .last30Days:
        return calendar.date(byAdding: .day, value: -30, to: today) ?? today
    case .thisYear:
        return calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
    }
}

private func spendingWindowTitle(_ window: SpendingWindowIntentOption) -> String {
    switch window {
    case .thisMonth: return "this month"
    case .lastMonth: return "last month"
    case .last30Days: return "the last 30 days"
    case .thisYear: return "this year"
    }
}

struct BillEntity: AppEntity, IndexedEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bill")
    static var defaultQuery = BillEntityQuery()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Amount")
    var amount: IntentCurrencyAmount?

    @Property(title: "Due Date", indexingKey: \CSSearchableItemAttributeSet.startDate)
    var dueDate: Date?

    @Property(title: "Category")
    var categoryName: String

    @Property(title: "Notes", indexingKey: \CSSearchableItemAttributeSet.contentDescription)
    var notes: String?

    @Property(title: "Autopay Source")
    var autopaySource: String?

    @Property(title: "Is Paid")
    var isPaid: Bool

    @Property(title: "Autopay Enabled")
    var autopayEnabled: Bool

    @Property(title: "Current Balance")
    var currentBalance: IntentCurrencyAmount?

    @Property(title: "Credit Limit")
    var creditLimit: IntentCurrencyAmount?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(categoryName) • due \(billDueDateText(dueDate))"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let amountText = amount.map {
            MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: $0.amount).doubleValue)
        } ?? "No amount"
        let dueText = billDueDateText(dueDate)
        attributes.contentDescription = [
            amountText,
            categoryName,
            "due \(dueText)"
        ].joined(separator: " • ")
        attributes.keywords = [categoryName, "Bill", "MoneyMap", name]
        return attributes
    }

    static func == (lhs: BillEntity, rhs: BillEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct GoalEntity: AppEntity, IndexedEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Goal")
    static var defaultQuery = GoalEntityQuery()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Saved")
    var amountSaved: IntentCurrencyAmount

    @Property(title: "Target")
    var targetAmount: IntentCurrencyAmount?

    @Property(title: "Remaining")
    var remainingAmount: IntentCurrencyAmount

    @Property(title: "Deadline", indexingKey: \CSSearchableItemAttributeSet.endDate)
    var deadline: Date?

    @Property(title: "Progress Percent")
    var progressPercent: Double

    @Property(title: "Amount Per Paycheck")
    var amountPerPaycheck: IntentCurrencyAmount?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: amountSaved.amount).doubleValue)) saved"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let savedText = MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: amountSaved.amount).doubleValue)
        let remainingText = MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: remainingAmount.amount).doubleValue)
        attributes.contentDescription = [
            "\(savedText) saved",
            "\(remainingText) remaining",
            "deadline \(goalDeadlineText(deadline))"
        ].joined(separator: " • ")
        attributes.keywords = ["Goal", "Savings", "MoneyMap", name]
        return attributes
    }

    static func == (lhs: GoalEntity, rhs: GoalEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TransactionEntity: AppEntity, IndexedEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Transaction")
    static var defaultQuery = TransactionEntityQuery()

    var id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Amount")
    var amount: IntentCurrencyAmount

    @Property(title: "Date", indexingKey: \CSSearchableItemAttributeSet.startDate)
    var date: Date?

    @Property(title: "Merchant")
    var merchantName: String?

    @Property(title: "Category")
    var categoryName: String?

    @Property(title: "Card Name")
    var cardName: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: amount.amount).doubleValue))"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let dateText = date.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Unknown date"
        let amountText = MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: amount.amount).doubleValue)
        attributes.contentDescription = [
            amountText,
            merchantName ?? "Unknown merchant",
            categoryName ?? "Uncategorized",
            dateText
        ].joined(separator: " • ")
        attributes.keywords = [merchantName, categoryName, cardName, "Transaction", "MoneyMap"]
            .compactMap { $0 }
        return attributes
    }

    static func == (lhs: TransactionEntity, rhs: TransactionEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PaydayStatusEntity: UniqueAppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Payday Status")
    static var defaultQuery = PaydayStatusEntityQuery()

    let id = "currentPayday"

    @Property(title: "Next Payday")
    var nextPayday: Date?

    @Property(title: "Amount Per Payday")
    var amountPerPayday: IntentCurrencyAmount?

    @Property(title: "Savings Per Paycheck")
    var savingsPerPaycheck: IntentCurrencyAmount?

    @Property(title: "Days Until Payday")
    var daysUntilPayday: Int

    init(nextPayday: Date?, amountPerPayday: Double?, savingsPerPaycheck: Double?) {
        self.nextPayday = nextPayday
        self.amountPerPayday = makeCurrencyAmount(amountPerPayday)
        self.savingsPerPaycheck = makeCurrencyAmount(savingsPerPaycheck)
        if let nextPayday {
            self.daysUntilPayday = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: nextPayday)
            ).day ?? 0
        } else {
            self.daysUntilPayday = 0
        }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Payday Status",
            subtitle: "\(nextPayday.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Not set")"
        )
    }
}

struct BillEntityQuery: EntityStringQuery {
    func entities(for identifiers: [BillEntity.ID]) async throws -> [BillEntity] {
        let bills = try MoneyMapBillStore.fetchBills()
        let identifierSet = Set(identifiers)
        return bills
            .filter { identifierSet.contains($0.id) }
            .map(BillEntity.init)
    }

    func entities(matching string: String) async throws -> [BillEntity] {
        let term = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return try await suggestedEntities() }

        return try MoneyMapBillStore.fetchBills()
            .filter { bill in
                let haystacks = [
                    bill.name,
                    bill.category?.name,
                    bill.notes,
                    bill.autopaySource
                ]
                return haystacks
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(term.lowercased()) }
            }
            .sorted(by: Bill.byStatusDateUtilization)
            .map(BillEntity.init)
    }

    func suggestedEntities() async throws -> [BillEntity] {
        try MoneyMapBillStore.fetchBills()
            .sorted(by: Bill.byStatusDateUtilization)
            .map(BillEntity.init)
    }
}

struct GoalEntityQuery: EntityStringQuery {
    func entities(for identifiers: [GoalEntity.ID]) async throws -> [GoalEntity] {
        let goals = try MoneyMapPlanningStore.fetchGoals()
        let identifierSet = Set(identifiers)
        return goals
            .filter { identifierSet.contains($0.id) }
            .map(GoalEntity.init)
    }

    func entities(matching string: String) async throws -> [GoalEntity] {
        let term = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return try await suggestedEntities() }

        return try MoneyMapPlanningStore.fetchGoals()
            .filter { goal in
                (goal.name ?? "").localizedCaseInsensitiveContains(term)
            }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .map(GoalEntity.init)
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        try MoneyMapPlanningStore.fetchGoals()
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .map(GoalEntity.init)
    }
}

struct TransactionEntityQuery: EntityStringQuery {
    func entities(for identifiers: [TransactionEntity.ID]) async throws -> [TransactionEntity] {
        let identifierSet = Set(identifiers)
        return try MoneyMapTransactionStore.fetchTransactions()
            .filter { identifierSet.contains(transactionEntityID(for: $0)) }
            .map(TransactionEntity.init)
    }

    func entities(matching string: String) async throws -> [TransactionEntity] {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return try await suggestedEntities() }

        let options = MoneyMapTransactionSearchOptions(
            merchant: normalized,
            category: normalized,
            cardID: nil,
            since: nil,
            limit: 12
        )
        return try MoneyMapTransactionStore.fetchTransactions(matching: options)
            .map(TransactionEntity.init)
    }

    func suggestedEntities() async throws -> [TransactionEntity] {
        try MoneyMapTransactionStore.fetchTransactions()
            .sorted(by: MoneyMapTransactionStore.mostRecentFirst)
            .prefix(12)
            .map(TransactionEntity.init)
    }
}

struct PaydayStatusEntityQuery: UniqueAppEntityQuery {
    func uniqueEntity() async throws -> PaydayStatusEntity {
        let snapshot = try MoneyMapPlanningStore.snapshot()
        let paydayConfig = try MoneyMapPlanningStore.fetchPrimaryPaydayConfig()
        return PaydayStatusEntity(
            nextPayday: snapshot.nextPayday,
            amountPerPayday: snapshot.amountPerPayday,
            savingsPerPaycheck: paydayConfig?.savingsPerPaycheck
        )
    }
}

extension BillEntity {
    init(_ bill: Bill) {
        id = bill.id
        name = bill.name ?? "Untitled"
        amount = makeCurrencyAmount(bill.amount)
        dueDate = bill.dueDate
        categoryName = bill.category?.name ?? "Other"
        notes = bill.notes
        autopaySource = bill.autopaySource
        isPaid = bill.datePaid != nil || bill.status == .paid
        autopayEnabled = bill.autopayEnabled
        currentBalance = makeCurrencyAmount(bill.creditCardDetails?.cardBalance)
        creditLimit = makeCurrencyAmount(bill.creditCardDetails?.creditLimit)
    }
}

extension GoalEntity {
    init(_ goal: Goal) {
        id = goal.id
        name = goal.name ?? "Untitled"
        amountSaved = makeCurrencyAmount(goal.amountSaved) ?? IntentCurrencyAmount(amount: 0, currencyCode: moneyMapCurrencyCode)
        targetAmount = makeCurrencyAmount(goal.targetAmount)
        remainingAmount = makeCurrencyAmount(goal.remainingAmount) ?? IntentCurrencyAmount(amount: 0, currencyCode: moneyMapCurrencyCode)
        deadline = goal.deadline
        progressPercent = goal.progress() * 100
        amountPerPaycheck = makeCurrencyAmount(goal.amountPerPaycheck)
    }
}

extension TransactionEntity {
    init(_ transaction: Transaction) {
        id = transactionEntityID(for: transaction)
        name = transactionHeadline(transaction)
        amount = makeCurrencyAmount(abs(transaction.amountUSD ?? 0)) ?? IntentCurrencyAmount(amount: 0, currencyCode: moneyMapCurrencyCode)
        date = transaction.transactionDate ?? transaction.clearingDate
        merchantName = transaction.merchant
        categoryName = transaction.category
        cardName = transaction.creditCard?.name
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
    static var description = IntentDescription("Open allocation recommendations in MoneyMap.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRouteStore.set(.showRecommendations)
        return .result()
    }
}

struct GetPaycheckRecommendationIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Allocation Plan"
    static var description = IntentDescription("Get recommended allocations for available money across cards and goals.")

    @Parameter(title: "Available Cash")
    var availableCash: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Get allocation plan")
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
    static var title: LocalizedStringResource = "Compare Allocation Scenarios"
    static var description = IntentDescription("Compare lean, planned, and stretch allocation strategies.")

    @Parameter(title: "Base Cash")
    var baseCash: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Compare allocation scenarios")
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

struct GetBillDueDateIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Bill Due Date"
    static var description = IntentDescription("Answer when a specific bill is due.")

    @Parameter(title: "Bill")
    var bill: BillEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get due date for \(\.$bill)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let dueText = billDueDateText(bill.dueDate)
        let name = bill.name
        let amountText = bill.amount.map {
            MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: $0.amount).doubleValue)
        } ?? "an amount that is not set yet"
        let spoken = "\(name) is due \(dueText). The amount is \(amountText)."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct GetSavingsSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Savings Summary"
    static var description = IntentDescription("Answer how much you have saved across goals or for one goal.")

    @Parameter(title: "Goal")
    var goal: GoalEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get savings summary")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        if let goal {
            let savedText = MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: goal.amountSaved.amount).doubleValue)
            let remainingText = MoneyMapFormatters.currencyString(for: NSDecimalNumber(decimal: goal.remainingAmount.amount).doubleValue)
            let spoken = "\(goal.name) has \(savedText) saved, with \(remainingText) remaining."
            return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
        }

        let goals = try MoneyMapPlanningStore.fetchGoals()
        let totalSaved = goals.reduce(0) { $0 + $1.amountSaved }
        let totalRemaining = goals.reduce(0) { $0 + $1.remainingAmount }
        let savedText = MoneyMapFormatters.currencyString(for: totalSaved)
        let remainingText = MoneyMapFormatters.currencyString(for: totalRemaining)
        let activeGoals = goals.filter { $0.remainingAmount > 0 }.count
        let spoken = "You have \(savedText) saved across \(goals.count) goal\(goals.count == 1 ? "" : "s"). \(activeGoals) still need funding, with \(remainingText) remaining."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct GetNextPaydayIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Next Payday"
    static var description = IntentDescription("Answer when the next payday is and how far away it is.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let payday = try await PaydayStatusEntityQuery().uniqueEntity()

        guard let nextPayday = payday.nextPayday else {
            let spoken = "You have not set a next payday yet."
            return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
        }

        let spoken = "Your next payday is \(MoneyMapFormatters.mediumDateString(for: nextPayday)), \(payday.daysUntilPayday) day\(payday.daysUntilPayday == 1 ? "" : "s") away."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct GetCashAfterBillsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Cash After Bills"
    static var description = IntentDescription("Answer how much paycheck money is left after bills due before the next payday.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let snapshot = try MoneyMapPlanningStore.snapshot()

        guard let nextPayday = snapshot.nextPayday else {
            let spoken = "Set your next payday first so MoneyMap can calculate what is left after bills."
            return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
        }

        let upcomingBills = snapshot.bills
            .filter { bill in
                guard bill.category != .creditCard,
                      bill.status != .paid,
                      let dueDate = bill.dueDate else {
                    return false
                }
                return dueDate <= nextPayday
            }
        let totalDue = upcomingBills.reduce(0) { $0 + ($1.amount ?? 0) }
        let remaining = max(snapshot.amountPerPayday - totalDue, 0)
        let spoken = "You have \(MoneyMapFormatters.currencyString(for: remaining)) left after \(MoneyMapFormatters.currencyString(for: totalDue)) in bills due before \(MoneyMapFormatters.mediumDateString(for: nextPayday))."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct GetRecentTransactionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Recent Transactions"
    static var description = IntentDescription("Answer with recent transactions, optionally filtered by card, merchant, or category.")

    @Parameter(title: "Card")
    var card: BillEntity?

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Within Days")
    var withinDays: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Get recent transactions")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let days = max(withinDays ?? 30, 1)
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let matches = try MoneyMapTransactionStore.fetchTransactions(
            matching: MoneyMapTransactionSearchOptions(
                merchant: merchant,
                category: category,
                cardID: card?.id,
                since: since,
                limit: 5
            )
        )

        guard !matches.isEmpty else {
            let spoken = "No matching transactions were found."
            return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
        }

        let lines = matches.map { transaction in
            let amount = MoneyMapFormatters.currencyString(for: abs(transaction.amountUSD ?? 0))
            let merchantName = transactionHeadline(transaction)
            let date = (transaction.transactionDate ?? transaction.clearingDate).map(MoneyMapFormatters.mediumDateString(for:)) ?? "Unknown date"
            return "\(merchantName) \(amount) on \(date)"
        }

        let spoken = "Recent transactions: " + lines.joined(separator: "; ") + "."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct GetSpendingSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Spending Summary"
    static var description = IntentDescription("Answer how much was spent in a time window, optionally filtered by card, merchant, or category.")

    @Parameter(title: "Card")
    var card: BillEntity?

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Window")
    var window: SpendingWindowIntentOption

    init() {
        card = nil
        merchant = nil
        category = nil
        window = .thisMonth
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get spending summary")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let start = spendingWindowStart(window)
        let matches = try MoneyMapTransactionStore.fetchTransactions(
            matching: MoneyMapTransactionSearchOptions(
                merchant: merchant,
                category: category,
                cardID: card?.id,
                since: start,
                limit: nil
            )
        )

        let total = matches.reduce(0) { $0 + abs($1.amountUSD ?? 0) }
        let scope = merchant ?? category ?? card?.name ?? "all tracked transactions"
        let spoken = "You spent \(MoneyMapFormatters.currencyString(for: total)) on \(scope) during \(spendingWindowTitle(window)). That came from \(matches.count) transaction\(matches.count == 1 ? "" : "s")."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
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
