//
//  MoneyMapAssistantView.swift
//  MoneyMap
//
//  Created by Codex on 6/16/26.
//

import SwiftUI
import SwiftData
import FoundationModels

struct MoneyMapAssistantView: View {
    @EnvironmentObject private var paydayManager: PaydayManager
    @Query private var bills: [Bill]
    @Query(sort: \Goal.deadline, order: .forward) private var goals: [Goal]
    @Query private var paydayConfigs: [PaydayConfig]

    @State private var query = ""
    @State private var answer: String?
    @State private var answeredQuery = ""
    @State private var isAsking = false
    @State private var errorMessage: String?

    private var availabilityMessage: String? {
        MoneyMapAssistant.availabilityMessage(for: MoneyMapAssistant.model.availability)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasQuery: Bool {
        !trimmedQuery.isEmpty
    }

    private var amountPerPayday: Double {
        paydayConfigs.first?.amountPerPayday ?? 0
    }

    private var nextPayday: Date? {
        paydayManager.nextPayday ?? paydayConfigs.first?.nextPayday
    }

    private var dueBeforePayday: [Bill] {
        guard let nextPayday else { return [] }
        return bills
            .filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                return dueDate <= nextPayday && bill.status != .paid
            }
            .sorted(by: Bill.byStatusDateUtilization)
    }

    private var matchingBills: [Bill] {
        guard hasQuery else { return Array(bills.sorted(by: Bill.byStatusDateUtilization).prefix(4)) }
        return bills
            .filter { bill in
                searchFields(for: bill).contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            }
            .sorted(by: Bill.byStatusDateUtilization)
    }

