//
//  CardUtilizationView.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import SwiftUI
import SwiftData

struct CardUtilizationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bills: [Bill]

    @State private var billToEdit: Bill?
    @State private var alertValue = ""
    @State private var editingBalance = false
    @State private var editingLimit = false
    @State private var makingPayment = false

    private var creditCards: Bills {
        bills.creditCards
    }

    var body: some View {
        List {
            CreditCardGauge(bills: creditCards)

            CreditCardSection(
                bills: creditCards,
                billToEdit: $billToEdit,
                alertValue: $alertValue,
                editingBalance: $editingBalance,
                editingLimit: $editingLimit,
                makingPayment: $makingPayment
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Card Utilization")
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .alert(billToEdit?.name ?? "Current Balance", isPresented: $editingBalance) {
            TextField(balancePlaceholder, text: $alertValue)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { }
            Button("Done") {
                billToEdit?.creditCardDetails?.cardBalance = Double(alertValue) ?? 0
                saveContext()
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
                saveContext()
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
                }
                saveContext()
                makingPayment = false
                alertValue.removeAll()
            }
        } message: {
            Text("How much would you like to pay off this bill?")
        }
    }

    private func saveContext() {
        try? modelContext.save()
    }

    private var paymentPlaceholder: String {
        if let payment = billToEdit?.creditCardDetails?.recommendedPayment {
            return "Recommended: \(payment.currency)"
        }
        return "Enter Payment"
    }

    private var balancePlaceholder: String {
        if let balance = billToEdit?.creditCardDetails?.cardBalance {
            return balance.currency
        }
        return "Enter Balance"
    }

    private var limitPlaceholder: String {
        if let limit = billToEdit?.creditCardDetails?.creditLimit {
            return limit.currency
        }
        return "Enter Limit"
    }

    private var paymentTitle: String {
        if let billToEdit, let name = billToEdit.name {
            return name
        }
        return "Payment Amount"
    }
}

#Preview {
    NavigationStack {
        CardUtilizationView()
    }
    .modelContainer(Bill.preview)
}
