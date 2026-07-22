//
//  BillEditor.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData
import TipKit

struct BillEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]

    let bill: Bill?

    @FocusState private var focusedField: Field?

    @State private var name: String
    @State private var amount: Double
    @State private var dueDate: Date
    @State private var selectedCategory: BillCategory

    @State private var repeats: Bool
    @State private var recurrenceInterval: Int
    @State private var selectedRecurrenceUnit: RecurrenceUnit
    @State private var selectedLifecycleState: BillLifecycleState

    @State private var autopayEnabled: Bool
    @State private var autopaySource: String
    @State private var selectedPaymentMethodID: UUID?
    @State private var showingPaymentMethodEditor = false
    @State private var gracePeriodDays: Int
    @State private var paymentLink: String
    @State private var notes: String

    @State private var hasPaidDate: Bool
    @State private var paidDate: Date

    @State private var creditLimit: Double
    @State private var cardBalance: Double
    @State private var statementBalance: Double
    @State private var annualPercentageRate: Double
    @State private var minimumPayment: Double
    @State private var issuerName: String
    @State private var lastFourDigits: String
    @State private var statementClosingDate: Date
    @State private var promoAPRExpiration: Date
    @State private var hasStatementClosingDate: Bool
    @State private var hasPromoAPRExpiration: Bool

    init(bill: Bill? = nil) {
        self.bill = bill

        let details = bill?.creditCardDetails
        _name = State(initialValue: bill?.name ?? "")
        _amount = State(initialValue: bill?.amount ?? details?.minimumPayment ?? 0)
        _dueDate = State(initialValue: bill?.dueDate ?? .now)
        _selectedCategory = State(initialValue: bill?.category ?? .utilities)

        _repeats = State(initialValue: bill?.recurrenceInterval != nil || bill == nil)
        _recurrenceInterval = State(initialValue: bill?.recurrenceInterval ?? 1)
        _selectedRecurrenceUnit = State(initialValue: bill?.recurrenceUnit ?? .month)
        _selectedLifecycleState = State(initialValue: bill?.lifecycleState ?? .active)

        _autopayEnabled = State(initialValue: bill?.autopayEnabled ?? false)
        _autopaySource = State(initialValue: bill?.autopaySource ?? "")
        _selectedPaymentMethodID = State(initialValue: bill?.paymentMethodID)
        _gracePeriodDays = State(initialValue: bill?.gracePeriodDays ?? 0)
        _paymentLink = State(initialValue: bill?.paymentURLString ?? "")
        _notes = State(initialValue: bill?.notes ?? "")

        _hasPaidDate = State(initialValue: bill?.datePaid != nil)
        _paidDate = State(initialValue: bill?.datePaid ?? .now)

        _creditLimit = State(initialValue: details?.creditLimit ?? 0)
        _cardBalance = State(initialValue: details?.cardBalance ?? 0)
        _statementBalance = State(initialValue: details?.statementBalance ?? 0)
        _annualPercentageRate = State(initialValue: details?.annualPercentageRate ?? 0)
        _minimumPayment = State(initialValue: details?.minimumPayment ?? 0)
        _issuerName = State(initialValue: details?.issuerName ?? "")
        _lastFourDigits = State(initialValue: details?.lastFourDigits ?? "")
        _statementClosingDate = State(initialValue: details?.statementClosingDate ?? .now)
        _promoAPRExpiration = State(initialValue: details?.promoAPRExpiration ?? .now)
        _hasStatementClosingDate = State(initialValue: details?.statementClosingDate != nil)
        _hasPromoAPRExpiration = State(initialValue: details?.promoAPRExpiration != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                scheduleSection
                paymentSection
                statusSection
                detailsSection

                if selectedCategory == .creditCard {
                    creditCardSection
                }
            }
            .navigationTitle(bill == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveBill()
                    }
                    .disabled(!canSave)
                }

                ToolbarItem(placement: .keyboard) {
                    Button {
                        moveFocus(direction: -1)
                    } label: {
                        Label("Previous", systemImage: "chevron.up")
                    }
                }

                ToolbarItem(placement: .keyboard) {
                    Button {
                        moveFocus(direction: 1)
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                }

                ToolbarSpacer(.fixed)

                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onChange(of: selectedCategory) { _, category in
                if category.isSubscriptionCategory {
                    repeats = true
                }
            }
            .onChange(of: autopayEnabled) { _, isEnabled in
                if !isEnabled {
                    autopaySource = ""
                }
            }
            .sheet(isPresented: $showingPaymentMethodEditor) {
                PaymentMethodEditor { paymentMethod in
                    selectedPaymentMethodID = paymentMethod.id
                }
            }
        }
    }

    private var basicsSection: some View {
        Section {
            HStack {
                Text("Name")
                Spacer()
                TextField("Name", text: $name)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .name)
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(BillCategory.allCases.sorted(by: <), id: \.self) { category in
                    Label {
                        Text(category.name)
                    } icon: {
                        Image(systemName: category.icon)
                            .foregroundStyle(category.color)
                    }
                    .tag(category)
                }
            }

            HStack {
                Text(selectedCategory == .creditCard ? "Payment Amount" : "Amount")
                Spacer()
                TextField("Amount", value: $amount, format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
            }
        } header: {
            Text("Basics")
        }
    }

    private var scheduleSection: some View {
        Section {
            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

            Toggle("Repeats", isOn: $repeats)

            if repeats {
                Stepper(
                    "Every \(recurrenceInterval) \(selectedRecurrenceUnit.rawValue)\(recurrenceInterval == 1 ? "" : "s")",
                    value: $recurrenceInterval,
                    in: 1...24
                )

                Picker("Repeat Unit", selection: $selectedRecurrenceUnit) {
                    ForEach(RecurrenceUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue.capitalized).tag(unit)
                    }
                }
            }

            Picker("State", selection: $selectedLifecycleState) {
                ForEach(BillLifecycleState.allCases, id: \.self) { state in
                    Label(state.title, systemImage: state.icon)
                        .tag(state)
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            if selectedLifecycleState != .active {
                Text("Paused and canceled bills stay in your data, but they are removed from upcoming review until resumed.")
            }
        }
    }

    private var paymentSection: some View {
        Section {
            Toggle("Autopay", isOn: $autopayEnabled)

            Picker("Pay From", selection: $selectedPaymentMethodID) {
                Text("No Payment Method").tag(Optional<UUID>.none)
                ForEach(sortedPaymentMethods) { method in
                    Label(method.displayName, systemImage: method.type.icon)
                        .tag(Optional(method.id))
                }
            }

            if let selectedPaymentMethod {
                PaymentMethodSummaryRow(paymentMethod: selectedPaymentMethod)
            }

            Button {
                showingPaymentMethodEditor = true
            } label: {
                Label("Add Payment Method", systemImage: "plus.circle")
            }

            if autopayEnabled && selectedPaymentMethod == nil {
                HStack {
                    Text("Autopay Source")
                    Spacer()
                    TextField("Checking Account", text: $autopaySource)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .autopaySource)
                }
            }

            Stepper(
                "Grace Period: \(gracePeriodDays) day\(gracePeriodDays == 1 ? "" : "s")",
                value: $gracePeriodDays,
                in: 0...31
            )

            PaymentLinkInputControls(linkText: $paymentLink)

            TipView(AutopayBillTip())
        } header: {
            Text("Payment")
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Marked Paid", isOn: $hasPaidDate)

            if hasPaidDate {
                DatePicker("Payment Date", selection: $paidDate, displayedComponents: .date)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Changing the payment date updates the bill's paid state without changing the bill amount or schedule.")
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Optional notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .focused($focusedField, equals: .notes)
        } header: {
            Text("Details")
        }
    }

    private var creditCardSection: some View {
        Section {
            currencyField("Credit Limit", value: $creditLimit, focus: .creditLimit)
            currencyField("Card Balance", value: $cardBalance, focus: .cardBalance)
            currencyField("Minimum Payment", value: $minimumPayment, focus: .minimumPayment)
            currencyField("Statement Balance", value: $statementBalance, focus: .statementBalance)

            HStack {
                Text("APR")
                Spacer()
                TextField("APR", value: $annualPercentageRate, format: .percent.precision(.fractionLength(2)))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .annualPercentageRate)
            }

            HStack {
                Text("Issuer")
                Spacer()
                TextField("Chase", text: $issuerName)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .issuerName)
            }

            HStack {
                Text("Last 4 Digits")
                Spacer()
                TextField("1234", text: $lastFourDigits)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .lastFourDigits)
            }

            Toggle("Statement Closing Date", isOn: $hasStatementClosingDate)
            if hasStatementClosingDate {
                DatePicker("Closing Date", selection: $statementClosingDate, displayedComponents: .date)
            }

            Toggle("Promo APR Expiration", isOn: $hasPromoAPRExpiration)
            if hasPromoAPRExpiration {
                DatePicker("Promo APR Ends", selection: $promoAPRExpiration, displayedComponents: .date)
            }
        } header: {
            Text("Card Info")
        }
    }

    private func currencyField(_ title: String, value: Binding<Double>, focus: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .currency(code: "USD"))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: focus)
        }
    }

    private var canSave: Bool {
        paymentLinkIsValid
    }

    private func moveFocus(direction: Int) {
        var fields: [Field] = [.name, .amount, .autopaySource, .notes]

        if selectedCategory == .creditCard {
            fields.append(contentsOf: [
                .creditLimit,
                .cardBalance,
                .minimumPayment,
                .statementBalance,
                .annualPercentageRate,
                .issuerName,
                .lastFourDigits
            ])
        }

        guard let current = focusedField, let currentIndex = fields.firstIndex(of: current) else {
            focusedField = fields.first
            return
        }

        let newIndex = currentIndex + direction
        if fields.indices.contains(newIndex) {
            focusedField = fields[newIndex]
        }
    }

    private func saveBill() {
        let targetBill = bill ?? Bill(
            name: nil,
            amount: nil,
            dueDate: nil,
            category: nil,
            recurrenceInterval: nil,
            recurrenceUnit: nil
        )

        applyFormValues(to: targetBill)

        if bill == nil {
            modelContext.insert(targetBill)
            AuditService.logBillCreated(targetBill, context: modelContext)
        }

        do {
            try modelContext.save()
            AppRefreshEvents.notifyBillsDidChange()
            dismiss()
        } catch {
            // The Save button is disabled for known validation issues. Keep the sheet open for unexpected save failures.
        }
    }

    private func applyFormValues(to targetBill: Bill) {
        targetBill.name = normalizedName
        targetBill.amount = amount
        targetBill.dueDate = Calendar.current.startOfDay(for: dueDate)
        targetBill.category = selectedCategory
        targetBill.recurrenceInterval = repeats ? recurrenceInterval : nil
        targetBill.recurrenceUnit = repeats ? selectedRecurrenceUnit : nil
        targetBill.updatePaymentSettings(
            autopayEnabled: autopayEnabled,
            paymentMethodID: selectedPaymentMethodID,
            autopaySource: normalizedAutopaySource,
            gracePeriodDays: gracePeriodDays
        )
        targetBill.paymentURLString = normalizedPaymentLink
        targetBill.notes = normalizedNotes
        targetBill.lifecycleState = selectedLifecycleState

        if selectedCategory == .creditCard {
            targetBill.creditCardDetails = creditCardDetails
        } else {
            targetBill.creditCardDetails = nil
        }

        if hasPaidDate {
            targetBill.datePaid = Calendar.current.startOfDay(for: paidDate)
            targetBill.status = .paid
        } else if selectedLifecycleState == .active {
            targetBill.datePaid = nil
            targetBill.checkStatus()
        } else {
            targetBill.datePaid = nil
        }

        if selectedLifecycleState != .active {
            targetBill.status = .paid
        }
    }

    private var creditCardDetails: CreditCardDetails {
        CreditCardDetails(
            creditLimit: creditLimit,
            cardBalance: cardBalance,
            annualPercentageRate: annualPercentageRate > 0 ? annualPercentageRate : nil,
            minimumPayment: minimumPayment > 0 ? minimumPayment : nil,
            statementBalance: statementBalance > 0 ? statementBalance : nil,
            issuerName: normalizedIssuerName,
            lastFourDigits: normalizedLastFourDigits,
            statementClosingDate: hasStatementClosingDate ? statementClosingDate : nil,
            promoAPRExpiration: hasPromoAPRExpiration ? promoAPRExpiration : nil
        )
    }

    private var normalizedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedAutopaySource: String? {
        if autopayEnabled, let selectedPaymentMethod {
            return selectedPaymentMethod.displayName
        }

        let trimmed = autopaySource.trimmingCharacters(in: .whitespacesAndNewlines)
        return autopayEnabled && !trimmed.isEmpty ? trimmed : nil
    }

    private var sortedPaymentMethods: [PaymentMethod] {
        paymentMethods.sorted {
            if $0.type == $1.type {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.type.name < $1.type.name
        }
    }

    private var selectedPaymentMethod: PaymentMethod? {
        guard let selectedPaymentMethodID else { return nil }
        return paymentMethods.first { $0.id == selectedPaymentMethodID }
    }

    private var normalizedPaymentLink: String? {
        let trimmed = paymentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Bill.normalizedPaymentURLString(from: paymentLink)
    }

    private var normalizedIssuerName: String? {
        let trimmed = issuerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedLastFourDigits: String? {
        let trimmed = lastFourDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var paymentLinkIsValid: Bool {
        let trimmed = paymentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Bill.paymentURL(from: paymentLink) != nil
    }
}

private struct PaymentMethodSummaryRow: View {
    let paymentMethod: PaymentMethod

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: paymentMethod.type.icon)
                .foregroundStyle(paymentMethod.type.color)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(paymentMethod.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(paymentMethod.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private enum Field: Hashable {
    case name
    case amount
    case autopaySource
    case notes
    case creditLimit
    case cardBalance
    case statementBalance
    case annualPercentageRate
    case minimumPayment
    case issuerName
    case lastFourDigits
}

#Preview {
    BillEditor()
        .modelContainer(for: [Bill.self, Transaction.self, AuditEvent.self, PaymentMethod.self], inMemory: true)
}