    private var matchingGoals: [Goal] {
        guard hasQuery else { return Array(goals.prefix(4)) }
        return goals.filter { goal in
            [goal.name, goal.deadline.map(MoneyMapFormatters.mediumDateString(for:))]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    private var matchingTransactions: [Transaction] {
        let transactions = bills.flatMap { $0.transactions ?? [] }
        guard hasQuery else {
            return Array(transactions.sorted(by: MoneyMapTransactionStore.mostRecentFirst).prefix(4))
        }
        return transactions
            .filter { transaction in
                searchFields(for: transaction).contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            }
            .sorted(by: MoneyMapTransactionStore.mostRecentFirst)
    }

    private var recommendationDigest: RecommendationDigest {
        FinancialPlanningEngine.digest(
            availableCash: amountPerPayday,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )
    }

    private var recommendationUnallocatedCash: Double {
        max(amountPerPayday - recommendationDigest.suggestedCardPaymentTotal - recommendationDigest.suggestedGoalContributionTotal, 0)
    }

    private var shouldShowRecommendationResult: Bool {
        guard hasQuery else { return true }
        let terms = ["paycheck", "recommend", "plan", "cash", "payday", "debt", "save", "goal", "card"]
        return terms.contains { trimmedQuery.localizedCaseInsensitiveContains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                promptSection

                if hasQuery || answer != nil {
                    localResultsSection
                }

                if let answer, !answer.isEmpty {
                    generatedAnswerSection(answer)
                    generatedVisualsSection
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if !hasQuery && answer == nil {
                    examplesSection
                }
            }
            .navigationTitle("Search MoneyMap")
            .searchable(text: $query, prompt: "Search or ask MoneyMap")
            .searchToolbarBehavior(.minimize)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await ask()
                        }
                    } label: {
                        if isAsking {
                            ProgressView()
                        } else {
                            Label("Ask", systemImage: "sparkles")
                        }
                    }
                    .disabled(isAsking || trimmedQuery.isEmpty || availabilityMessage != nil)
                }
            }
            .onSubmit(of: .search) {
                Task {
                    await ask()
                }
            }
        }
    }

    private var promptSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Search and Ask")
                            .font(.title2.bold())
                        Text("Find bills, goals, transactions, or ask a question grounded in your MoneyMap data.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let availabilityMessage {
                    Label(availabilityMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var localResultsSection: some View {
        Section("App Results") {
            if matchingBills.isEmpty && matchingGoals.isEmpty && matchingTransactions.isEmpty && !shouldShowRecommendationResult {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Ask MoneyMap to reason over your data instead."))
            }

            if shouldShowRecommendationResult {
                NavigationLink {
                    RecommendationsView()
                } label: {
                    SearchRecommendationRow(digest: recommendationDigest, unallocatedCash: recommendationUnallocatedCash)
                }
            }

            ForEach(matchingBills.prefix(5)) { bill in
                NavigationLink {
                    BillView(bill: bill)
                } label: {
                    SearchBillRow(bill: bill)
                }
            }

            ForEach(matchingGoals.prefix(5)) { goal in
                NavigationLink {
                    GoalDetailView(goal)
                } label: {
                    SearchGoalRow(goal: goal)
                }
            }

            ForEach(matchingTransactions.prefix(6), id: \.self) { transaction in
                if let bill = transaction.creditCard {
                    NavigationLink {
                        BillView(bill: bill)
                    } label: {
                        SearchTransactionRow(transaction: transaction)
                    }
                } else {
                    SearchTransactionRow(transaction: transaction)
                }
            }
        }
    }

    private func generatedAnswerSection(_ answer: String) -> some View {
        Section("MoneyMap Answer") {
            Text(answer)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private var generatedVisualsSection: some View {
        Section("Visual Summary") {
            SearchMetricGrid(
                metrics: [
                    SearchMetric(title: "Due Before Payday", value: "\(dueBeforePayday.count)", detail: MoneyMapFormatters.currencyString(for: dueBeforePayday.totalAmount), systemImage: "calendar.badge.exclamationmark", color: .orange),
                    SearchMetric(title: "Goal Progress", value: averageGoalProgressText, detail: MoneyMapFormatters.currencyString(for: goals.reduce(0) { $0 + $1.amountSaved }), systemImage: "target", color: .green),
                    SearchMetric(title: "Matched Spend", value: MoneyMapFormatters.currencyString(for: matchedTransactionTotal), detail: "\(matchingTransactions.count) transactions", systemImage: "creditcard", color: .blue),
                    SearchMetric(title: "Unallocated", value: MoneyMapFormatters.currencyString(for: recommendationUnallocatedCash), detail: "After recommended moves", systemImage: "tray", color: .purple)
                ]
            )

            if !dueBeforePayday.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bills Before Payday")
                        .font(.headline)
                    ForEach(dueBeforePayday.prefix(3)) { bill in
                        SearchBillDueBar(bill: bill, total: max(dueBeforePayday.totalAmount, 1))
                    }
                }
                .padding(.vertical, 4)
            }

            if !goals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Goals")
                        .font(.headline)
                    ForEach(goals.prefix(3)) { goal in
                        SearchGoalProgressBar(goal: goal)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var examplesSection: some View {
        Section("Examples") {
            exampleButton("What bills are due before payday?")
            exampleButton("Search Starbucks transactions")
            exampleButton("How much do I have saved across my goals?")
            exampleButton("What should I do with my paycheck?")
        }
    }

    private var matchedTransactionTotal: Double {
        matchingTransactions.reduce(0) { $0 + abs($1.amountUSD ?? 0) }
    }

    private var averageGoalProgressText: String {
        guard !goals.isEmpty else { return "0%" }
        let average = goals.reduce(0) { $0 + $1.progress() } / Double(goals.count)
        return "\(Int((average * 100).rounded()))%"
    }

    private func exampleButton(_ example: String) -> some View {
        Button(example) {
            query = example
        }
    }

    private func searchFields(for bill: Bill) -> [String] {
        [
            bill.name,
            bill.category?.name,
            bill.status?.name,
            bill.notes,
            bill.autopaySource,
            bill.dueDate.map(MoneyMapFormatters.mediumDateString(for:)),
            bill.amount.map(MoneyMapFormatters.currencyString(for:))
        ]
        .compactMap { $0 }
    }

    private func searchFields(for transaction: Transaction) -> [String] {
        [
            transaction.friendlyName,
            transaction.merchant,
            transaction.transactionDescription,
            transaction.category,
            transaction.type,
            transaction.purchasedBy,
            transaction.creditCard?.name,
            (transaction.transactionDate ?? transaction.clearingDate).map(MoneyMapFormatters.mediumDateString(for:)),
            transaction.amountUSD.map { MoneyMapFormatters.currencyString(for: abs($0)) }
        ]
        .compactMap { $0 }
    }

    @MainActor
    private func ask() async {
        guard availabilityMessage == nil, !trimmedQuery.isEmpty else { return }
        isAsking = true
        errorMessage = nil
        answeredQuery = trimmedQuery

        do {
            answer = try await MoneyMapAssistant.answer(question: trimmedQuery)
        } catch {
            errorMessage = "MoneyMap couldn't answer that right now."
        }

        isAsking = false
    }
}

private struct SearchMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let color: Color
}

private struct SearchMetricGrid: View {
    let metrics: [SearchMetric]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: metric.systemImage)
                        .font(.title3)
                        .foregroundStyle(metric.color)
                    Text(metric.value)
                        .font(.headline)
                    Text(metric.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(metric.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                .padding(12)
                .background(metric.color.opacity(0.12), in: .rect(cornerRadius: 8))
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
}

private struct SearchBillRow: View {
    let bill: Bill

    var body: some View {
        HStack(spacing: 12) {
            SearchIcon(systemName: bill.category?.icon ?? "banknote", color: bill.category?.color ?? .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(bill.name ?? "Untitled Bill")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyMapFormatters.currencyString(for: bill.amount ?? 0))
                .font(.subheadline.weight(.semibold))
        }
    }

    private var detail: String {
        let due = bill.dueDate.map { MoneyMapFormatters.mediumDateString(for: $0) } ?? "No due date"
        let status = bill.status?.name ?? bill.category?.name ?? "Bill"
        return "\(status) • \(due)"
    }
}

private struct SearchGoalRow: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 12) {
            if let uiImage = goal.uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                SearchIcon(systemName: "target", color: .green)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(goal.name ?? "Savings Goal")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int((goal.progress() * 100).rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(max(goal.progress(), 0), 1))
                    .tint(.green)

                Text("\(MoneyMapFormatters.currencyString(for: goal.amountSaved)) saved • \(MoneyMapFormatters.currencyString(for: goal.remainingAmount)) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SearchTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            SearchIcon(systemName: "creditcard", color: .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Transaction")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyMapFormatters.currencyString(for: abs(transaction.amountUSD ?? 0)))
                .font(.subheadline.weight(.semibold))
        }
    }

    private var detail: String {
        let date = (transaction.transactionDate ?? transaction.clearingDate).map(MoneyMapFormatters.mediumDateString(for:)) ?? "Unknown date"
        let category = transaction.category ?? "Uncategorized"
        return "\(category) • \(date)"
    }
}

