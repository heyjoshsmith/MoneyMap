//
//  BillSetupStatusView.swift
//  MoneyMap
//
//  Created by Codex on 7/29/26.
//

import SwiftUI
import SwiftData

enum BillSetupAction: Hashable {
    case editBill
    case paymentSettings
    case paymentLink
    case transactionLinking
    case recordPayment
    case openPaymentLink
}

enum BillSetupAnalyzer {
    static func pendingItemCount(
        for bills: [Bill],
        paymentMethods: [PaymentMethod],
        transactions: [Transaction]
    ) -> Int {
        bills.reduce(0) { count, bill in
            count + BillSetupKind.kindsNeedingSetup(
                for: bill,
                paymentMethods: paymentMethods,
                transactions: transactions
            ).count
        }
    }
}

struct BillSetupStatusView: View {
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    @Query private var transactions: [Transaction]

    private var activeBills: [Bill] {
        bills
            .filter { $0.lifecycleState == .active }
            .sorted(by: Bill.byDate)
    }

    private var setupItems: [BillSetupItem] {
        activeBills.flatMap { bill in
            BillSetupItem.items(for: bill, paymentMethods: paymentMethods, transactions: transactions)
        }
        .sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.billDueDate != rhs.billDueDate {
                return (lhs.billDueDate ?? .distantFuture) < (rhs.billDueDate ?? .distantFuture)
            }
            return lhs.billName.localizedCaseInsensitiveCompare(rhs.billName) == .orderedAscending
        }
    }

    private var readyBills: [Bill] {
        let billsWithSetupItems = Set(setupItems.map(\.billID))
        return activeBills.filter { !billsWithSetupItems.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                BillSetupSummaryRow(
                    actionCount: setupItems.count,
                    readyCount: readyBills.count,
                    billCount: activeBills.count
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            if setupItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Bills Are Ready",
                        systemImage: "checkmark.circle",
                        description: Text("Every active bill has the payment, schedule, and transaction details MoneyMap needs.")
                    )
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            } else {
                Section {
                    ForEach(setupItems) { item in
                        NavigationLink {
                            BillView(bill: item.bill, initialSetupAction: item.action)
                        } label: {
                            BillSetupItemRow(item: item)
                        }
                    }
                } header: {
                    Text("Needs Setup")
                } footer: {
                    Text("Tap a bill to open the exact place that finishes the missing setup.")
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }

            if !readyBills.isEmpty {
                Section("Ready") {
                    ForEach(readyBills) { bill in
                        NavigationLink {
                            BillView(bill: bill)
                        } label: {
                            BillSetupReadyRow(bill: bill)
                        }
                    }
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
        }
        .navigationTitle("Bill Setup")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
}

private struct BillSetupItem: Identifiable {
    let id: String
    let bill: Bill
    let kind: BillSetupKind

    var billID: UUID { bill.id }
    var billName: String { bill.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Bill" }
    var billDueDate: Date? { bill.dueDate }
    var title: String { kind.title(for: bill) }
    var detail: String { kind.detail(for: bill) }
    var systemImage: String { kind.systemImage }
    var tint: Color { kind.tint }
    var action: BillSetupAction { kind.action(for: bill) }
    var priority: Int { kind.priority }

    static func items(
        for bill: Bill,
        paymentMethods: [PaymentMethod],
        transactions: [Transaction]
    ) -> [BillSetupItem] {
        BillSetupKind.kindsNeedingSetup(
            for: bill,
            paymentMethods: paymentMethods,
            transactions: transactions
        )
        .map { kind in
            BillSetupItem(
                id: "\(bill.id.uuidString)-\(kind.rawValue)",
                bill: bill,
                kind: kind
            )
        }
    }
}

private enum BillSetupKind: String, CaseIterable {
    case missingDueDate
    case missingAmount
    case missingAutopayMethod
    case missingPaymentLink
    case invalidPaymentLink
    case missingTransactionConnection
    case manualPaymentDue
    case creditCardPaymentDue

    var systemImage: String {
        switch self {
        case .missingDueDate:
            return "calendar.badge.exclamationmark"
        case .missingAmount:
            return "dollarsign.circle"
        case .missingAutopayMethod:
            return "wallet.pass"
        case .missingPaymentLink:
            return "link.badge.plus"
        case .invalidPaymentLink:
            return "exclamationmark.link"
        case .missingTransactionConnection:
            return "list.bullet.rectangle"
        case .manualPaymentDue:
            return "checkmark.circle"
        case .creditCardPaymentDue:
            return MoneyMapAction.makePayment.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .manualPaymentDue, .creditCardPaymentDue:
            return MoneyMapDesign.attentionRed
        case .missingDueDate, .missingAmount, .missingAutopayMethod, .missingPaymentLink, .invalidPaymentLink, .missingTransactionConnection:
            return MoneyMapDesign.warningGold
        }
    }

    func action(for bill: Bill) -> BillSetupAction {
        switch self {
        case .missingDueDate, .missingAmount:
            return .editBill
        case .missingAutopayMethod:
            return .paymentSettings
        case .missingPaymentLink, .invalidPaymentLink:
            return .paymentLink
        case .missingTransactionConnection:
            return .transactionLinking
        case .manualPaymentDue, .creditCardPaymentDue:
            if bill.paymentMode == .payLink {
                return .openPaymentLink
            }
            return .recordPayment
        }
    }

    var priority: Int {
        switch self {
        case .manualPaymentDue, .creditCardPaymentDue:
            return 0
        case .missingDueDate, .missingAmount:
            return 1
        case .missingAutopayMethod, .missingPaymentLink, .invalidPaymentLink, .missingTransactionConnection:
            return 2
        }
    }

    func title(for bill: Bill) -> String {
        switch self {
        case .missingDueDate:
            return "Add a due date"
        case .missingAmount:
            return bill.category == .creditCard ? "Add card payment details" : "Add an amount"
        case .missingAutopayMethod:
            return "Choose autopay source"
        case .missingPaymentLink:
            return "Add payment link"
        case .invalidPaymentLink:
            return "Fix payment link"
        case .missingTransactionConnection:
            return "Connect transactions"
        case .manualPaymentDue:
            return bill.paymentMode == .payLink ? "Complete linked payment" : "Complete manual payment"
        case .creditCardPaymentDue:
            return "Record card payment"
        }
    }

    func detail(for bill: Bill) -> String {
        switch self {
        case .missingDueDate:
            return "MoneyMap needs a date before it can place this bill in your schedule."
        case .missingAmount:
            return bill.category == .creditCard
                ? "Add the balance, limit, or minimum payment used for recommendations."
                : "Add the expected amount for this bill."
        case .missingAutopayMethod:
            return "Autopay is on, but no account or payment source is saved."
        case .missingPaymentLink:
            return "Pay Link is selected, but no website or app link is saved."
        case .invalidPaymentLink:
            return "The saved link is not a website or app link MoneyMap can open."
        case .missingTransactionConnection:
            return "Connect at least one matching transaction so MoneyMap can recognize payment activity."
        case .manualPaymentDue:
            return dueDetail(for: bill, fallback: "This bill needs to be marked paid when payment is complete.")
        case .creditCardPaymentDue:
            return dueDetail(for: bill, fallback: "Record the payment once it has been made.")
        }
    }

    static func kindsNeedingSetup(
        for bill: Bill,
        paymentMethods: [PaymentMethod],
        transactions: [Transaction]
    ) -> [BillSetupKind] {
        guard bill.lifecycleState == .active else { return [] }

        var kinds: [BillSetupKind] = []

        if bill.dueDate == nil {
            kinds.append(.missingDueDate)
        }

        if needsAmount(bill) {
            kinds.append(.missingAmount)
        }

        if bill.paymentMode == .autopay,
           bill.paymentMethod(in: paymentMethods) == nil,
           (bill.autopaySource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kinds.append(.missingAutopayMethod)
        }

        if bill.paymentMode == .payLink {
            if let rawValue = bill.paymentURLString,
               !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               bill.paymentURL == nil {
                kinds.append(.invalidPaymentLink)
            } else if bill.paymentURL == nil {
                kinds.append(.missingPaymentLink)
            }
        }

        if bill.paymentMode == .inPerson && connectedTransactions(for: bill, in: transactions).isEmpty {
            kinds.append(.missingTransactionConnection)
        }

        if billNeedsPaymentCompletion(bill) {
            kinds.append(bill.category == .creditCard ? .creditCardPaymentDue : .manualPaymentDue)
        }

        return kinds
    }

    private static func needsAmount(_ bill: Bill) -> Bool {
        if bill.category == .creditCard {
            guard let details = bill.creditCardDetails else { return true }
            return details.creditLimit <= 0 &&
                details.cardBalance <= 0 &&
                details.effectiveMinimumPayment <= 0 &&
                (bill.amount ?? 0) <= 0
        }

        return (bill.amount ?? 0) <= 0
    }

    private static func billNeedsPaymentCompletion(_ bill: Bill) -> Bool {
        guard bill.status != .paid else { return false }
        guard bill.paymentMode != .autopay && bill.paymentMode != .inPerson else { return false }
        guard let dueDate = bill.dueDate else { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.startOfDay(for: dueDate) <= today
    }

    private static func connectedTransactions(for bill: Bill, in transactions: [Transaction]) -> [Transaction] {
        BillPaymentMatcher.connectedTransactions(for: bill, in: transactions)
    }

    private func dueDetail(for bill: Bill, fallback: String) -> String {
        guard let dueDate = bill.dueDate else { return fallback }
        let dueDay = Calendar.current.startOfDay(for: dueDate)
        let today = Calendar.current.startOfDay(for: .now)
        if dueDay < today {
            return "Overdue since \(MoneyMapFormatters.mediumDateString(for: dueDate))."
        }
        return "Due today. Finish the payment, then mark it paid."
    }
}

private struct BillSetupSummaryRow: View {
    let actionCount: Int
    let readyCount: Int
    let billCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                        .fill(summaryColor.opacity(0.14))
                    Image(systemName: summaryIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(summaryColor)
                        .accessibilityHidden(true)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summaryDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Text("\(actionCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(summaryColor)
            }

            HStack(spacing: 10) {
                BillSetupMetric(title: "Ready", value: "\(readyCount)", systemImage: "checkmark.circle.fill", color: MoneyMapDesign.calmGreen)
                BillSetupMetric(title: "Active", value: "\(billCount)", systemImage: "calendar", color: .blue)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var summaryColor: Color {
        actionCount > 0 ? MoneyMapDesign.warningGold : MoneyMapDesign.calmGreen
    }

    private var summaryIcon: String {
        actionCount > 0 ? "checklist" : "checkmark.circle.fill"
    }

    private var summaryTitle: String {
        actionCount == 0 ? "Bills are set up" : "Setup remaining"
    }

    private var summaryDetail: String {
        actionCount == 0
            ? "Active bills have the details needed for payment tracking."
            : "\(actionCount) item\(actionCount == 1 ? "" : "s") need\(actionCount == 1 ? "s" : "") attention."
    }
}

private struct BillSetupMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius, style: .continuous))
    }
}

private struct BillSetupItemRow: View {
    let item: BillSetupItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.headline)
                .foregroundStyle(item.tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(item.billName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(dueText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var dueText: String {
        item.billDueDate.map(MoneyMapFormatters.mediumDateString(for:)) ?? "No date"
    }
}

private struct BillSetupReadyRow: View {
    let bill: Bill

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: bill.category?.icon ?? "checkmark.circle")
                .foregroundStyle(bill.category?.color ?? MoneyMapDesign.calmGreen)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(bill.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Bill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MoneyMapDesign.calmGreen)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        [
            bill.paymentModeTitle,
            bill.dueDate.map(MoneyMapFormatters.mediumDateString(for:))
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    NavigationStack {
        BillSetupStatusView()
    }
    .modelContainer(Bill.preview)
}
