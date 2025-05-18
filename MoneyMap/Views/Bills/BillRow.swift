//
//  BillRow.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import SwiftUI

struct BillRow: View {
    
    var bills: Bills
    @State private var isPresented: Bool = false
    
    var body: some View {
        VStack {
            
            HStack {
                Text("Bills")
                    .font(.title3.weight(.medium))
                Spacer()
                Button("View All") {
                    isPresented.toggle()
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
        .navigationDestination(isPresented: $isPresented) {
            BillsView()
        }
    }
    
}

struct BillButton: View {
    
    var bill: Bill
    
    var body: some View {
        NavigationLink {
            BillView(bill: bill)
        } label: {
            HStack {
                Image(systemName: bill.category.icon)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bill.name)
                        .font(.title3.weight(.semibold))
                    let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: bill.dueDate).day ?? 0
                    Text("\(daysUntilDue) days")
                        .font(.footnote)
                        .opacity(0.7)
                }
                Text(bill.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .padding(.leading)
            }
            .padding()
            .foregroundStyle(.white)
            .background(bill.category.color.gradient)
            .clipShape(.rect(cornerRadius: 10))
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
