//
//  BillReviewFlowView.swift
//  MoneyMap
//
//  Created by Codex on 7/1/26.
//

import SwiftUI
import SwiftData

struct BillReviewFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var reviewQueue: [Bill]
    @State private var reviewedBills: [BillReviewResult] = []
    @State private var dragOffset: CGSize = .zero
    @State private var showingDelayPicker = false
    @State private var showingCancelConfirmation = false

    init(bills: [Bill]) {
        let unpaidBills = bills
            .filter(Self.shouldReview)
            .sorted(by: Bill.byDate)
        _reviewQueue = State(initialValue: unpaidBills)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MoneyMapDesign.groupedBackground
                    .ignoresSafeArea()

                if let currentBill {
                    reviewDeck(currentBill)
                } else {
                    BillReviewResultsView(results: reviewedBills) { url in
                        openURL(url)
                    }
                }
            }
            .navigationTitle("Review Bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingDelayPicker) {
                if let currentBill {
                    BillDateActionSheet(
                        title: "Delay",
                        bill: currentBill,
                        defaultDate: defaultDelayDate(for: currentBill),
                        confirmTitle: "Delay"
                    ) { date in
                        completeCurrentBill(as: .delayed, scheduledDate: date)
                    }
                }
            }
            .confirmationDialog(
                "Cancel \(currentBill?.name ?? "this subscription")?",
                isPresented: $showingCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancel Subscription", role: .destructive) {
                    completeCurrentBill(as: .canceled)
                }
                Button("Keep Active", role: .cancel) { }
            } message: {
                Text("This keeps the bill in your history and removes it from future payment review.")
            }
        }
    }

    private var currentBill: Bill? {
        reviewQueue.first
    }

    private var totalCount: Int {
        reviewedBills.count + reviewQueue.count
    }

    private static func shouldReview(_ bill: Bill) -> Bool {
        guard bill.lifecycleState == .active else { return false }
        guard bill.status != .paid else { return false }
        guard let dueDate = bill.dueDate else { return true }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = calendar.startOfDay(for: dueDate)

        if dueDay < today {
            return true
        }

        if dueDay == today {
            return bill.paymentMode != .autopay && bill.paymentMode != .inPerson
        }

        return false
    }

    private func reviewDeck(_ bill: Bill) -> some View {
        VStack(spacing: 18) {
            Text("\(reviewedBills.count + 1) of \(max(totalCount, 1))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            ZStack {
                ForEach(Array(reviewQueue.prefix(3).enumerated()).reversed(), id: \.element.id) { index, bill in
                    BillReviewCard(
                        bill: bill,
                        paidOpacity: paidIntentOpacity,
                        missedOpacity: missedIntentOpacity,
                        delayOpacity: delayIntentOpacity,
                        cancelOpacity: cancelIntentOpacity
                    )
                    .scaleEffect(index == 0 ? 1 : 1 - (CGFloat(index) * 0.045))
                    .offset(y: CGFloat(index) * 14)
                    .offset(index == 0 ? dragOffset : .zero)
                    .rotationEffect(.degrees(index == 0 ? Double(dragOffset.width / 18) : 0))
                    .zIndex(Double(3 - index))
                    .gesture(dragGesture)
                    .accessibilitySortPriority(index == 0 ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 440)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        requestDelayCurrentBill()
                    } label: {
                        MoneyMapNeutralButtonLabel(
                            title: "Delay",
                            systemImage: "calendar.badge.clock",
                            iconColor: MoneyMapDesign.warningGold
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        requestCancelCurrentBill()
                    } label: {
                        MoneyMapNeutralButtonLabel(
                            title: "Cancel",
                            systemImage: "xmark.circle",
                            iconColor: MoneyMapDesign.attentionRed
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                HStack(spacing: 12) {
                    Button {
                        completeCurrentBill(as: .missed)
                    } label: {
                        MoneyMapNeutralButtonLabel(
                            title: "Missed",
                            systemImage: "xmark.circle.fill",
                            iconColor: MoneyMapDesign.attentionRed
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        completeCurrentBill(as: .paid)
                    } label: {
                        MoneyMapNeutralButtonLabel(
                            title: "Paid",
                            systemImage: "checkmark.circle.fill",
                            iconColor: MoneyMapDesign.calmGreen
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .padding()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let translation = value.translation
                if abs(translation.width) >= abs(translation.height), translation.width > 120 {
                    completeCurrentBill(as: .paid)
                } else if abs(translation.width) >= abs(translation.height), translation.width < -120 {
                    completeCurrentBill(as: .missed)
                } else if abs(translation.height) > abs(translation.width), translation.height < -120 {
                    requestDelayCurrentBill()
                } else if abs(translation.height) > abs(translation.width), translation.height > 120 {
                    requestCancelCurrentBill()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private var paidIntentOpacity: Double {
        min(max(Double(dragOffset.width / 120), 0), 1)
    }

    private var missedIntentOpacity: Double {
        min(max(Double(-dragOffset.width / 120), 0), 1)
    }

    private var delayIntentOpacity: Double {
        min(max(Double(-dragOffset.height / 120), 0), 1)
    }

    private var cancelIntentOpacity: Double {
        min(max(Double(dragOffset.height / 120), 0), 1)
    }

    private func requestDelayCurrentBill() {
        guard currentBill != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = .zero
        }
        showingDelayPicker = true
    }

    private func requestCancelCurrentBill() {
        guard currentBill != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = .zero
        }
        showingCancelConfirmation = true
    }

    private func completeCurrentBill(as decision: BillReviewDecision, scheduledDate: Date? = nil) {
        guard let bill = currentBill else { return }

        let amount: Double?
        switch decision {
        case .paid:
            amount = markPaid(bill)
        case .missed:
            bill.checkStatus()
            try? modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            amount = nil
        case .delayed:
            guard let scheduledDate else {
                requestDelayCurrentBill()
                return
            }
            bill.delay(to: scheduledDate)
            try? modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            amount = nil
        case .canceled:
            bill.cancel()
            try? modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            amount = nil
        }

        reviewedBills.append(
            BillReviewResult(
                bill: bill,
                decision: decision,
                amount: amount,
                scheduledDate: scheduledDate
            )
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            _ = reviewQueue.removeFirst()
            dragOffset = .zero
        }
    }

    @discardableResult
    private func markPaid(_ bill: Bill) -> Double {
        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status
        let amount = paymentAmount(for: bill)

        if bill.category == .creditCard, amount > 0 {
            bill.makePayment(of: amount)
        } else {
            bill.datePaid = .now
            bill.status = .paid
            bill.checkStatus()
        }

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
        return amount
    }

    private func paymentAmount(for bill: Bill) -> Double {
        if bill.category == .creditCard {
            return max(
                bill.creditCardDetails?.recommendedPayment ??
                bill.creditCardDetails?.effectiveMinimumPayment ??
                bill.amount ??
                0,
                0
            )
        }

        return max(bill.amount ?? 0, 0)
    }

    private func defaultDelayDate(for bill: Bill) -> Date {
        let calendar = Calendar.current
        return bill.nextOccurrenceDate(calendar: calendar) ??
            calendar.date(byAdding: .day, value: 7, to: bill.dueDate ?? .now) ??
            .now
    }
}

private struct BillReviewCard: View {
    let bill: Bill
    let paidOpacity: Double
    let missedOpacity: Double
    let delayOpacity: Double
    let cancelOpacity: Double
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]

    private var dueText: String {
        guard let dueDate = bill.dueDate else { return "No due date" }
        if Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date()) {
            return "Overdue since \(MoneyMapFormatters.mediumDateString(for: dueDate))"
        }
        return "Due \(MoneyMapFormatters.mediumDateString(for: dueDate))"
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MoneyMapDesign.surfaceBackground)
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 18)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    Image(systemName: bill.category?.icon ?? "questionmark.circle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background((bill.category?.color ?? .gray).gradient)
                        .clipShape(.rect(cornerRadius: MoneyMapDesign.cornerRadius))
                        .accessibilityHidden(true)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(bill.displayStatusName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(bill.displayStatusColor)
                        Text(dueText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(bill.name ?? "Untitled")
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    MoneyMapMoneyText(
                        amount: bill.amount ?? 0,
                        font: .system(.largeTitle, design: .rounded, weight: .bold),
                        foregroundStyle: .primary
                    )
                }

                if bill.paymentMode == .inPerson {
                    Label("Transaction tracked", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let paymentHost = bill.paymentHost {
                    Label(paymentHost, systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Payment link not set", systemImage: "link.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Label(paymentText, systemImage: bill.paymentModeIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(bill.paymentMode == .autopay || bill.paymentMode == .inPerson ? .green : .secondary)

                Spacer()
            }
            .padding(24)

            BillReviewDecisionBadge(title: "Paid", systemImage: "checkmark.circle.fill", tint: .green)
                .opacity(paidOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)

            BillReviewDecisionBadge(title: "Missed", systemImage: "xmark.circle.fill", tint: .red)
                .opacity(missedOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)

            BillReviewDecisionBadge(title: "Delay", systemImage: "calendar.badge.clock", tint: .blue)
                .opacity(delayOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(24)

            BillReviewDecisionBadge(title: "Cancel", systemImage: "xmark.circle.fill", tint: .red)
                .opacity(cancelOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(24)
        }
        .accessibilityElement(children: .combine)
    }

    private var paymentText: String {
        if bill.paymentMode == .inPerson {
            return "Watching transactions"
        }
        if let methodName = bill.paymentMethodName(in: paymentMethods) {
            return "\(bill.paymentModeTitle) from \(methodName)"
        }
        return bill.paymentMode == .autopay ? "Autopay" : bill.paymentModeTitle
    }
}

private struct BillReviewDecisionBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint, lineWidth: 2)
            }
    }
}

private struct BillReviewResultsView: View {
    let results: [BillReviewResult]
    let openPaymentURL: (URL) -> Void

    private var paidResults: [BillReviewResult] {
        results.filter { $0.decision == .paid }
    }

    private var missedResults: [BillReviewResult] {
        results.filter { $0.decision == .missed }
    }

    private var delayedResults: [BillReviewResult] {
        results.filter { $0.decision == .delayed }
    }

    private var canceledResults: [BillReviewResult] {
        results.filter { $0.decision == .canceled }
    }

    private var summaryText: String {
        [
            (paidResults.count, "paid"),
            (missedResults.count, "missed"),
            (delayedResults.count, "delayed"),
            (canceledResults.count, "canceled")
        ]
        .filter { $0.0 > 0 }
        .map { "\($0.0) \($0.1)" }
        .joined(separator: ", ")
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Complete")
                            .font(.title3.weight(.semibold))
                        Text(summaryText.isEmpty ? "No changes made" : summaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 6)
            }

            if !missedResults.isEmpty {
                Section("Needs Payment") {
                    ForEach(missedResults) { result in
                        BillReviewResultRow(result: result, openPaymentURL: openPaymentURL)
                    }
                }
            }

            if !delayedResults.isEmpty {
                Section("Delayed") {
                    ForEach(delayedResults) { result in
                        BillReviewResultRow(result: result, openPaymentURL: openPaymentURL)
                    }
                }
            }

            if !canceledResults.isEmpty {
                Section("Canceled") {
                    ForEach(canceledResults) { result in
                        BillReviewResultRow(result: result, openPaymentURL: openPaymentURL)
                    }
                }
            }

            if !paidResults.isEmpty {
                Section("Marked Paid") {
                    ForEach(paidResults) { result in
                        BillReviewResultRow(result: result, openPaymentURL: openPaymentURL)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
}

private struct BillReviewResultRow: View {
    let result: BillReviewResult
    let openPaymentURL: (URL) -> Void

    @State private var showingPaymentLinkSetup = false

    private var bill: Bill {
        result.bill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.decision.systemImage)
                    .foregroundStyle(result.decision.tint)
                    .font(.title3)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.name ?? "Untitled")
                        .font(.headline)
                    Text(result.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                MoneyMapMoneyText(amount: bill.amount ?? 0)
            }

            if result.decision == .missed {
                if let paymentURL = bill.paymentURL {
                    Button {
                        openPaymentURL(paymentURL)
                    } label: {
                        MoneyMapNeutralButtonLabel(
                            title: "Open Payment Link",
                            systemImage: "arrow.up.forward.app",
                            iconColor: MoneyMapDesign.calmGreen,
                            fillsWidth: false
                        )
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        showingPaymentLinkSetup = true
                    } label: {
                        MoneyMapNeutralButtonLabel(
                            title: "Set Up Payment Link",
                            systemImage: "link.badge.plus",
                            iconColor: MoneyMapDesign.calmGreen,
                            fillsWidth: false
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 5)
        .sheet(isPresented: $showingPaymentLinkSetup) {
            PaymentLinkSetupView(bill: bill)
        }
    }
}

private struct BillReviewResult: Identifiable {
    let id = UUID()
    let bill: Bill
    let decision: BillReviewDecision
    let amount: Double?
    let scheduledDate: Date?

    var detailText: String {
        switch decision {
        case .paid:
            if let amount {
                return "Marked paid for \(MoneyMapFormatters.currencyString(for: amount))."
            }
            return "Marked paid."
        case .missed:
            return bill.paymentHost.map { "Payment link: \($0)" } ?? "Payment link not set."
        case .delayed:
            if let scheduledDate {
                return "Delayed to \(MoneyMapFormatters.mediumDateString(for: scheduledDate))."
            }
            return "Delayed."
        case .canceled:
            return "Canceled and removed from payment review."
        }
    }
}

private enum BillReviewDecision {
    case paid
    case missed
    case delayed
    case canceled

    var systemImage: String {
        switch self {
        case .paid:
            return "checkmark.circle.fill"
        case .missed:
            return "xmark.circle.fill"
        case .delayed:
            return "calendar.badge.clock"
        case .canceled:
            return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .paid:
            return .green
        case .missed:
            return .red
        case .delayed:
            return .blue
        case .canceled:
            return .red
        }
    }
}

#Preview {
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    let bills = (try? container.mainContext.fetch(FetchDescriptor<Bill>())) ?? []

    BillReviewFlowView(bills: bills)
        .environmentObject(paydayManager)
        .modelContainer(container)
}
