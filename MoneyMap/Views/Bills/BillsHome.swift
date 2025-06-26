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
    @Query private var goals: [Goal]
    
    @State private var addingBill = false
    @State private var editingBalance = false
    @State private var billToEdit: Bill?
    @State private var alertValue: String = ""
    @State private var makingPayment = false
    
    var body: some View {
        NavigationStack {
            List {
                
                CreditCardGauge(bills: bills)
                
                Section {
                    ForEach(bills.creditCards.sorted(by: Bill.byStatusDateUtilization)) { card in
                        // Use closure to allow local @State
                        CardRowWithDelete(card: card, modelContext: modelContext, billToEdit: $billToEdit, alertValue: $alertValue, editingBalance: $editingBalance, makingPayment: $makingPayment)
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
                TextField(balancePlaceholder, text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    billToEdit?.creditCardDetails?.cardBalance = Double(alertValue) ?? 0
                    editingBalance = false
                }
            } message: {
                Text("What is your current balance?")
            }
            .alert(paymentTitle, isPresented: $makingPayment) {
                TextField(paymentPlaceholder, text: $alertValue)
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
    
    var paymentPlaceholder: String {
        if let payment = billToEdit?.creditCardDetails?.recommendedPayment {
            return "Recommended: $\(payment)"
        } else {
            return "Enter Payment"
        }
    }
    
    var balancePlaceholder: String {
        if let balance = billToEdit?.creditCardDetails?.cardBalance {
            return "Current: $\(balance)"
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

private struct CardRowWithDelete: View {
    let card: Bill
    let modelContext: ModelContext
    
    @Binding var billToEdit: Bill?
    @Binding var alertValue: String
    @Binding var editingBalance: Bool
    @Binding var makingPayment: Bool
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        CreditCardRow(for: card)
            .swipeActions(edge: .leading) {
                Button("Pay", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90") {
                    billToEdit = card
                    alertValue = ""
                    makingPayment = true
                }.tint(.green)
                Button("Balance", systemImage: "dollarsign.gauge.chart.lefthalf.righthalf") {
                    billToEdit = card
                    editingBalance = true
                }.tint(.blue)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash") {
                    showingDeleteConfirmation = true
                }.tint(.red)
            }
            .confirmationDialog("Are you sure you want to delete this bill?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(card)
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

#Preview {
      let (container, paydayManager) = PreviewDataProvider.createContainer()
      BillsHome()
          .environmentObject(paydayManager)
          .modelContainer(container)
  }
