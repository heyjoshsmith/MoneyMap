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

    // Focus state to track current field
    @FocusState private var focusedField: Field?

    // Bill Details
    @State private var name = ""
    @State private var amount: Double = 0.0
    @State private var dueDate = Date()
    @State private var selectedCategory: BillCategory = .utilities

    // Recurrence Details
    @State private var recurrenceInterval: Int = 1
    @State private var selectedRecurrenceUnit: RecurrenceUnit = .month
    @State private var autopayEnabled = false
    @State private var notes = ""
    @State private var autopaySource = ""
    @State private var gracePeriodDays = 0

    // Credit Card Details
    @State private var creditLimit: Double = 0.0
    @State private var cardBalance: Double = 0.0
    @State private var statementBalance: Double = 0.0
    @State private var annualPercentageRate: Double = 0.0
    @State private var minimumPayment: Double = 0.0
    @State private var issuerName = ""
    @State private var lastFourDigits = ""
    @State private var statementClosingDate = Date()
    @State private var promoAPRExpiration = Date()
    @State private var hasStatementClosingDate = false
    @State private var hasPromoAPRExpiration = false
    @State private var showingBillDetails = false
    @State private var showingCardDetails = false

    var body: some View {
        NavigationStack {
            List {
                // Bill Details Section
                Section(header: Text("Bill Details")) {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .name)
                    }
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(BillCategory.allCases.sorted(by: <), id: \ .self) { category in
                            Label(category.name, systemImage: category.icon)
                                .tint(category.color)
                        }
                    }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    if selectedCategory != .creditCard {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("Amount", value: $amount, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amount)
                        }
                    }
                }

                Section("More Details") {
                    DisclosureGroup("Bill Details", isExpanded: $showingBillDetails) {
                        Stepper("Every \(recurrenceInterval) \(selectedRecurrenceUnit.rawValue)\(recurrenceInterval > 1 ? "s" : "")", value: $recurrenceInterval, in: 1...12)
                        Picker("Recurrence Unit", selection: $selectedRecurrenceUnit) {
                            ForEach(RecurrenceUnit.allCases, id: \ .self) { unit in
                                Text(unit.rawValue.capitalized)
                            }
                        }
                        Toggle("Autopay", isOn: $autopayEnabled)
                        if autopayEnabled {
                            HStack {
                                Text("Autopay Source")
                                Spacer()
                                TextField("Checking Account", text: $autopaySource)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        Stepper("Grace Period: \(gracePeriodDays) day\(gracePeriodDays == 1 ? "" : "s")", value: $gracePeriodDays, in: 0...31)
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)

                        TipView(AutopayBillTip())
                    }
                }

                // Credit Card Details Section (only if category is creditCard)
                if selectedCategory == .creditCard {
                    Section(header: Text("Credit Card Details")) {
                        HStack {
                            Text("Credit Limit")
                            Spacer()
                            TextField("Credit Limit", value: $creditLimit, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .creditLimit)
                        }
                        HStack {
                            Text("Card Balance")
                            Spacer()
                            TextField("Card Balance", value: $cardBalance, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .cardBalance)
                        }
                        HStack {
                            Text("Minimum Payment")
                            Spacer()
                            TextField("Minimum Payment", value: $minimumPayment, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .minimumPayment)
                        }

                        DisclosureGroup("Advanced Card Details", isExpanded: $showingCardDetails) {
                            HStack {
                                Text("Statement Balance")
                                Spacer()
                                TextField("Statement Balance", value: $statementBalance, format: .currency(code: "USD"))
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .statementBalance)
                            }
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
                            Toggle("Track Statement Closing Date", isOn: $hasStatementClosingDate)
                            if hasStatementClosingDate {
                                DatePicker("Closing Date", selection: $statementClosingDate, displayedComponents: .date)
                            }
                            Toggle("Track Promo APR Expiration", isOn: $hasPromoAPRExpiration)
                            if hasPromoAPRExpiration {
                                DatePicker("Promo APR Ends", selection: $promoAPRExpiration, displayedComponents: .date)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Bill")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveBill()
                    }
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
        }
    }

    // Function to move focus between text fields
    private func moveFocus(direction: Int) {
        // Determine the order of fields based on whether credit card fields are visible
        var fields: [Field] = [.name, .amount]
        if selectedCategory == .creditCard {
            fields.append(contentsOf: [.creditLimit, .cardBalance, .statementBalance, .annualPercentageRate, .minimumPayment, .issuerName, .lastFourDigits])
        }

        guard let current = focusedField, let currentIndex = fields.firstIndex(of: current) else {
            // If no field is focused, set focus to the first field
            focusedField = fields.first
            return
        }

        let newIndex = currentIndex + direction
        if newIndex >= 0 && newIndex < fields.count {
            focusedField = fields[newIndex]
        }
    }

    private func saveBill() {
        let billAmount = amount

        var newBill: Bill

        if selectedCategory == .creditCard {
            let creditDetails = CreditCardDetails(
                creditLimit: creditLimit,
                cardBalance: cardBalance,
                annualPercentageRate: annualPercentageRate > 0 ? annualPercentageRate : nil,
                minimumPayment: minimumPayment > 0 ? minimumPayment : nil,
                statementBalance: statementBalance > 0 ? statementBalance : nil,
                issuerName: issuerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : issuerName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastFourDigits: lastFourDigits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lastFourDigits.trimmingCharacters(in: .whitespacesAndNewlines),
                statementClosingDate: hasStatementClosingDate ? statementClosingDate : nil,
                promoAPRExpiration: hasPromoAPRExpiration ? promoAPRExpiration : nil
            )
            newBill = Bill(name: name, amount: billAmount, dueDate: dueDate, category: .creditCard, recurrenceInterval: recurrenceInterval, recurrenceUnit: selectedRecurrenceUnit, creditCardDetails: creditDetails, autopayEnabled: autopayEnabled, notes: normalizedNotes, autopaySource: normalizedAutopaySource, gracePeriodDays: gracePeriodDays > 0 ? gracePeriodDays : nil)
        } else {
            newBill = Bill(name: name, amount: billAmount, dueDate: dueDate, category: selectedCategory, recurrenceInterval: recurrenceInterval, recurrenceUnit: selectedRecurrenceUnit, autopayEnabled: autopayEnabled, notes: normalizedNotes, autopaySource: normalizedAutopaySource, gracePeriodDays: gracePeriodDays > 0 ? gracePeriodDays : nil)
        }

        modelContext.insert(newBill)
        AuditService.logBillCreated(newBill, context: modelContext)
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
        dismiss()
    }

    private var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedAutopaySource: String? {
        let trimmed = autopaySource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// Define focusable fields for keyboard navigation
private enum Field: Hashable {
    case name
    case amount
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
        .modelContainer(for: [Bill.self, Transaction.self, AuditEvent.self], inMemory: true)
}
