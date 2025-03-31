//
//  BillEditor.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData

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

    // Credit Card Details
    @State private var creditLimit: Double = 0.0
    @State private var cardBalance: Double = 0.0

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
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amount)
                    }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }

                // Category Section
                Section(header: Text("Category")) {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(BillCategory.allCases.sorted(by: <), id: \ .self) { category in
                            Label(category.name, systemImage: category.icon)
                                .tint(category.color)
                        }
                    }
                }

                // Recurrence Section
                Section(header: Text("Recurrence")) {
                    Stepper("Every \(recurrenceInterval) \(selectedRecurrenceUnit.rawValue)\(recurrenceInterval > 1 ? "s" : "")", value: $recurrenceInterval, in: 1...12)
                    Picker("Recurrence Unit", selection: $selectedRecurrenceUnit) {
                        ForEach(RecurrenceUnit.allCases, id: \ .self) { unit in
                            Text(unit.rawValue.capitalized)
                        }
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
                    }
                }
            }
            .navigationTitle("Bill Editor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveBill()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        moveFocus(direction: -1)
                    } label: {
                        Label("Previous", systemImage: "chevron.up")
                    }
                    Spacer()
                    Button {
                        moveFocus(direction: 1)
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                    Spacer()
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
            fields.append(contentsOf: [.creditLimit, .cardBalance])
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
            let creditDetails = CreditCardDetails(creditLimit: creditLimit, cardBalance: cardBalance)
            newBill = Bill(name: name, amount: billAmount, dueDate: dueDate, category: .creditCard, recurrenceInterval: recurrenceInterval, recurrenceUnit: selectedRecurrenceUnit, creditCardDetails: creditDetails)
        } else {
            newBill = Bill(name: name, amount: billAmount, dueDate: dueDate, category: selectedCategory, recurrenceInterval: recurrenceInterval, recurrenceUnit: selectedRecurrenceUnit)
        }

        modelContext.insert(newBill)
        dismiss()
    }
}

// Define focusable fields for keyboard navigation
private enum Field: Hashable {
    case name
    case amount
    case creditLimit
    case cardBalance
}

#Preview {
    BillEditor()
        .modelContainer(for: Bill.self)
}
