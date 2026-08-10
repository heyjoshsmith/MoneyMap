//
//  BillLifecycleControls.swift
//  MoneyMap
//
//  Created by Codex on 7/1/26.
//

import SwiftUI

struct BillLifecycleCard: View {
    let bill: Bill
    let delay: (Date) -> Void
    let skip: () -> Void
    let pause: () -> Void
    let cancel: () -> Void
    let resume: () -> Void

    @State private var showingCustomDelay = false
    @State private var customDelayDate = Calendar.current.startOfDay(for: .now)
    @State private var pendingConfirmation: BillLifecycleConfirmation?

    private var state: BillLifecycleState {
        bill.lifecycleState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state.icon)
                    .foregroundStyle(state.color)
                    .font(.title3)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Schedule")
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }

            LazyVGrid(columns: actionGridColumns, alignment: .leading, spacing: 8) {
                ForEach(actions) { action in
                    if action.kind == .delay {
                        delayMenu
                    } else {
                        BillLifecycleActionButton(action: action)
                    }
                }
            }

            if showingCustomDelay {
                customDelayPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let pendingConfirmation {
                confirmationPanel(for: pendingConfirmation)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: showingCustomDelay)
        .animation(.snappy(duration: 0.22), value: pendingConfirmation?.id)
        .onAppear {
            customDelayDate = defaultCustomDelayDate
        }
        .onChange(of: bill.dueDate) { _, _ in
            customDelayDate = defaultCustomDelayDate
        }
        .padding()
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
    }

    private var delayMenu: some View {
        Menu {
            ForEach(delayOptions, id: \.title) { option in
                Button(option.title, systemImage: option.systemImage) {
                    showingCustomDelay = false
                    pendingConfirmation = nil
                    delay(Calendar.current.startOfDay(for: option.date))
                }
            }

            Divider()

            Button("Custom", systemImage: "calendar") {
                customDelayDate = defaultCustomDelayDate
                showingCustomDelay = true
                pendingConfirmation = nil
            }
        } label: {
            BillLifecycleActionLabel(
                title: "Delay",
                detail: "Choose when",
                systemImage: "calendar.badge.clock",
                tint: .blue,
                role: nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var customDelayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            DatePicker("Custom Date", selection: $customDelayDate, displayedComponents: .date)
                .datePickerStyle(.graphical)

            HStack {
                Button("Cancel") {
                    showingCustomDelay = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    delay(Calendar.current.startOfDay(for: customDelayDate))
                    showingCustomDelay = false
                    pendingConfirmation = nil
                } label: {
                    Text("Save")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 2)
    }

    private var delayOptions: [(title: String, systemImage: String, date: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var options: [(String, String, Date)] = [
            ("Tomorrow", "sunrise", calendar.date(byAdding: .day, value: 1, to: today) ?? today),
            ("Next Week", "calendar.badge.plus", calendar.date(byAdding: .day, value: 7, to: today) ?? today),
            ("Next Month", "calendar", calendar.date(byAdding: .month, value: 1, to: today) ?? today)
        ]

        if let nextCycle = bill.nextOccurrenceDate(calendar: calendar) {
            options.append(("Next Cycle", "forward.end", nextCycle))
        }

        return options
    }

    private var defaultCustomDelayDate: Date {
        let calendar = Calendar.current
        return bill.nextOccurrenceDate(calendar: calendar) ??
            calendar.date(byAdding: .day, value: 7, to: bill.dueDate ?? .now) ??
            .now
    }

    private var actionGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 126), spacing: 8, alignment: .top)
        ]
    }

    private var statusText: String {
        switch state {
        case .active:
            return bill.isSubscriptionLike ? "Active subscription or recurring bill" : "Active bill"
        case .paused:
            return "Paused until you resume it"
        case .canceled:
            return "Canceled and kept for your records"
        }
    }

    private var actions: [BillLifecycleAction] {
        switch state {
        case .active:
            return [
                BillLifecycleAction(
                    title: "Delay",
                    detail: "Pick a date",
                    systemImage: "calendar.badge.clock",
                    tint: .blue,
                    kind: .delay,
                    handler: {}
                ),
                BillLifecycleAction(
                    title: "Skip",
                    detail: "Next cycle",
                    systemImage: "forward.end.fill",
                    tint: .orange,
                    handler: { showConfirmation(.skip) }
                ),
                BillLifecycleAction(
                    title: "Pause",
                    detail: "Hold it",
                    systemImage: "pause.circle",
                    tint: .orange,
                    handler: { showConfirmation(.pause) }
                ),
                BillLifecycleAction(
                    title: "Cancel",
                    detail: "Keep history",
                    systemImage: "xmark.circle",
                    tint: .red,
                    role: .destructive,
                    handler: { showConfirmation(.cancel) }
                )
            ]

        case .paused:
            return [
                BillLifecycleAction(
                    title: "Resume",
                    detail: "Choose date",
                    systemImage: "play.circle",
                    tint: .green,
                    style: .prominent,
                    handler: resume
                ),
                BillLifecycleAction(
                    title: "Cancel",
                    detail: "Keep history",
                    systemImage: "xmark.circle",
                    tint: .red,
                    role: .destructive,
                    handler: { showConfirmation(.cancel) }
                )
            ]

        case .canceled:
            return [
                BillLifecycleAction(
                    title: "Resume",
                    detail: "Choose date",
                    systemImage: "play.circle",
                    tint: .green,
                    style: .prominent,
                    handler: resume
                )
            ]
        }
    }

    private func showConfirmation(_ confirmation: BillLifecycleConfirmation) {
        showingCustomDelay = false
        pendingConfirmation = confirmation
    }

    private func perform(_ confirmation: BillLifecycleConfirmation) {
        pendingConfirmation = nil

        switch confirmation {
        case .skip:
            skip()
        case .pause:
            pause()
        case .cancel:
            cancel()
        }
    }

    @ViewBuilder
    private func confirmationPanel(for confirmation: BillLifecycleConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: confirmation.systemImage)
                    .font(.headline)
                    .foregroundStyle(confirmation.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmation.title(for: billDisplayName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(confirmation.message(for: bill, billName: billDisplayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    pendingConfirmation = nil
                } label: {
                    Text(confirmation.cancelTitle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 8)

                Button(role: confirmation.role) {
                    perform(confirmation)
                } label: {
                    Text(confirmation.confirmTitle)
                        .foregroundStyle(confirmation.role == .destructive ? MoneyMapDesign.attentionRed : .primary)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 2)
    }

    private var billDisplayName: String {
        bill.name ?? "this bill"
    }
}

private enum BillLifecycleConfirmation: String, Identifiable {
    case skip
    case pause
    case cancel

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .skip:
            return "forward.end.fill"
        case .pause:
            return "pause.circle"
        case .cancel:
            return "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .skip, .pause:
            return .orange
        case .cancel:
            return .red
        }
    }

    var confirmTitle: String {
        switch self {
        case .skip:
            return "Skip Next Cycle"
        case .pause:
            return "Pause Bill"
        case .cancel:
            return "Cancel Subscription"
        }
    }

    var cancelTitle: String {
        switch self {
        case .skip:
            return "Keep Current Date"
        case .pause, .cancel:
            return "Keep Active"
        }
    }

    var role: ButtonRole? {
        self == .cancel ? .destructive : nil
    }

    func title(for billName: String) -> String {
        switch self {
        case .skip:
            return "Skip the next cycle for \(billName)?"
        case .pause:
            return "Pause \(billName)?"
        case .cancel:
            return "Cancel \(billName)?"
        }
    }

    func message(for bill: Bill, billName: String) -> String {
        switch self {
        case .skip:
            if let nextDate = bill.nextOccurrenceDate(calendar: .current) {
                return "\(billName) will move to \(MoneyMapFormatters.mediumDateString(for: nextDate))."
            }
            return "\(billName) will move to the next scheduled occurrence."
        case .pause:
            return "\(billName) stays in your history and leaves upcoming review until you resume it."
        case .cancel:
            return "\(billName) stays in your history and leaves upcoming payment review."
        }
    }
}

