//
//  RecurringBillReviewView.swift
//  MoneyMap
//
//  Created by Codex on 7/7/26.
//

import SwiftData
import SwiftUI

struct RecurringBillReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(RecurringBillDetector.ignoredSuggestionIDsKey) private var ignoredSuggestionIDs = ""

    @State private var bills: [Bill] = []
    @State private var plaidAccounts: [PlaidAccountValue] = []
    @State private var actionMessage: String?
    @State private var actionErrorMessage: String?
    @State private var reviewSuggestions: [RecurringBillSuggestion] = []
    @State private var ignoredSuggestions: [RecurringBillSuggestion] = []
    @State private var lastIgnoredSuggestion: RecurringBillSuggestion?
    @State private var showingIgnoredSuggestions = false
    @State private var selectedSuggestion: RecurringBillSuggestion?
    @State private var viewingBill: Bill?
    @State private var isLoadingSuggestions = false
    @State private var selectedMode: RecurringReviewMode = .upcoming
    @State private var visibleMonth = Calendar.current.startOfMonth(containing: .now)

    init(initialSuggestions: [RecurringBillSuggestion] = [], initialPlaidAccounts: [PlaidAccountValue] = []) {
        _reviewSuggestions = State(initialValue: initialSuggestions)
        _plaidAccounts = State(initialValue: initialPlaidAccounts)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                    .padding(.horizontal)

                feedbackStack
            }
            .padding(.top, 12)

            switch selectedMode {
            case .upcoming:
                upcomingContent
            case .all:
                allContent
            }
        }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .background(MoneyMapDesign.groupedBackground)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: reviewSuggestions)
        .animation(.snappy(duration: 0.2), value: actionMessage)
        .task {
            await loadInitialSuggestions()
        }
        .onAppear {
            MoneyMapDiagnostics.record(
                "recurringReview.appear",
                metadata: ["initialSuggestions": "\(reviewSuggestions.count)"]
            )
        }
        .onDisappear {
            MoneyMapDiagnostics.record(
                "recurringReview.disappear",
                metadata: ["visibleSuggestions": "\(reviewSuggestions.count)"]
            )
        }
        .onChange(of: ignoredSuggestionIDs) { _, _ in
            reloadSuggestions(animated: true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingIgnoredSuggestions = true
                } label: {
                    Label("Ignored", systemImage: "archivebox")
                }
                .disabled(ignoredSuggestions.isEmpty)
            }
        }
        .sheet(isPresented: $showingIgnoredSuggestions) {
            NavigationStack {
                IgnoredRecurringChargesView(
                    suggestions: ignoredSuggestions,
                    restore: restore
                )
            }
        }
        .sheet(item: $selectedSuggestion) { suggestion in
            NavigationStack {
                RecurringChargeDetailView(
                    suggestion: suggestion,
                    plaidAccounts: plaidAccounts,
                    add: { accept(suggestion) },
                    ignore: { ignore(suggestion) },
                    deleteTransactions: { deleteMatchedTransactions(for: suggestion) }
                )
            }
        }
        .navigationDestination(item: $viewingBill) { bill in
            BillView(bill: bill)
        }
    }

    private var modePicker: some View {
        Picker("Recurring View", selection: $selectedMode) {
            ForEach(RecurringReviewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Recurring filter")
    }

    @ViewBuilder
    private var feedbackStack: some View {
        if actionMessage != nil || actionErrorMessage != nil {
            VStack(spacing: 10) {
                if let actionMessage {
                    RecurringStatusNotice(
                        title: actionMessage,
                        systemImage: "checkmark.circle.fill",
                        tint: MoneyMapDesign.calmGreen,
                        actionTitle: lastIgnoredSuggestion == nil ? nil : "Undo",
                        action: {
                            if let lastIgnoredSuggestion {
                                restore(lastIgnoredSuggestion)
                            }
                        }
                    )
                }

                if let actionErrorMessage {
                    RecurringStatusNotice(
                        title: actionErrorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: MoneyMapDesign.attentionRed
                    )
                    .textSelection(.enabled)
                }
            }
            .padding(.horizontal)
        }
    }

    private var upcomingContent: some View {
        TabView(selection: $visibleMonth) {
            ForEach(monthPageDates, id: \.self) { month in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        recurringCalendarSection(for: month)
                        recurringMonthlySummary(for: month)

                        Text("Expected dates and amounts are estimates based on your transaction history.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)

                        recurringUpcomingSection(for: month)
                        recurringHistorySection(for: month)
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 34)
                }
                .tag(month)
                .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recurringAllSummary
                recurringAllSection
            }
            .padding(.vertical, 12)
        }
    }

    private func recurringCalendarSection(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(monthTitle(for: month))
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            .padding(.horizontal)

            RecurringMonthCalendarCard(
                month: month,
                items: projectedScheduleItems(for: month),
                today: .now,
                calendar: .current
            )
            .padding(.horizontal)
        }
    }

    private func recurringMonthlySummary(for month: Date) -> some View {
        RecurringMonthlySummaryCard(
            total: expectedTotal(for: month),
            average: averageMonthlyExpectedTotal
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recurringUpcomingSection(for month: Date) -> some View {
        let items = projectedScheduleItems(for: month)

        RecurringSectionContainer(title: "Upcoming") {
            if isLoadingSuggestions && items.isEmpty {
                RecurringLoadingRow(title: "Checking recent transactions")
            } else if items.isEmpty {
                RecurringEmptyState(
                    title: "No Upcoming Charges",
                    systemImage: "calendar.badge.checkmark",
                    detail: "Tracked subscriptions and detected recurring charges will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(items.prefix(12)) { item in
                        RecurringScheduleRow(
                            item: item,
                            dateStyle: .relative,
                            select: { select(item) }
                        )

                        if item.id != items.prefix(12).last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recurringHistorySection(for month: Date) -> some View {
        let history = recentRecurringHistory(for: month)

        if !history.isEmpty {
            RecurringSectionContainer(title: "Transaction History") {
                VStack(spacing: 0) {
                    ForEach(history.prefix(8)) { item in
                        RecurringHistoryRow(item: item)

                        if item.id != history.prefix(8).last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    private var recurringAllSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(allScheduleItems.count) Transaction\(allScheduleItems.count == 1 ? "" : "s")")
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)

            Text(allSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
    }

    private var recurringAllSection: some View {
        RecurringSectionContainer(title: nil) {
            if isLoadingSuggestions && allScheduleItems.isEmpty {
                RecurringLoadingRow(title: "Checking recent transactions")
            } else if allScheduleItems.isEmpty {
                RecurringEmptyState(
                    title: "No Recurring Charges",
                    systemImage: "repeat",
                    detail: "MoneyMap has not found or saved recurring transactions yet."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(allScheduleItems) { item in
                        RecurringScheduleRow(
                            item: item,
                            dateStyle: .full,
                            select: { select(item) }
                        )

                        if item.id != allScheduleItems.last?.id {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    private var today: Date {
        Calendar.current.startOfDay(for: .now)
    }

    private func expectedTotal(for month: Date) -> Double {
        projectedScheduleItems(for: month).reduce(0) { $0 + $1.amount }
    }

    private var averageMonthlyExpectedTotal: Double {
        let totals = monthPageDates
            .map(expectedTotal(for:))
            .filter { $0 > 0 }
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Double(totals.count)
    }

    private func projectedScheduleItems(for month: Date) -> [RecurringScheduleItem] {
        let calendar = Calendar.current
        let suggestions = reviewSuggestions.flatMap { suggestion in
            projectedDates(
                startingAt: suggestion.nextDueDate,
                interval: suggestion.cadence.recurrenceInterval,
                unit: suggestion.cadence.recurrenceUnit,
                in: month,
                calendar: calendar
            )
            .map { date in
                RecurringScheduleItem(suggestion, occurrenceDate: date)
            }
        }

        let tracked = trackedRecurringBills
            .filter { $0.lifecycleState == .active }
            .flatMap { bill in
                projectedDates(
                    startingAt: bill.dueDate,
                    interval: bill.recurrenceInterval,
                    unit: bill.recurrenceUnit,
                    in: month,
                    calendar: calendar
                )
                .map { date in
                    RecurringScheduleItem(bill: bill, occurrenceDate: date, calendar: calendar)
                }
            }

        return (suggestions + tracked)
            .filter { $0.date >= today }
            .sorted(by: RecurringScheduleItem.byDate)
    }

    private func projectedDates(
        startingAt startDate: Date?,
        interval: Int?,
        unit: RecurrenceUnit?,
        in month: Date,
        calendar: Calendar
    ) -> [Date] {
        guard let startDate,
              let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        var candidate = calendar.startOfDay(for: startDate)

        guard let interval, let unit, interval > 0 else {
            return calendar.isDate(candidate, equalTo: month, toGranularity: .month) ? [candidate] : []
        }

        var safetyCounter = 0
        while candidate < monthInterval.start && safetyCounter < 240 {
            guard let nextDate = advanced(date: candidate, unit: unit, interval: interval, calendar: calendar) else {
                return []
            }
            candidate = nextDate
            safetyCounter += 1
        }

        var dates: [Date] = []
        while candidate < monthInterval.end && safetyCounter < 260 {
            dates.append(candidate)
            guard let nextDate = advanced(date: candidate, unit: unit, interval: interval, calendar: calendar) else {
                break
            }
            candidate = nextDate
            safetyCounter += 1
        }

        return dates
    }

    private func advanced(date: Date, unit: RecurrenceUnit, interval: Int, calendar: Calendar) -> Date? {
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .week:
            return calendar.date(byAdding: .day, value: interval * 7, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: interval, to: date)
        case .year:
            return calendar.date(byAdding: .year, value: interval, to: date)
        }
    }

    private var upcomingScheduleItems: [RecurringScheduleItem] {
        allScheduleItems
            .filter { $0.lifecycleState == .active && $0.date >= today }
            .sorted(by: RecurringScheduleItem.byDate)
    }

    private var allScheduleItems: [RecurringScheduleItem] {
        let tracked = trackedRecurringBills.map { RecurringScheduleItem(bill: $0, calendar: .current) }
        let suggestions = reviewSuggestions.map { RecurringScheduleItem($0) }
        return (suggestions + tracked).sorted(by: RecurringScheduleItem.byDateThenTitle)
    }

    private var recentRecurringHistory: [RecurringHistoryItem] {
        reviewSuggestions
            .flatMap { suggestion in
                suggestion.evidence.map { evidence in
                    RecurringHistoryItem(suggestion: suggestion, evidence: evidence)
                }
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.date > rhs.date
            }
    }

    private func recentRecurringHistory(for month: Date) -> [RecurringHistoryItem] {
        recentRecurringHistory.filter { item in
            Calendar.current.isDate(item.date, equalTo: month, toGranularity: .month)
        }
    }

    private func monthTitle(for month: Date) -> String {
        month.formatted(.dateTime.month(.wide).year())
    }

    private var monthPageDates: [Date] {
        let calendar = Calendar.current
        let currentMonth = calendar.startOfMonth(containing: .now)
        return (0...18).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: currentMonth)
        }
    }

    private var allSummaryText: String {
        let upcomingTotal = upcomingScheduleItems.reduce(0) { $0 + $1.amount }
        if upcomingScheduleItems.isEmpty {
            return "Tracked and detected recurring charges will collect here as MoneyMap learns your patterns."
        }
        return "\(upcomingScheduleItems.count) upcoming - \(MoneyMapFormatters.currencyString(for: upcomingTotal)) expected"
    }

    private func select(_ item: RecurringScheduleItem) {
        switch item.source {
        case let .suggestion(suggestion):
            selectedSuggestion = suggestion
        case let .bill(bill):
            viewingBill = bill
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(MoneyMapDesign.controlBackground)
                        Image(systemName: "repeat")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(MoneyMapDesign.calmGreen)
                    }
                    .frame(width: 48, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(heroTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(heroDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    RecurringReviewMetric(value: "\(reviewSuggestions.count)", title: "Found")
                    RecurringReviewMetric(value: "\(highConfidenceCount)", title: "High")
                    RecurringReviewMetric(value: upcomingTotalText, title: "Monthly")
                }
            }
            .padding(16)
            .background(MoneyMapDesign.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MoneyMapDesign.separator, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let actionMessage {
            Section {
                HStack(spacing: 10) {
                    Label(actionMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(MoneyMapDesign.calmGreen)

                    Spacer(minLength: 8)

                    if let lastIgnoredSuggestion {
                        Button {
                            restore(lastIgnoredSuggestion)
                        } label: {
                            Text("Undo")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        if let actionErrorMessage {
            Section {
                Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(MoneyMapDesign.attentionRed)
                    .textSelection(.enabled)
            }
        }
    }

    private var suggestionsSection: some View {
        Section {
            if isLoadingSuggestions && reviewSuggestions.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Checking recent transactions")
                        .padding(.vertical, 24)
                    Spacer()
                }
            } else if reviewSuggestions.isEmpty {
                ContentUnavailableView(
                    "Nothing to Review",
                    systemImage: "checkmark.circle",
                    description: Text("MoneyMap will show this card again when imported transactions reveal a new recurring charge.")
                )
            } else {
                ForEach(reviewSuggestions) { suggestion in
                    RecurringReviewSuggestionRow(
                        suggestion: suggestion,
                        showDetails: { selectedSuggestion = suggestion }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            ignore(suggestion)
                        } label: {
                            Label("Ignore", systemImage: "xmark.circle")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            accept(suggestion)
                        } label: {
                            Label(
                                suggestion.hasCanceledMatch ? "Restore" : "Add",
                                systemImage: suggestion.hasCanceledMatch ? "arrow.uturn.backward.circle" : "plus.circle"
                            )
                        }
                        .tint(.accentColor)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
        } header: {
            HStack {
                Text("Detected Charges")
                Spacer()
                if !ignoredSuggestions.isEmpty {
                    Button {
                        showingIgnoredSuggestions = true
                    } label: {
                        Text("\(ignoredSuggestions.count) Ignored")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        } footer: {
            Text("Recurring charge is the umbrella. MoneyMap labels each item as a bill, subscription, loan, membership, service, utility, insurance, or housing cost so you can decide how to track it.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var trackedRecurringSection: some View {
        Section {
            if trackedRecurringBills.isEmpty {
                Text("Tracked bills and subscriptions will appear here after you add them.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trackedRecurringBills) { bill in
                    Button {
                        viewingBill = bill
                    } label: {
                        TrackedRecurringChargeRow(bill: bill)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        } header: {
            Text("Tracked Bills & Subscriptions")
        } footer: {
            Text("This includes active, paused, and canceled recurring items already saved in MoneyMap.")
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    private var highConfidenceCount: Int {
        reviewSuggestions.filter { $0.confidence >= 0.86 }.count
    }

    private var upcomingTotalText: String {
        let monthlyTotal = reviewSuggestions
            .filter { $0.cadence == .monthly }
            .reduce(0) { $0 + $1.amount }
        return MoneyMapFormatters.currencyString(for: monthlyTotal)
    }

    private var heroTitle: String {
        reviewSuggestions.isEmpty ? "Recurring charges are current" : "\(reviewSuggestions.count) recurring charge\(reviewSuggestions.count == 1 ? "" : "s") found"
    }

    private var heroDetail: String {
        reviewSuggestions.isEmpty
            ? "There are no detected subscriptions waiting for review."
            : "Review repeating imported transactions before adding them to MoneyMap."
    }

    private var trackedRecurringBills: [Bill] {
        bills.withoutCreditCards
            .filter(\.isSubscriptionLike)
            .sorted { lhs, rhs in
                if lhs.lifecycleState != rhs.lifecycleState {
                    return lhs.lifecycleState.sortPriority < rhs.lifecycleState.sortPriority
                }
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
    }

    @MainActor
    private func loadInitialSuggestions() async {
        MoneyMapDiagnostics.record(
            "recurringReview.initialReload.scheduled",
            metadata: ["initialSuggestions": "\(reviewSuggestions.count)"]
        )
        if reviewSuggestions.isEmpty {
            isLoadingSuggestions = true
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else {
            MoneyMapDiagnostics.record("recurringReview.initialReload.cancelled")
            return
        }
        reloadSuggestions()
    }

    private func reloadSuggestions(animated: Bool = false) {
        let start = Date()
        MoneyMapDiagnostics.record(
            "recurringReview.reload.begin",
            metadata: [
                "animated": "\(animated)",
                "cachedSuggestions": "\(reviewSuggestions.count)"
            ]
        )
        isLoadingSuggestions = true
        do {
            let ignoredIDs = Set(ignoredSuggestionIDs.split(separator: "|").map(String.init))
            let fetchedBills = try MoneyMapDiagnostics.measure("recurringReview.fetchBills") {
                try modelContext.fetch(FetchDescriptor<Bill>())
            }
            let fetchedTransactions = try MoneyMapDiagnostics.measure("recurringReview.fetchTransactions") {
                try fetchDetectionTransactions()
            }
            let fetchedPlaidAccounts = try MoneyMapDiagnostics.measure("recurringReview.fetchPlaidAccounts") {
                try modelContext.fetch(
                    FetchDescriptor<PlaidAccountSnapshot>(sortBy: [SortDescriptor(\.accountName)])
                )
                .map(PlaidAccountValue.init)
            }
            let detected = MoneyMapDiagnostics.measure(
                "recurringReview.detect",
                metadata: [
                    "bills": "\(fetchedBills.count)",
                    "transactions": "\(fetchedTransactions.count)"
                ]
            ) {
                RecurringBillDetector.detect(transactions: fetchedTransactions, existingBills: fetchedBills)
            }
            let update = {
                bills = fetchedBills
                if !fetchedPlaidAccounts.isEmpty || plaidAccounts.isEmpty {
                    plaidAccounts = fetchedPlaidAccounts
                }
                reviewSuggestions = detected.filter { !ignoredIDs.contains($0.id) }
                ignoredSuggestions = detected.filter { ignoredIDs.contains($0.id) }
                isLoadingSuggestions = false
            }

            if animated {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86), update)
            } else {
                update()
            }
            MoneyMapDiagnostics.record(
                "recurringReview.reload.complete",
                metadata: [
                    "durationMs": MoneyMapDiagnostics.durationMilliseconds(since: start),
                    "detected": "\(detected.count)",
                    "ignored": "\(ignoredSuggestions.count)",
                    "visible": "\(reviewSuggestions.count)"
                ]
            )
        } catch {
            isLoadingSuggestions = false
            actionErrorMessage = "Could not check recurring charges: \(error.localizedDescription)"
            MoneyMapDiagnostics.record(
                "recurringReview.reload.failed",
                error: error,
                metadata: ["durationMs": MoneyMapDiagnostics.durationMilliseconds(since: start)]
            )
        }
    }

    private func fetchDetectionTransactions() throws -> [Transaction] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -18, to: .now) ?? .distantPast
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                if let transactionDate = transaction.transactionDate {
                    transactionDate >= cutoff
                } else if let clearingDate = transaction.clearingDate {
                    clearingDate >= cutoff
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        descriptor.fetchLimit = 5_000
        return try modelContext.fetch(descriptor)
    }

    private func accept(_ suggestion: RecurringBillSuggestion) {
        if suggestion.hasCanceledMatch {
            restoreCanceledBill(from: suggestion)
        } else {
            createBill(from: suggestion)
        }
    }

    private func createBill(from suggestion: RecurringBillSuggestion) {
        let bill = Bill(
            name: suggestion.title,
            amount: suggestion.amount,
            dueDate: suggestion.nextDueDate,
            category: suggestion.category,
            recurrenceInterval: suggestion.cadence.recurrenceInterval,
            recurrenceUnit: suggestion.cadence.recurrenceUnit,
            notes: "Detected from \(suggestion.transactionCount) recurring imported transactions.",
            autopaySource: suggestion.title
        )
        bill.checkStatus()
        modelContext.insert(bill)
        markResolved(suggestion)

        do {
            try modelContext.save()
            actionMessage = "\(suggestion.title) was added as a \(suggestion.kind.title.lowercased())."
            actionErrorMessage = nil
            lastIgnoredSuggestion = nil
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            actionErrorMessage = error.localizedDescription
            actionMessage = nil
        }
    }

    private func restoreCanceledBill(from suggestion: RecurringBillSuggestion) {
        guard let matchedBillID = suggestion.matchedBillID,
              let bill = bills.first(where: { $0.id == matchedBillID }) else {
            createBill(from: suggestion)
            return
        }

        bill.name = bill.name?.isEmpty == false ? bill.name : suggestion.title
        bill.amount = suggestion.amount
        bill.dueDate = suggestion.nextDueDate
        bill.category = suggestion.category
        bill.recurrenceInterval = suggestion.cadence.recurrenceInterval
        bill.recurrenceUnit = suggestion.cadence.recurrenceUnit
        bill.resume(nextDueDate: suggestion.nextDueDate)
        markResolved(suggestion)

        do {
            try modelContext.save()
            actionMessage = "\(bill.name ?? suggestion.title) was restored."
            actionErrorMessage = nil
            lastIgnoredSuggestion = nil
            AppRefreshEvents.notifyBillsDidChange()
        } catch {
            actionErrorMessage = error.localizedDescription
            actionMessage = nil
        }
    }

    private func ignore(_ suggestion: RecurringBillSuggestion) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            setIgnored(true, for: suggestion)
            lastIgnoredSuggestion = suggestion
            actionMessage = "\(suggestion.title) was ignored."
            actionErrorMessage = nil
        }
    }

    private func restore(_ suggestion: RecurringBillSuggestion) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            setIgnored(false, for: suggestion)
            if lastIgnoredSuggestion?.id == suggestion.id {
                lastIgnoredSuggestion = nil
            }
            actionMessage = "\(suggestion.title) is back in review."
            actionErrorMessage = nil
        }
    }

    private func deleteMatchedTransactions(for suggestion: RecurringBillSuggestion) {
        let start = Date()
        MoneyMapDiagnostics.record(
            "recurringReview.deleteMatchedTransactions.begin",
            metadata: [
                "suggestion": suggestion.id,
                "evidence": "\(suggestion.evidence.count)"
            ]
        )

        do {
            let transactions = try fetchDetectionTransactions()
            let matchedTransactions = transactions.filter { transaction in
                suggestion.evidence.contains { evidence in
                    evidenceMatchesTransaction(evidence, transaction)
                }
            }

            guard !matchedTransactions.isEmpty else {
                actionMessage = nil
                actionErrorMessage = "No matching transactions were found to delete."
                MoneyMapDiagnostics.record(
                    "recurringReview.deleteMatchedTransactions.none",
                    metadata: ["suggestion": suggestion.id]
                )
                return
            }

            matchedTransactions.forEach(modelContext.delete)
            try modelContext.save()
            selectedSuggestion = nil
            actionMessage = "\(matchedTransactions.count) matched transaction\(matchedTransactions.count == 1 ? "" : "s") deleted."
            actionErrorMessage = nil
            lastIgnoredSuggestion = nil
            reloadSuggestions(animated: true)
            MoneyMapDiagnostics.record(
                "recurringReview.deleteMatchedTransactions.complete",
                metadata: [
                    "durationMs": MoneyMapDiagnostics.durationMilliseconds(since: start),
                    "deleted": "\(matchedTransactions.count)",
                    "suggestion": suggestion.id
                ]
            )
        } catch {
            actionMessage = nil
            actionErrorMessage = "Could not delete matched transactions: \(error.localizedDescription)"
            MoneyMapDiagnostics.record(
                "recurringReview.deleteMatchedTransactions.failed",
                error: error,
                metadata: [
                    "durationMs": MoneyMapDiagnostics.durationMilliseconds(since: start),
                    "suggestion": suggestion.id
                ]
            )
        }
    }

    private func evidenceMatchesTransaction(_ evidence: RecurringChargeEvidence, _ transaction: Transaction) -> Bool {
        if let plaidTransactionID = evidence.plaidTransactionID?.nilIfBlank,
           transaction.plaidTransactionID == plaidTransactionID {
            return true
        }

        guard let transactionAmount = transaction.amountUSD,
              cents(for: transactionAmount) == cents(for: evidence.amount),
              let transactionDate = transaction.transactionDate ?? transaction.clearingDate,
              Calendar.current.isDate(transactionDate, inSameDayAs: evidence.date) else {
            return false
        }

        if let evidenceAccountID = evidence.plaidAccountID?.nilIfBlank,
           transaction.plaidAccountID != evidenceAccountID {
            return false
        }

        let evidenceName = normalizedMatchText(evidence.displayName)
        return transactionMatchNames(for: transaction)
            .map(normalizedMatchText)
            .contains(evidenceName)
    }

    private func transactionMatchNames(for transaction: Transaction) -> [String] {
        [
            transaction.friendlyName,
            transaction.merchant,
            transaction.transactionDescription
        ]
        .compactMap { $0?.nilIfBlank }
    }

    private func normalizedMatchText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func cents(for amount: Double) -> Int {
        Int((amount * 100).rounded())
    }

    private func markResolved(_ suggestion: RecurringBillSuggestion) {
        setIgnored(true, for: suggestion)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            reviewSuggestions.removeAll { $0.id == suggestion.id }
        }
    }

    private func setIgnored(_ isIgnored: Bool, for suggestion: RecurringBillSuggestion) {
        var ignoredIDs = Set(ignoredSuggestionIDs.split(separator: "|").map(String.init))
        if isIgnored {
            ignoredIDs.insert(suggestion.id)
        } else {
            ignoredIDs.remove(suggestion.id)
        }
        ignoredSuggestionIDs = ignoredIDs.sorted().joined(separator: "|")
    }
}

private struct RecurringReviewMetric: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(.primary)
        .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum RecurringReviewMode: String, CaseIterable, Identifiable {
    case upcoming
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .all:
            return "All"
        }
    }
}

private struct RecurringScheduleItem: Identifiable {
    enum Source {
        case suggestion(RecurringBillSuggestion)
        case bill(Bill)
    }

    let id: String
    let title: String
    let amount: Double
    let date: Date
    let cadenceText: String
    let categoryName: String
    let systemImage: String
    let tint: Color
    let lifecycleState: BillLifecycleState
    let isDetected: Bool
    let amountVaries: Bool
    let source: Source

    init(_ suggestion: RecurringBillSuggestion, occurrenceDate: Date? = nil) {
        let date = occurrenceDate ?? suggestion.nextDueDate
        id = "suggestion-\(suggestion.id)-\(Int(date.timeIntervalSinceReferenceDate))"
        title = suggestion.title
        amount = suggestion.amount
        self.date = date
        cadenceText = suggestion.cadence.title
        categoryName = suggestion.kind.title
        systemImage = suggestion.kind.systemImage
        tint = suggestion.category.color
        lifecycleState = .active
        isDetected = true
        amountVaries = suggestion.amountVaries
        source = .suggestion(suggestion)
    }

    init(bill: Bill, occurrenceDate: Date? = nil, calendar: Calendar) {
        let fallbackDate = occurrenceDate ?? bill.dueDate ?? bill.nextOccurrenceDate(calendar: calendar) ?? .distantFuture
        id = "bill-\(bill.id.uuidString)-\(Int(fallbackDate.timeIntervalSinceReferenceDate))"
        title = bill.name?.nilIfBlank ?? "Recurring Charge"
        amount = bill.amount ?? 0
        date = fallbackDate
        cadenceText = Self.cadenceText(for: bill)
        categoryName = bill.category?.name ?? "Recurring"
        systemImage = bill.category?.icon ?? "repeat"
        tint = bill.category?.color ?? MoneyMapDesign.calmGreen
        lifecycleState = bill.lifecycleState
        isDetected = false
        amountVaries = false
        source = .bill(bill)
    }

    var statusText: String {
        if isDetected {
            return "Detected"
        }

        switch lifecycleState {
        case .active:
            return "Tracked"
        case .paused:
            return "Paused"
        case .canceled:
            return "Canceled"
        }
    }

    var statusTint: Color {
        if isDetected {
            return MoneyMapDesign.calmGreen
        }
        return lifecycleState.color
    }

    var sortPriority: Int {
        if lifecycleState != .active {
            return lifecycleState == .paused ? 2 : 3
        }
        return isDetected ? 0 : 1
    }

    static func byDate(_ lhs: RecurringScheduleItem, _ rhs: RecurringScheduleItem) -> Bool {
        if !Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) {
            return lhs.date < rhs.date
        }
        return byDateThenTitle(lhs, rhs)
    }

    static func byDateThenTitle(_ lhs: RecurringScheduleItem, _ rhs: RecurringScheduleItem) -> Bool {
        if lhs.sortPriority != rhs.sortPriority {
            return lhs.sortPriority < rhs.sortPriority
        }
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func cadenceText(for bill: Bill) -> String {
        guard let interval = bill.recurrenceInterval,
              let unit = bill.recurrenceUnit else {
            return bill.category?.isSubscriptionCategory == true ? "Monthly" : "Recurring"
        }

        if interval == 1 {
            switch unit {
            case .day:
                return "Daily"
            case .week:
                return "Weekly"
            case .month:
                return "Monthly"
            case .year:
                return "Yearly"
            }
        }

        return "Every \(interval) \(unit.pluralName)"
    }
}

private struct RecurringHistoryItem: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let date: Date
    let detail: String
    let systemImage: String
    let tint: Color

    init(suggestion: RecurringBillSuggestion, evidence: RecurringChargeEvidence) {
        id = "\(suggestion.id)-\(evidence.id)"
        title = evidence.displayName
        amount = evidence.amount
        date = evidence.date
        detail = [suggestion.kind.title, evidence.category, evidence.sourceLabel]
            .compactMap { value in
                guard let value = value?.nilIfBlank else { return nil }
                return value
            }
            .joined(separator: " - ")
        systemImage = suggestion.kind.systemImage
        tint = suggestion.category.color
    }
}

private struct RecurringSectionContainer<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .padding(.horizontal)
            }

            VStack(spacing: 0) {
                content
            }
            .background(MoneyMapDesign.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MoneyMapDesign.separator, lineWidth: 1)
            }
            .padding(.horizontal)
        }
    }
}

private struct RecurringStatusNotice: View {
    let title: String
    let systemImage: String
    let tint: Color
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
    }
}

private struct RecurringMonthlySummaryCard: View {
    let total: Double
    let average: Double

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Expected This Month")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(MoneyMapFormatters.currencyString(for: total))
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text("Average \(MoneyMapFormatters.currencyString(for: average))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: comparisonSystemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(comparisonTint)
                    .frame(width: 34, height: 34)
                    .background(comparisonTint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                Text(comparisonText)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(comparisonTint)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(16)
        .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var difference: Double {
        total - average
    }

    private var comparisonText: String {
        guard average > 0 else {
            return "No average yet"
        }

        if abs(difference) < 0.01 {
            return "Matches average"
        }

        let amount = MoneyMapFormatters.currencyString(for: abs(difference))
        return difference > 0 ? "\(amount) higher" : "\(amount) lower"
    }

    private var comparisonTint: Color {
        guard average > 0 else {
            return .secondary
        }

        if abs(difference) < 0.01 {
            return .secondary
        }

        return difference > 0 ? MoneyMapDesign.warningGold : MoneyMapDesign.calmGreen
    }

    private var comparisonSystemImage: String {
        guard average > 0 else {
            return "minus"
        }

        if abs(difference) < 0.01 {
            return "equal"
        }

        return difference > 0 ? "arrow.up" : "arrow.down"
    }
}

private struct RecurringMonthCalendarCard: View {
    let month: Date
    let items: [RecurringScheduleItem]
    let today: Date
    let calendar: Calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(dayValues) { day in
                    RecurringCalendarDayCell(
                        day: day,
                        amount: amountByDay[day.dayKey ?? .distantPast],
                        isToday: day.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false
                    )
                }
            }
        }
        .padding(14)
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private var dayValues: [RecurringCalendarDay] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }

        let leadingCount = leadingPlaceholderCount(for: firstOfMonth)
        var values = (0..<leadingCount).map { RecurringCalendarDay.placeholder(index: $0) }

        values += dayRange.compactMap { day -> RecurringCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else {
                return nil
            }
            return RecurringCalendarDay(date: date, calendar: calendar)
        }

        let trailingCount = (7 - (values.count % 7)) % 7
        values += (0..<trailingCount).map { RecurringCalendarDay.placeholder(index: leadingCount + dayRange.count + $0) }
        return values
    }

    private var amountByDay: [Date: Double] {
        Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }
        .mapValues { values in
            values.reduce(0) { $0 + $1.amount }
        }
    }

    private func leadingPlaceholderCount(for firstOfMonth: Date) -> Int {
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}

private struct RecurringCalendarDay: Identifiable {
    let id: String
    let date: Date?
    let dayNumber: Int?
    let dayKey: Date?

    init(date: Date, calendar: Calendar) {
        self.id = "day-\(calendar.startOfDay(for: date).timeIntervalSince1970)"
        self.date = date
        self.dayNumber = calendar.component(.day, from: date)
        self.dayKey = calendar.startOfDay(for: date)
    }

    static func placeholder(index: Int) -> RecurringCalendarDay {
        RecurringCalendarDay(id: "placeholder-\(index)", date: nil, dayNumber: nil, dayKey: nil)
    }

    private init(id: String, date: Date?, dayNumber: Int?, dayKey: Date?) {
        self.id = id
        self.date = date
        self.dayNumber = dayNumber
        self.dayKey = dayKey
    }
}

private struct RecurringCalendarDayCell: View {
    let day: RecurringCalendarDay
    let amount: Double?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: 34, height: 34)
                }

                Text(dayText)
                    .font(.title3.weight(isToday ? .bold : .regular))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(day.date == nil ? .clear : (isToday ? Color.accentColor : .primary))
            }
            .frame(height: 34)

            Text(amountText)
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayText: String {
        day.dayNumber.map(String.init) ?? "0"
    }

    private var amountText: String {
        guard let amount, amount > 0 else { return "" }
        return compactCurrencyString(for: amount)
    }

    private var accessibilityLabel: String {
        guard let date = day.date else { return "Empty day" }
        let dateText = MoneyMapFormatters.mediumDateString(for: date)
        guard let amount, amount > 0 else {
            return dateText
        }
        return "\(dateText), \(MoneyMapFormatters.currencyString(for: amount)) expected"
    }

    private func compactCurrencyString(for amount: Double) -> String {
        let absoluteAmount = abs(amount)
        let prefix = amount < 0 ? "-$" : "$"

        if absoluteAmount >= 1_000_000 {
            let value = absoluteAmount / 1_000_000
            let digits = absoluteAmount < 10_000_000 ? 1 : 0
            return "\(prefix)\(value.formatted(.number.precision(.fractionLength(digits))))M"
        }

        if absoluteAmount >= 1_000 {
            let value = absoluteAmount / 1_000
            let digits = absoluteAmount < 10_000 ? 1 : 0
            return "\(prefix)\(value.formatted(.number.precision(.fractionLength(digits))))K"
        }

        return "\(prefix)\(absoluteAmount.formatted(.number.precision(.fractionLength(0))))"
    }
}

private struct RecurringScheduleRow: View {
    enum DateStyle {
        case relative
        case full
    }

    let item: RecurringScheduleItem
    let dateStyle: DateStyle
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: item.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(item.tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(item.cadenceText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(MoneyMapFormatters.currencyString(for: item.amount))
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    if item.amountVaries {
                        Text("Variable")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(.secondary)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    } else {
                        Text(item.statusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item.statusTint)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateText: String {
        switch dateStyle {
        case .relative:
            return "Expected \(relativeDateText)"
        case .full:
            return "Expected \(MoneyMapFormatters.mediumDateString(for: item.date))"
        }
    }

    private var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(item.date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(item.date) {
            return "Tomorrow"
        }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: item.date)).day ?? 99
        if (0...6).contains(days) {
            return item.date.formatted(.dateTime.weekday(.wide))
        }
        return item.date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct RecurringHistoryRow: View {
    let item: RecurringHistoryItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(item.tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(MoneyMapFormatters.mediumDateString(for: item.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(MoneyMapFormatters.currencyString(for: item.amount))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RecurringLoadingRow: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            ProgressView(title)
                .padding(.vertical, 26)
            Spacer()
        }
    }
}

private struct RecurringEmptyState: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(detail)
        )
        .padding(.vertical, 26)
    }
}

private struct RecurringReviewSuggestionRow: View {
    let suggestion: RecurringBillSuggestion
    let showDetails: () -> Void

    var body: some View {
        Button {
            showDetails()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
                    .frame(width: 36, height: 34)
                    .background(MoneyMapDesign.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(suggestion.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(suggestion.confidenceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MoneyMapDesign.calmGreen)
                }

                Spacer(minLength: 8)

                Text(MoneyMapFormatters.currencyString(for: suggestion.amount))
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var detailText: String {
        var parts = [
            suggestion.cadence.title,
            "next \(MoneyMapFormatters.mediumDateString(for: suggestion.nextDueDate))",
            "\(suggestion.transactionCount) matching transactions"
        ]
        if suggestion.hasCanceledMatch {
            parts.append("previously canceled")
        }
        return parts.joined(separator: " - ")
    }
}

private struct TrackedRecurringChargeRow: View {
    let bill: Bill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bill.category?.icon ?? "repeat")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 34)
                .background((bill.category?.color ?? MoneyMapDesign.calmGreen), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name ?? "Recurring Item")
                    .font(.headline)
                    .lineLimit(1)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(bill.displayStatusName, systemImage: bill.lifecycleState.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bill.displayStatusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(MoneyMapFormatters.currencyString(for: bill.amount ?? 0))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var detailText: String {
        [
            bill.category?.name,
            recurrenceText,
            bill.dueDate.map { "next \(MoneyMapFormatters.mediumDateString(for: $0))" }
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " - ")
    }

    private var recurrenceText: String? {
        guard let interval = bill.recurrenceInterval,
              let unit = bill.recurrenceUnit else {
            return bill.category?.isSubscriptionCategory == true ? "Subscription" : nil
        }

        if interval == 1 {
            return "Every \(unit.singularName)"
        }

        return "Every \(interval) \(unit.pluralName)"
    }
}

private struct RecurringChargeDetailView: View {
    let suggestion: RecurringBillSuggestion
    let plaidAccounts: [PlaidAccountValue]
    let add: () -> Void
    let ignore: () -> Void
    let deleteTransactions: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteTransactionsConfirmation = false

    var body: some View {
        List {
            summarySection
            sourceSection
            amountSection
            historySection
            cleanupSection
        }
        .navigationTitle(suggestion.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingDeleteTransactionsConfirmation = true
                    } label: {
                        Label("Delete Matched Transactions", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete matched transactions?",
            isPresented: $showingDeleteTransactionsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(suggestion.evidence.count) Transaction\(suggestion.evidence.count == 1 ? "" : "s")", role: .destructive) {
                deleteTransactions()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the imported transactions used for this recurring charge. Existing bills and subscriptions are not deleted.")
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    add()
                    dismiss()
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                Button(role: .destructive) {
                    ignore()
                    dismiss()
                } label: {
                    Label("Ignore", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private var cleanupSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteTransactionsConfirmation = true
            } label: {
                Label("Delete Matched Transactions", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } footer: {
            Text("Use this for test imports or duplicate imported charges. MoneyMap deletes the matched transaction rows only.")
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Type", value: suggestion.kind.title)
            LabeledContent("Category", value: suggestion.category.name)
            LabeledContent("Cadence", value: suggestion.cadence.title)
            LabeledContent("Next due", value: MoneyMapFormatters.mediumDateString(for: suggestion.nextDueDate))
            LabeledContent("Confidence", value: suggestion.confidenceLabel)
            if suggestion.hasCanceledMatch {
                Label("Matches a canceled bill. Restoring keeps the old bill history instead of creating a duplicate.", systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Summary")
        }
    }

    private var sourceSection: some View {
        Section {
            ForEach(sourceRows, id: \.self) { source in
                Label(source, systemImage: "creditcard")
            }
        } header: {
            Text("Source")
        } footer: {
            Text("MoneyMap shows the charged account first, then falls back to the import source when account details are unavailable.")
        }
    }

    private var amountSection: some View {
        Section {
            LabeledContent("Average", value: MoneyMapFormatters.currencyString(for: suggestion.amount))
            LabeledContent("Lowest", value: MoneyMapFormatters.currencyString(for: suggestion.minimumEvidenceAmount))
            LabeledContent("Highest", value: MoneyMapFormatters.currencyString(for: suggestion.maximumEvidenceAmount))
            Label(
                suggestion.amountVaries ? "The amount changed across matching transactions." : "The amount was the same each time.",
                systemImage: suggestion.amountVaries ? "chart.line.uptrend.xyaxis" : "equal.circle"
            )
            .foregroundStyle(.secondary)
        } header: {
            Text("Amount Pattern")
        }
    }

    private var historySection: some View {
        Section {
            ForEach(suggestion.evidence.sorted { $0.date > $1.date }) { evidence in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(MoneyMapFormatters.mediumDateString(for: evidence.date))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(MoneyMapFormatters.currencyString(for: evidence.amount))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }

                    Text(transactionDetail(for: evidence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Matched Transactions")
        }
    }

    private var sourceRows: [String] {
        let rows = suggestion.evidence.map(chargeSourceLabel(for:))
        return Array(Set(rows)).sorted()
    }

    private var plaidAccountsByID: [String: PlaidAccountValue] {
        Dictionary(plaidAccounts.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var primaryActionTitle: String {
        suggestion.hasCanceledMatch ? "Restore" : suggestion.kind.addActionTitle
    }

    private var primaryActionImage: String {
        suggestion.hasCanceledMatch ? "arrow.uturn.backward.circle" : "plus.circle"
    }

    private func transactionDetail(for evidence: RecurringChargeEvidence) -> String {
        var parts = [evidence.displayName]
        if let category = evidence.category, !category.isEmpty {
            parts.append(category)
        }
        parts.append(chargeSourceLabel(for: evidence))
        return parts.joined(separator: " - ")
    }

    private func chargeSourceLabel(for evidence: RecurringChargeEvidence) -> String {
        let linkedCardName = evidence.linkedCardName?.nilIfBlank
        let account = evidence.plaidAccountID.flatMap { plaidAccountsByID[$0] }
        let primaryName = linkedCardName ?? account?.displayName.nilIfBlank
        let institutionName = evidence.linkedCardInstitutionName?.nilIfBlank ?? account?.institutionName?.nilIfBlank
        let lastFourLabel = evidence.linkedCardLastFourDigits.map { "Ending \($0)" } ?? account?.lastFourLabel

        let cardParts = [primaryName, institutionName, lastFourLabel]
            .compactMap { $0 }
            .removingDuplicates()
        if !cardParts.isEmpty {
            return cardParts.joined(separator: " - ")
        }

        if let account {
            return accountDisplayName(account)
        }

        if let plaidAccountID = evidence.plaidAccountID?.nilIfBlank {
            return "Plaid account \(String(plaidAccountID.suffix(6)))"
        }

        return evidence.sourceLabel
    }

    private func accountDisplayName(_ account: PlaidAccountValue) -> String {
        var parts = [account.displayName]
        if let institutionName = account.institutionName?.nilIfBlank {
            parts.append(institutionName)
        }
        if let lastFourLabel = account.lastFourLabel {
            parts.append(lastFourLabel)
        }
        return parts.joined(separator: " - ")
    }
}

private struct IgnoredRecurringChargesView: View {
    let suggestions: [RecurringBillSuggestion]
    let restore: (RecurringBillSuggestion) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if suggestions.isEmpty {
                ContentUnavailableView(
                    "No Ignored Charges",
                    systemImage: "archivebox",
                    description: Text("Ignored recurring charges will appear here so you can bring them back.")
                )
            } else {
                Section {
                    ForEach(suggestions) { suggestion in
                        Button {
                            restore(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: suggestion.kind.systemImage)
                                    .foregroundStyle(suggestion.category.color)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(suggestion.kind.title) - \(MoneyMapFormatters.currencyString(for: suggestion.amount))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Label("Restore", systemImage: "arrow.uturn.backward.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MoneyMapDesign.calmGreen)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                } footer: {
                    Text("Restored charges return to the review list.")
                }
            }
        }
        .navigationTitle("Ignored")
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension BillLifecycleState {
    var sortPriority: Int {
        switch self {
        case .active:
            return 0
        case .paused:
            return 1
        case .canceled:
            return 2
        }
    }
}

private extension RecurrenceUnit {
    var singularName: String {
        switch self {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .year:
            return "year"
        }
    }

    var pluralName: String {
        "\(singularName)s"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Calendar {
    func startOfMonth(containing date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

#Preview {
    NavigationStack {
        RecurringBillReviewView()
    }
    .modelContainer(SharedModelContainerFactory.makeInMemory())
}
