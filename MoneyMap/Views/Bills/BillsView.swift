//
//  BillsView.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import SwiftUI
import SwiftData
import AppIntents

struct BillsView: View {
    enum Mode {
        case all
        case upcoming
    }

    @Query private var bills: Bills
    let mode: Mode

    init(mode: Mode = .all) {
        self.mode = mode
    }

    private var visibleTimeframes: [Timeframe] {
        switch mode {
        case .all:
            return Timeframe.allCases
        case .upcoming:
            return [.overdue, .today, .tomorrow, .thisWeek, .thisMonth]
        }
    }

    private var title: String {
        switch mode {
        case .all:
            return "Bills"
        case .upcoming:
            return "Upcoming Bills"
        }
    }

    var body: some View {
        List {
            ForEach(visibleTimeframes) { timeframe in
                
                let billsForTimeframe = bills.due(timeframe)
                
                if !billsForTimeframe.isEmpty {
                    Section {
                        ForEach(billsForTimeframe) { bill in
                            Row(for: bill)
                        }
                    } header: {
                        HStack {
                            Text(timeframe.name)
                            Spacer()
                            Text(billsForTimeframe.totalAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
}

fileprivate struct Row: View {
    
    init(for bill: Bill) {
        self.bill = bill
    }
    
    @Environment(\.modelContext) private var modelContext
    
    var bill: Bill
    
    @State private var deletingBill = false
    @State private var makingPayment = false
    @State private var paymentAmount = ""
    @State private var showMarkPaidConfirmation = false
    
    var body: some View {
        NavigationLink {
            BillView(bill: bill)
        } label: {
            HStack(spacing: 10) {
                
                Image(systemName: bill.category?.icon ?? "questionmark.circle")
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background((bill.category?.color.gradient) ?? Color.gray.gradient)
                    .clipShape(.rect(cornerRadius: 5))
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(bill.name ?? "Untitled")
                        .font(.title3.weight(.semibold))
                    Text(bill.status?.name ?? "N/A")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text((bill.amount ?? 0), format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .padding(.leading)
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            MoneyMapIntentDonations.donateOpenBill(bill)
        })
        .userActivity("com.heyjoshsmith.MoneyMap.viewingBillRow") { activity in
            let entity = BillEntity(bill)
            activity.title = "Reviewing \(entity.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 5)
        .task {
            bill.checkStatus()
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash") {
                deletingBill.toggle()
            }.tint(.red)
        }
        .swipeActions(edge: .leading) {
            if bill.status != .paid {
                Button(bill.category == .creditCard ? "Pay" : "Mark Paid", systemImage: "checkmark.circle") {
                    if bill.category == .creditCard {
                        paymentAmount = ""
                        makingPayment = true
                    } else {
                        showMarkPaidConfirmation = true
                    }
                }
                .tint(.green)
            }
        }
        .alert("Delete \(bill.name ?? "Bill") Bill", isPresented: $deletingBill) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    modelContext.delete(bill)
                }
            }
        } message: {
            Text("Are you sure you want to delete your \(bill.name ?? "this") bill? This cannot be undone.")
        }
        .alert(paymentAlertTitle, isPresented: $makingPayment) {
            TextField(paymentPlaceholder, text: $paymentAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { }
            Button("Done") {
                recordPayment()
            }
        } message: {
            Text("How much would you like to pay?")
        }
        .confirmationDialog(
            "Mark \(bill.name ?? "this bill") as paid?",
            isPresented: $showMarkPaidConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark Paid") {
                markPaid()
            }
            Button("Cancel", role: .cancel) { }
        }

    }

    private var paymentPlaceholder: String {
        if let payment = bill.creditCardDetails?.recommendedPayment {
            return "Recommended: \(payment.currency)"
        }
        return "Enter Payment"
    }

    private var paymentAlertTitle: String {
        bill.name ?? "Payment Amount"
    }

    private func recordPayment() {
        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status
        let amount = Double(paymentAmount) ?? 0

        guard amount > 0 else { return }

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
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
        MoneyMapIntentDonations.donateMarkBillPaid(bill, paymentAmount: amount)
        paymentAmount.removeAll()
    }

    private func markPaid() {
        let previousBalance = bill.creditCardDetails?.cardBalance
        let previousDatePaid = bill.datePaid
        let previousDueDate = bill.dueDate
        let previousStatus = bill.status

        bill.datePaid = .now
        bill.status = .paid
        bill.checkStatus()

        AuditService.logBillPayment(
            bill: bill,
            previousBalance: previousBalance,
            previousDatePaid: previousDatePaid,
            previousDueDate: previousDueDate,
            previousStatus: previousStatus,
            amount: bill.amount ?? 0,
            context: modelContext
        )
        try? modelContext.save()
        AppRefreshEvents.notifyBillsDidChange()
        MoneyMapIntentDonations.donateMarkBillPaid(bill)
    }
    
}

#Preview {
    NavigationStack {
        BillsView()
    }
    .modelContainer(Bill.preview)
}