private struct BillLifecycleAction: Identifiable {
    enum Style: Equatable {
        case prominent
        case secondary
    }

    enum Kind: Equatable {
        case button
        case delay
    }

    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    var style: Style = .secondary
    var role: ButtonRole?
    var kind: Kind = .button
    let handler: () -> Void

    var id: String {
        "\(title)-\(systemImage)"
    }
}

private struct BillLifecycleActionButton: View {
    let action: BillLifecycleAction

    var body: some View {
        Button(role: action.role) {
            action.handler()
        } label: {
            BillLifecycleActionLabel(
                title: action.title,
                detail: action.detail,
                systemImage: action.systemImage,
                tint: action.tint,
                role: action.role
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct BillLifecycleActionLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let role: ButtonRole?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MoneyMapDesign.controlBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                .stroke(MoneyMapDesign.separator.opacity(0.24), lineWidth: 0.5)
        }
    }
}

struct BillDateActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let bill: Bill
    let confirmTitle: String
    let onConfirm: (Date) -> Void

    @State private var selectedDate: Date

    init(
        title: String,
        bill: Bill,
        defaultDate: Date,
        confirmTitle: String,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.title = title
        self.bill = bill
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        _selectedDate = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("New Date", selection: $selectedDate, displayedComponents: .date)

                    quickDateButtons
                } header: {
                    Text("Date")
                } footer: {
                    Text("This changes the next due date without deleting the bill.")
                }
                .moneyMapListSectionBackground()
            }
            .moneyMapGroupedListBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(confirmTitle) {
                        onConfirm(Calendar.current.startOfDay(for: selectedDate))
                        dismiss()
                    }
                }
            }
        }
    }

    private var quickDateOptions: [(title: String, date: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var options: [(String, Date)] = [
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today) ?? today),
            ("Next Week", calendar.date(byAdding: .day, value: 7, to: today) ?? today),
            ("Next Month", calendar.date(byAdding: .month, value: 1, to: today) ?? today)
        ]

        if let nextCycle = bill.nextOccurrenceDate(calendar: calendar) {
            options.append(("Next Cycle", nextCycle))
        }

        return options
    }

    private var quickDateButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                quickDateButtonGroup
            }

            VStack(alignment: .leading) {
                quickDateButtonGroup
            }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var quickDateButtonGroup: some View {
        ForEach(quickDateOptions, id: \.title) { option in
            Button(option.title) {
                selectedDate = option.date
            }
        }
    }
}

struct BillPaymentDateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let bill: Bill
    let onSave: (Date) -> Void

    @State private var selectedDate: Date

    init(bill: Bill, defaultDate: Date, onSave: @escaping (Date) -> Void) {
        self.bill = bill
        self.onSave = onSave
        _selectedDate = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Payment Date", selection: $selectedDate, displayedComponents: .date)
                } footer: {
                    Text("This changes when the bill was marked paid. It does not change the bill amount.")
                }
                .moneyMapListSectionBackground()
            }
            .moneyMapGroupedListBackground()
            .navigationTitle(bill.name ?? "Payment Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(Calendar.current.startOfDay(for: selectedDate))
                        dismiss()
                    }
                }
            }
        }
    }
}
