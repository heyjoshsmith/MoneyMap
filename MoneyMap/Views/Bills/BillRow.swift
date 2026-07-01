//
//  BillRow.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import SwiftUI
import AppIntents

struct BillRow: View {
    
    var bills: Bills
    
    var body: some View {
        VStack {
            
            HStack {
                Text("Bills")
                    .font(.title3.weight(.medium))
                Spacer()
                NavigationLink {
                    BillsView()
                } label: {
                    HStack {
                        Spacer()
                        Text("View All")
                    }
                }
                .foregroundStyle(.blue)
            }.padding(.horizontal)
            
            ScrollView(.horizontal) {
                HStack {
                    ForEach(bills.withoutCreditCards, content: BillButton.init)
                }
                .padding(.horizontal)
            }
            
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 15, leading: 0, bottom: 15, trailing: 0))
        .listRowSeparator(.hidden)
        .scrollIndicators(.hidden)
    }
    
}

struct BillButton: View {
    
    var bill: Bill

    private var dueLabel: String {
        guard let dueDate = bill.dueDate else { return "No due date" }
        let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        if bill.status == .paid {
            return "Paid"
        }
        if daysUntilDue < 0 {
            return "Overdue"
        }
        if daysUntilDue == 0 {
            return "Due today"
        }
        if daysUntilDue == 1 {
            return "1 day"
        }
        return "\(daysUntilDue) days"
    }
    
    var body: some View {
        NavigationLink {
            BillView(bill: bill)
        } label: {
            HStack {
                Image(systemName: bill.category?.icon ?? "questionmark.circle")
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bill.name ?? "Untitled")
                        .font(.title3.weight(.semibold))
                    Text(dueLabel)
                        .font(.footnote)
                        .opacity(0.7)
                }
                Text((bill.amount ?? 0), format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .padding(.leading)
            }
            .padding()
            .foregroundStyle(.white)
            .background(bill.category?.color.gradient ?? Color.gray.gradient)
            .clipShape(.rect(cornerRadius: 10))
        }
        .simultaneousGesture(TapGesture().onEnded {
            MoneyMapIntentDonations.donateOpenBill(bill)
        })
        .userActivity("com.heyjoshsmith.MoneyMap.viewingBillCard") { activity in
            let entity = BillEntity(bill)
            activity.title = "Browsing \(entity.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .task {
            bill.checkStatus()
        }
    }
    
}

#Preview {
    NavigationStack {
        List {
            BillRow(bills: Bill.sampleBills().withoutCreditCards)
        }
        .listStyle(.plain)
    }
    .modelContainer(Bill.preview)
}
