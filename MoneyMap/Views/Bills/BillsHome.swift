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
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query private var bills: [Bill]
    @Query private var goals: [Goal]
    
    @State private var addingBill = false
    @State private var editingBalance = false
    @State private var editingLimit = false
    @State private var billToEdit: Bill?
    @State private var alertValue: String = ""
    @State private var makingPayment = false
    @State private var viewingBill: Bill?
    @State private var destination: BillsNavigationTarget?
    
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
                    Button(MoneyMapAction.addBill.title, systemImage: MoneyMapAction.addBill.systemImage) {
                        addingBill.toggle()
                    }
                }
            }
            .sheet(isPresented: $addingBill) {
                BillEditor()
            }
            .navigationDestination(item: $viewingBill, destination: { bill in
                BillView(bill: bill)
            })
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .upcomingBills:
                    BillsView(mode: .upcoming)
                case .cardUtilization:
                    CardUtilizationView()
                }
            }
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
                    makingPayment = false
                    alertValue.removeAll()
                }
            } message: {
                Text("How much would you like to pay off this bill?")
            }
            .onAppear {
                routeToRequestedBillIfNeeded()
                routeToRequestedDestinationIfNeeded()
                syncSystemIntegrations()
            }
            .onChange(of: deepLinkManager.requestedBillID) { _, _ in
                routeToRequestedBillIfNeeded()
            }
            .onChange(of: deepLinkManager.requestedBillsDestination) { _, _ in
                routeToRequestedDestinationIfNeeded()
            }
            .onChange(of: bills.count) { _, _ in
                routeToRequestedBillIfNeeded()
            }
            .onChange(of: billsIntegrationSignature) { _, _ in
                syncSystemIntegrations()
            }
        }
    }

    private var billsIntegrationSignature: String {
        bills
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { bill in
                let name = bill.name ?? ""
                let amount = bill.amount ?? 0
                let due = bill.dueDate?.timeIntervalSince1970 ?? 0
                let paid = bill.datePaid?.timeIntervalSince1970 ?? 0
                return "\(bill.id.uuidString)|\(name)|\(amount)|\(due)|\(paid)"
            }
            .joined(separator: ";")
    }

    private func syncSystemIntegrations() {
        refreshBillStatuses()
        SpotlightIndexer.reindexBills(bills)
        notificationManager.scheduleBillDueNotifications(for: bills)
    }

    private func refreshBillStatuses() {
        var didChange = false

        for bill in bills {
            let previousDueDate = bill.dueDate
            let previousDatePaid = bill.datePaid
            let previousStatus = bill.status

            bill.checkStatus()

            if previousDueDate != bill.dueDate ||
                previousDatePaid != bill.datePaid ||
                previousStatus != bill.status {
                didChange = true
            }
        }

        if didChange {
            try? modelContext.save()
        }
    }

    private func routeToRequestedBillIfNeeded() {
        guard let requestedBillID = deepLinkManager.requestedBillID,
              let targetBill = bills.first(where: { $0.id == requestedBillID }) else {
            return
        }
        viewingBill = targetBill
        deepLinkManager.requestedBillID = nil
    }

    private func routeToRequestedDestinationIfNeeded() {
        guard let requestedDestination = deepLinkManager.requestedBillsDestination else {
            return
        }
        destination = requestedDestination
        deepLinkManager.requestedBillsDestination = nil
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
          .environmentObject(DeepLinkManager())
          .environmentObject(NotificationManager())
          .modelContainer(container)
  }
