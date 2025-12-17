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
    @State private var editingLimit = false
    @State private var billToEdit: Bill?
    @State private var alertValue: String = ""
    @State private var makingPayment = false
    @State private var viewingBill: Bill?
    
    var body: some View {
        NavigationStack {
            List {
                
                CreditCardGauge(bills: bills)
                
                CreditCardSection(
                    bills: bills,
                    billToEdit: $billToEdit,
                    alertValue: $alertValue,
                    editingBalance: $editingBalance, editingLimit: $editingLimit,
                    makingPayment: $makingPayment
                )
                
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
            .navigationDestination(item: $viewingBill, destination: { bill in
                
            })
            .alert(billToEdit?.name ?? "Current Balance", isPresented: $editingBalance) {
                TextField(balancePlaceholder, text: $alertValue)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { }
                Button("Done") {
                    billToEdit?.creditCardDetails?.cardBalance = Double(alertValue) ?? 0
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
                    billToEdit?.makePayment(of: Double(alertValue) ?? 0)
                    makingPayment = false
                    alertValue.removeAll()
                }
            } message: {
                Text("How much would you like to pay off this bill?")
            }
        }
    }
    
    var paymentPlaceholder: String {
        if let payment = billToEdit?.creditCardDetails?.recommendedPayment {
            return "Recommended: \(payment.currency)"
        } else {
            return "Enter Payment"
        }
    }
    
    var balancePlaceholder: String {
        if let balance = billToEdit?.creditCardDetails?.cardBalance {
            return balance.currency
        } else {
            return "Enter Balance"
        }
    }
    
    var limitPlaceholder: String {
        if let balance = billToEdit?.creditCardDetails?.creditLimit {
            return balance.currency
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



#Preview {
      let (container, paydayManager) = PreviewDataProvider.createContainer()
      BillsHome()
          .environmentObject(paydayManager)
          .modelContainer(container)
  }