private struct SearchRecommendationRow: View {
    let digest: RecommendationDigest
    let unallocatedCash: Double

    var body: some View {
        HStack(spacing: 12) {
            SearchIcon(systemName: "wand.and.stars", color: .purple)
            VStack(alignment: .leading, spacing: 6) {
                Text("Paycheck Recommendations")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    labeledAmount("Cards", digest.suggestedCardPaymentTotal)
                    labeledAmount("Goals", digest.suggestedGoalContributionTotal)
                    labeledAmount("Left", unallocatedCash)
                }
            }
        }
    }

    private func labeledAmount(_ label: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(MoneyMapFormatters.currencyString(for: amount))
                .font(.caption.weight(.semibold))
        }
    }
}

private struct SearchIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.headline)
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 8))
    }
}

private struct SearchBillDueBar: View {
    let bill: Bill
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bill.name ?? "Untitled Bill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(MoneyMapFormatters.currencyString(for: bill.amount ?? 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max((bill.amount ?? 0) / total, 0), 1))
                .tint(bill.category?.color ?? .accentColor)
        }
    }
}

private struct SearchGoalProgressBar: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(goal.name ?? "Savings Goal")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int((goal.progress() * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(goal.progress(), 0), 1))
                .tint(.green)
        }
    }
}

#Preview {
    let (container, paydayManager) = PreviewDataProvider.createContainer()

    MoneyMapAssistantView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
