//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData

struct BillsView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var bills: [Bill]
    
    @State private var addingBill = false
    @State private var editingBalance = false
    @State private var billToEdit: Bill?
    @State private var alertValue: String = ""
    @State private var makingPayment = false
    
    var body: some View {
        NavigationStack {
            List {
                
                Section("Credit Card Details") {
                    HStack {
                        Text("Total Balance")
                        Spacer()
                        Text(bills.totalBalance, format: .currency(code: "USD"))
                    }
                    HStack {
                        Text("Total Limit")
                        Spacer()
                        Text(bills.totalCreditLimit, format: .currency(code: "USD"))
                    }
                    HStack {
                        Text("Total Utilization")
                        Spacer()
                        Image(systemName: bills.creditCardUtilization < 0.3 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(bills.creditCardUtilization < 0.3 ? .green : .yellow)
                        Text(bills.creditCardUtilization, format: .percent.precision(.fractionLength(0)))
                    }
                    if bills.creditCardUtilization >= 0.3 {
                        HStack {
                            Text("Amount Over Utilization")
                            Spacer()
                            Text((bills.totalBalance - bills.totalCreditLimit * 0.3), format: .currency(code: "USD"))
                        }
                    }
                }
                
                Section("Credit Cards") {
                    ForEach(bills.creditCards.sorted(by: Bill.byDate)) { card in
                        CreditCardRow(for: card)
                        .contextMenu {
                            Button("Balance", systemImage: "dollarsign.gauge.chart.lefthalf.righthalf") {
                                billToEdit = card
                                alertValue = String(billToEdit?.creditCardDetails?.cardBalance ?? 0.0)
                                editingBalance = true
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Make Payment", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90") {
                                billToEdit = card
                                alertValue = ""
                                makingPayment = true
                            }.tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash") {
                                modelContext.delete(card)
                            }.tint(.red)
                        }
                    }
                }
                
                Section("Bills") {
                    ForEach(bills.withoutCreditCards) { bill in
                        NavigationLink(bill.name) {
                            BillView(bill: bill)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash") {
                                modelContext.delete(bill)
                            }.tint(.red)
                        }
                    }
                }
            }
            .navigationTitle("Bills")
            .listStyle(.plain)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Add Bill", systemImage: "plus") {
                        addingBill.toggle()
                    }
                }
            }
            .sheet(isPresented: $addingBill) {
                BillEditor()
            }
            .alert(billToEdit?.name ?? "Current Balance", isPresented: $editingBalance) {
                TextField("Enter Balance", text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    billToEdit?.creditCardDetails?.cardBalance = Double(alertValue) ?? 0
                    editingBalance = false
                }
            } message: {
                Text("What is your current balance?")
            }
            .alert(billToEdit?.name ?? "Payment Amount", isPresented: $makingPayment) {
                TextField("Enter Payment", text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    billToEdit?.makePayment(of: Double(alertValue) ?? 0)
                    makingPayment = false
                }
            } message: {
                Text("How much would you like to pay off this bill?")
            }
        }
    }
    
    
}

#Preview {
    BillsView()
        .modelContainer(for: Bill.self)
}
