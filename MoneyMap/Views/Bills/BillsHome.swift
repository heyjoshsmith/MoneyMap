//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import SwiftData

struct BillsHome: View {
    
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
                
                Section {
                    
                    Gauge(value: bills.totalBalance, in: 0...(bills.totalCreditLimit)) {
                        VStack {
                            HStack {
                                Text("Credit Cards")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text(bills.creditCardUtilization, format: .percent.precision(.fractionLength(0)))
                                    .fontDesign(.rounded)
                                    .font(.title3.weight(.bold))
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text(bills.totalBalance, format: .currency(code: "USD").precision(.fractionLength(0)))
                                Spacer()
                                Text(bills.totalCreditLimit, format: .currency(code: "USD").precision(.fractionLength(0)))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .tint(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    
                    if bills.creditCardUtilization >= 0.3 {
                        HStack {
                            Text("Amount Over Utilization")
                            Spacer()
                            Text((bills.totalBalance - bills.totalCreditLimit * 0.3), format: .currency(code: "USD"))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                
                Section {
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
                
                BillRow(bills: bills.withoutCreditCards.sorted(by: Bill.byDate))
                
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
    BillsHome()
        .modelContainer(Bill.preview)
}
