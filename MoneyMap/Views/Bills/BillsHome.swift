//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData
import AppIntents

struct BillsHome: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query private var bills: [Bill]
    @Query private var goals: [Goal]
    @Query private var transactions: [Transaction]
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @AppStorage(RecurringBillDetector.ignoredSuggestionIDsKey) private var ignoredRecurringBillSuggestionIDs = ""
    
    @State private var addingBill = false
    @State private var editingBalance = false
    @State private var editingLimit = false
    @State private var billToEdit: Bill?
    @State private var alertValue: String = ""
    @State private var makingPayment = false
    @State private var viewingBill: Bill?
    @State private var destination: BillsNavigationTarget?
    @State private var selectedBillForEditor: Bill?
    @State private var billPendingDelete: Bill?
    @State private var billPendingCancel: Bill?
    @State private var billPendingResume: Bill?
    @State private var showingDeleteConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var recurringBillSuggestions: [RecurringBillSuggestion] = []
    
    var body: some View {
        NavigationStack {
            List {
                overviewSection
                recurringSuggestionsSection

                if !bills.creditCards.isEmpty {
                    CreditCardSection(
                        bills: bills,
                        billToEdit: $billToEdit,
                        alertValue: $alertValue,
                        editingBalance: $editingBalance,
                        editingLimit: $editingLimit,
                        makingPayment: $makingPayment
                    )
                }

                if bills.withoutCreditCards.isEmpty {
                    emptyBillsSection
                } else {
                    billSection("Needs Attention", bills: needsAttentionBills)
                    billSection("Upcoming", bills: upcomingBills)
                    billSection("Paid", bills: paidBills)
                    billSection("Paused", bills: pausedBills)
                    billSection("Canceled", bills: canceledBills)
                }
            }
            .navigationTitle("Bills")
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(MoneyMapAction.addBill.title, systemImage: MoneyMapAction.addBill.systemImage) {
                        addingBill.toggle()
                    }
                }
            }
            .sheet(isPresented: $addingBill) {
                BillEditor()
            }
            .sheet(item: $selectedBillForEditor) { bill in
                BillEditor(bill: bill)
            }
            .sheet(item: $billPendingResume) { bill in
                BillDateActionSheet(
                    title: "Resume",
                    bill: bill,
                    defaultDate: defaultScheduleDate(for: bill),
                    confirmTitle: "Resume"
                ) { date in
                    resume(bill, on: date)
                }
            }
            .navigationDestination(item: $viewingBill, destination: { bill in
                BillView(bill: bill)
            })
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .upcomingBills:
                    BillsView(mode: .upcoming)
                case .cardUtilization:
                    CardUtilizationView()
                }
            }
            .alert(billToEdit?.name ?? "Current Balance", isPresented: $editingBalance) {
                TextField(balancePlaceholder, text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    billToEdit?.creditCardDetails?.cardBalance = Double(alertValue) ?? 0
                    saveBillChanges()
                    editingBalance = false
                    alertValue.removeAll()
                }
            } message: {
                Text("What is your current balance?")
            }
            .alert(billToEdit?.name ?? "Current Limit", isPresented: $editingLimit) {
                TextField(limitPlaceholder, text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    billToEdit?.creditCardDetails?.creditLimit = Double(alertValue) ?? 0
                    saveBillChanges()
                    editingLimit = false
                    alertValue.removeAll()
                }
            } message: {
                Text("What is your current limit?")
            }
            .alert(paymentTitle, isPresented: $makingPayment) {
                TextField(paymentPlaceholder, text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    if let bill = billToEdit {
                        let amount = Double(alertValue) ?? 0
                        let previousBalance = bill.creditCardDetails?.cardBalance
                        let previousDatePaid = bill.datePaid
                        let previousDueDate = bill.dueDate
                        let previousStatus = bill.status
                        bill.makePayment(of: amount)
                        AuditService.logBillPayment(
                            bill: bill,
                            previousBalance: previousBalance,
                            previousDatePaid: previousDatePaid,
                            previousDueDate: previousDueDate,
                            previousStatus: previousStatus,
                            amount: amount,
                            context: modelContext
                        )
                        try? modelContext.save()
                        AppRefreshEvents.notifyBillsDidChange()
                        MoneyMapIntentDonations.donateMarkBillPaid(bill, paymentAmount: amount)
                    }
                    makingPayment = false
                    alertValue.removeAll()
                }
            } message: {
                Text("How much would you like to pay off this bill?")
            }
            .confirmationDialog(
                "Delete \(billPendingDelete?.name ?? "this bill")?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Bill", role: .destructive) {
                    if let billPendingDelete {
                        delete(billPendingDelete)
                    }
                    billPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    billPendingDelete = nil
                }
            } message: {
                Text("This removes the bill from MoneyMap.")
            }
            .confirmationDialog(
                "Cancel \(billPendingCancel?.name ?? "this subscription")?",
                isPresented: $showingCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancel Subscription", role: .destructive) {
                    if let billPendingCancel {
                        cancel(billPendingCancel)
                    }
                    billPendingCancel = nil
                }
                Button("Keep Active", role: .cancel) {
                    billPendingCancel = nil
                }
            } message: {
                Text("This keeps the bill in your history and removes it from upcoming review.")
            }
            .onAppear {
                routeToRequestedBillIfNeeded()
                routeToRequestedDestinationIfNeeded()
                syncSystemIntegrations()
                refreshRecurringBillSuggestions()
            }
            .onChange(of: deepLinkManager.requestedBillID) { _, _ in
                routeToRequestedBillIfNeeded()
            }
            .onChange(of: deepLinkManager.requestedBillsDestination) { _, _ in
                routeToRequestedDestinationIfNeeded()
            }
            .onChange(of: bills.count) { _, _ in
                routeToRequestedBillIfNeeded()
            }
            .onChange(of: billsIntegrationSignature) { _, _ in
                syncSystemIntegrations()
                refreshRecurringBillSuggestions()
            }
            .onChange(of: transactions.count) { _, _ in
                refreshRecurringBillSuggestions()
            }
            .onChange(of: ignoredRecurringBillSuggestionIDs) { _, _ in
                refreshRecurringBillSuggestions()
            }
        }
    }

    private var activeBills: [Bill] {
        bills.withoutCreditCards
            .filter { $0.lifecycleState == .active }
            .sorted(by: Bill.byDate)
    }

    private var unpaidActiveBills: [Bill] {
        activeBills.filter { $0.status != .paid }
    }

    private var needsAttentionBills: [Bill] {
        unpaidActiveBills.filter(billNeedsAttention)
    }

    private var upcomingBills: [Bill] {
        unpaidActiveBills.filter { !billNeedsAttention($0) }
    }

    private var paidBills: [Bill] {
        activeBills
            .filter { $0.status == .paid }
            .sorted { lhs, rhs in
                (lhs.datePaid ?? lhs.dueDate ?? .distantPast) > (rhs.datePaid ?? rhs.dueDate ?? .distantPast)
            }
    }

    private var pausedBills: [Bill] {
        lifecycleBills(.paused)
    }

    private var canceledBills: [Bill] {
        lifecycleBills(.canceled)
    }

    private var today: Date {
        Calendar.current.startOfDay(for: .now)
    }

    private func billNeedsAttention(_ bill: Bill) -> Bool {
        guard bill.lifecycleState == .active else { return false }
        guard bill.status != .paid else { return false }
        guard let dueDate = bill.dueDate else { return true }

        let dueDay = Calendar.current.startOfDay(for: dueDate)
        if dueDay < today {
            return true
        }

        if dueDay == today {
            return bill.paymentMode != .autopay && bill.paymentMode != .inPerson
        }

        return false
    }

    private var overviewSection: some View {
        Section {
            BillsOverviewRow(
                needsAttentionCount: needsAttentionBills.count,
                upcomingCount: upcomingBills.count,
                paidCount: paidBills.count,
                inactiveCount: pausedBills.count + canceledBills.count,
                unpaidAmount: unpaidActiveBills.reduce(0) { $0 + ($1.amount ?? 0) }
            )

            NavigationLink {
                RecurringBillReviewView(initialSuggestions: recurringBillSuggestions)
            } label: {
                BillsCalendarLinkRow(
                    savedBillCount: bills.withoutCreditCards.count,
                    detectedCount: recurringBillSuggestions.count,
                    nextDueDate: nextActiveDueDate
                )
            }
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private var recurringSuggestionsSection: some View {
        if !recurringBillSuggestions.isEmpty {
            Section {
                ForEach(recurringBillSuggestions.prefix(4)) { suggestion in
                    RecurringBillSuggestionRow(
                        suggestion: suggestion,
                        add: { createBill(from: suggestion) },
                        ignore: { ignore(suggestion) }
                    )
                }
            } header: {
                Text("Detected Charges")
            } footer: {
                Text("MoneyMap found repeating transactions from imported bank activity. Review each one before adding it as a bill.")
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
    }

    private var emptyBillsSection: some View {
        Section {
            ContentUnavailableView(
                "No Bills Yet",
                systemImage: "list.bullet.clipboard",
                description: Text("Add bills to track what needs attention.")
            )
        }
        .listRowBackground(MoneyMapDesign.surfaceBackground)
    }

    @ViewBuilder
    private func billSection(_ title: String, bills: [Bill]) -> some View {
        if !bills.isEmpty {
            Section {
                ForEach(bills) { bill in
                    ManagedBillRow(
                        bill: bill,
                        paymentMethods: paymentMethods,
                        markPaid: markPaid,
                        edit: { selectedBillForEditor = $0 },
                        pause: pause,
                        requestCancel: requestCancel,
                        requestResume: { billPendingResume = $0 },
                        requestDelete: requestDelete
                    )
                }
            } header: {
                Text(title)
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
    }

    private var billsIntegrationSignature: String {
        bills
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { bill in
                let name = bill.name ?? ""
                let amount = bill.amount ?? 0
                let due = bill.dueDate?.timeIntervalSince1970 ?? 0
                let paid = bill.datePaid?.timeIntervalSince1970 ?? 0
                let lifecycle = bill.lifecycleState.rawValue
                return "\(bill.id.uuidString)|\(name)|\(amount)|\(due)|\(paid)|\(lifecycle)"
            }
            .joined(separator: ";")
    }

    private var nextActiveDueDate: Date? {
        unpaidActiveBills
            .compactMap(\.dueDate)
            .min()
    }

    private func lifecycleBills(_ state: BillLifecycleState) -> [Bill] {
        bills.withoutCreditCards
            .filter { $0.lifecycleState == state }
            .sorted(by: Bill.byDate)
    }

    private func syncSystemIntegrations() {
        refreshBillStatuses()
        SpotlightIndexer.reindexBills(bills)
        SpotlightIndexer.reindexTransactions(bills.flatMap { $0.transactions ?? [] })
        notificationManager.scheduleBillDueNotifications(for: bills)
    }

    private func refreshBillStatuses() {
        if BillPaymentMatcher.refreshStatuses(for: bills, transactions: transactions) {
            try? modelContext.save()
        }
    }

    private func routeToRequestedBillIfNeeded() {
        guard let requestedBillID = deepLinkManager.requestedBillID,
              let targetBill = bills.first(where: { $0.id == requestedBillID }) else {
            return
        }
        viewingBill = targetBill
        deepLinkManager.requestedBillID = nil
    }

    private func routeToRequestedDestinationIfNeeded() {
        guard let requestedDestination = deepLinkManager.requestedBillsDestination else {
            return
        }
        destination = requestedDestination
        deepLinkManager.requestedBillsDestination = nil
    }

    private func refreshRecurringBillSuggestions() {
        let ignoredIDs = Set(ignoredRecurringBillSuggestionIDs.split(separator: "|").map(String.init))
        recurringBillSuggestions = RecurringBillDetector
            .detect(transactions: transactions, existingBills: bills)
            .filter { !ignoredIDs.contains($0.id) }
    }

    private func requestDelete(_ bill: Bill) {
        billPendingDelete = bill
        showingDeleteConfirmation = true
    }

    private func requestCancel(_ bill: Bill) {
        billPendingCancel = bill
        showingCancelConfirmation = true
    }

    private func markPaid(_ bill: Bill) {
        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status

        bill.datePaid = .now
        bill.status = .paid
        bill.checkStatus()

        AuditService.logBillPayment(
            bill: bill,
            previousBalance: previousBalance,
            previousDatePaid: previousDatePaid,
            previousDueDate: previousDueDate,
            previousStatus: previousStatus,
            amount: bill.amount ?? 0,
            context: modelContext
        )
        saveBillChanges()
        MoneyMapIntentDonations.donateMarkBillPaid(bill)
    }

    private func pause(_ bill: Bill) {
        bill.pause()
        saveBillChanges()
    }

    private func cancel(_ bill: Bill) {
        bill.cancel()
        saveBillChanges()
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
        ignore(suggestion)
        saveBillChanges()
    }

    private func ignore(_ suggestion: RecurringBillSuggestion) {
        var ignoredIDs = Set(ignoredRecurringBillSuggestionIDs.split(separator: "|").map(String.init))
        ignoredIDs.insert(suggestion.id)
        ignoredRecurringBillSuggestionIDs = ignoredIDs.sorted().joined(separator: "|")
        recurringBillSuggestions.removeAll { $0.id == suggestion.id }
    }

    private func resume(_ bill: Bill, on date: Date) {
        bill.resume(nextDueDate: date)
        saveBillChanges()
    }

    private func delete(_ bill: Bill) {
        modelContext.delete(bill)
        saveBillChanges()
    }

    private func defaultScheduleDate(for bill: Bill) -> Date {
        let calendar = Calendar.current
        return bill.nextOccurrenceDate(calendar: calendar) ??
            calendar.date(byAdding: .day, value: 7, to: bill.dueDate ?? .now) ??
            .now
    }

    private func saveBillChanges() {
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
    }
    
    var paymentPlaceholder: String {
        if let payment = billToEdit?.creditCardDetails?.recommendedPayment {
            return "Recommended: \(payment.currency)"
        } else {
            return "Enter Payment"
        }
    }
    
    var balancePlaceholder: String {
        if let balance = billToEdit?.creditCardDetails?.cardBalance {
            return balance.currency
        } else {
            return "Enter Balance"
        }
    }
    
    var limitPlaceholder: String {
        if let balance = billToEdit?.creditCardDetails?.creditLimit {
            return balance.currency
        } else {
            return "Enter Balance"
        }
    }
        
    var paymentTitle: String {
        
        if let billToEdit, let name = billToEdit.name {
            return name
        }
        return "Payment Amount"
    }
    
}

private struct BillsOverviewRow: View {
    let needsAttentionCount: Int
    let upcomingCount: Int
    let paidCount: Int
    let inactiveCount: Int
    let unpaidAmount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                        .fill(primaryColor.opacity(0.14))

                    Image(systemName: primaryIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(primaryColor)
                        .accessibilityHidden(true)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryTitle)
                        .font(.headline)
                    Text(primarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Text("\(needsAttentionCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(primaryColor)
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                BillsOverviewMetric(
                    title: "Upcoming",
                    value: "\(upcomingCount)",
                    systemImage: "calendar",
                    color: MoneyMapDesign.warningGold
                )
                BillsOverviewMetric(
                    title: "Unpaid",
                    value: MoneyMapFormatters.currencyString(for: unpaidAmount),
                    systemImage: "banknote",
                    color: MoneyMapDesign.calmGreen
                )
                BillsOverviewMetric(
                    title: "Paid",
                    value: "\(paidCount)",
                    systemImage: "checkmark.circle.fill",
                    color: MoneyMapDesign.sage
                )
                BillsOverviewMetric(
                    title: "Paused",
                    value: "\(inactiveCount)",
                    systemImage: "pause.circle.fill",
                    color: MoneyMapDesign.sage
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var primaryColor: Color {
        needsAttentionCount > 0 ? MoneyMapDesign.attentionRed : MoneyMapDesign.calmGreen
    }

    private var primaryIcon: String {
        needsAttentionCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    private var primaryTitle: String {
        needsAttentionCount > 0 ? "Needs Attention" : "Bills Look Good"
    }

    private var primarySubtitle: String {
        needsAttentionCount == 1 ? "1 bill needs review today." :
            needsAttentionCount > 1 ? "\(needsAttentionCount) bills need review today." :
            "Nothing is due or overdue right now."
    }
}

private struct BillsOverviewMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(MoneyMapDesign.controlBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
    }
}

private struct BillsCalendarLinkRow: View {
    let savedBillCount: Int
    let detectedCount: Int
    let nextDueDate: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(MoneyMapDesign.warningGold)
                .frame(width: 36, height: 36)
                .background(MoneyMapDesign.controlBackground)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bill Calendar")
                    .font(.headline)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if detectedCount > 0 {
                Text("\(detectedCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(MoneyMapDesign.calmGreen, in: Capsule())
                    .accessibilityLabel("\(detectedCount) detected charges")
            }
        }
        .padding(.vertical, 4)
    }

    private var detailText: String {
        var parts = ["\(savedBillCount) saved"]
        if detectedCount > 0 {
            parts.append("\(detectedCount) detected")
        }
        if let nextDueDate {
            parts.append("next \(MoneyMapFormatters.mediumDateString(for: nextDueDate))")
        }
        return parts.joined(separator: " - ")
    }
}

private struct ManagedBillRow: View {
    let bill: Bill
    let paymentMethods: [PaymentMethod]
    let markPaid: (Bill) -> Void
    let edit: (Bill) -> Void
    let pause: (Bill) -> Void
    let requestCancel: (Bill) -> Void
    let requestResume: (Bill) -> Void
    let requestDelete: (Bill) -> Void

    var body: some View {
        NavigationLink {
            BillView(bill: bill)
        } label: {
            BillStateRow(bill: bill, paymentMethods: paymentMethods)
        }
        .userActivity("com.heyjoshsmith.MoneyMap.viewingBillRow") { activity in
            let entity = BillEntity(bill)
            activity.title = "Reviewing \(entity.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canMarkPaid {
                Button("Mark Paid", systemImage: "checkmark.circle") {
                    markPaid(bill)
                }
                .tint(MoneyMapDesign.calmGreen)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Edit", systemImage: "pencil") {
                edit(bill)
            }
            .tint(MoneyMapDesign.sage)

            if bill.lifecycleState == .active {
                Button("Cancel", systemImage: "xmark.circle") {
                    requestCancel(bill)
                }
                .tint(MoneyMapDesign.attentionRed)
            }
        }
        .contextMenu {
            Button("Edit Bill", systemImage: "pencil") {
                edit(bill)
            }

            if canMarkPaid {
                Button("Mark Paid", systemImage: "checkmark.circle") {
                    markPaid(bill)
                }
            }

            if bill.lifecycleState == .paused || bill.lifecycleState == .canceled {
                Button("Resume", systemImage: "play.circle") {
                    requestResume(bill)
                }
            } else if bill.lifecycleState == .active {
                Button("Pause", systemImage: "pause.circle") {
                    pause(bill)
                }
                Button("Cancel Subscription", systemImage: "xmark.circle", role: .destructive) {
                    requestCancel(bill)
                }
            }

            Button("Delete Bill", systemImage: "trash", role: .destructive) {
                requestDelete(bill)
            }
        }
    }

    private var canMarkPaid: Bool {
        bill.lifecycleState == .active &&
            bill.status != .paid &&
            bill.paymentMode != .autopay &&
            bill.paymentMode != .inPerson
    }
}

struct BillStateRow: View {
    let bill: Bill
    let paymentMethods: [PaymentMethod]

    private var statusColor: Color {
        bill.displayStatusColor
    }

    private var statusText: String {
        if bill.lifecycleState != .active {
            return bill.lifecycleState.title
        }
        if bill.status == .paid {
            return "Paid"
        }
        guard bill.dueDate != nil else {
            return "Needs Date"
        }
        return bill.status?.name ?? "Needs Review"
    }

    private var statusImage: String {
        if bill.lifecycleState != .active {
            return bill.lifecycleState.icon
        }
        switch bill.status {
        case .paid:
            return "checkmark.circle.fill"
        case .overdue:
            return "exclamationmark.circle.fill"
        case .upcoming:
            return "calendar"
        case nil:
            return "questionmark.circle"
        }
    }

    private var detailText: String {
        if bill.lifecycleState != .active {
            return bill.lifecycleState == .paused ? "Paused until resumed" : "Canceled and kept for history"
        }

        if bill.status == .paid {
            if let datePaid = bill.datePaid {
                return "Paid \(MoneyMapFormatters.mediumDateString(for: datePaid))"
            }
            return "Marked paid"
        }

        guard let dueDate = bill.dueDate else {
            return "No due date"
        }

        let calendar = Calendar.current
        let dueDay = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: .now)

        if dueDay < today {
            return "Overdue since \(MoneyMapFormatters.mediumDateString(for: dueDate))"
        }
        if dueDay == today {
            return "Due today"
        }
        return "Due \(MoneyMapFormatters.mediumDateString(for: dueDate))"
    }

    private var paymentText: String? {
        if bill.paymentMode == .inPerson {
            return "Watching transactions"
        }
        guard bill.paymentMode == .autopay else { return nil }
        if let methodName = bill.paymentMethodName(in: paymentMethods) {
            return "Autopay from \(methodName)"
        }
        return "Autopay"
    }

    private var paymentColor: Color {
        bill.paymentMode == .autopay || bill.paymentMode == .inPerson ? MoneyMapDesign.calmGreen : .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bill.category?.icon ?? "questionmark.circle")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background((bill.category?.color ?? .gray).gradient)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name ?? "Untitled")
                    .font(.headline)
                    .lineLimit(1)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let paymentText {
                    HStack(spacing: 5) {
                        Image(systemName: bill.paymentModeIcon)
                            .imageScale(.medium)
                            .frame(width: 16)
                        Text(paymentText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paymentColor)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(bill.amount ?? 0, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: statusImage)
                        .imageScale(.medium)
                    Text(statusText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecurringBillSuggestionRow: View {
    let suggestion: RecurringBillSuggestion
    let add: () -> Void
    let ignore: () -> Void

    private var amountText: String {
        MoneyMapFormatters.currencyString(for: suggestion.amount)
    }

    private var detailText: String {
        [
            suggestion.cadence.title,
            "next \(MoneyMapFormatters.mediumDateString(for: suggestion.nextDueDate))",
            "\(suggestion.transactionCount) matches"
        ].joined(separator: " - ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: suggestion.category.icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(suggestion.category.color.gradient)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(suggestion.confidenceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MoneyMapDesign.calmGreen)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(amountText)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button("Ignore", action: ignore)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)

                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}



#Preview {
      let (container, paydayManager) = PreviewDataProvider.createContainer()
      BillsHome()
          .environmentObject(paydayManager)
          .environmentObject(DeepLinkManager())
          .environmentObject(NotificationManager())
          .modelContainer(container)
  }
