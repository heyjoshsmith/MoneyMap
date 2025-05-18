//
//  BillsView.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import SwiftUI
import SwiftData

struct BillsView: View {
    
    @Query private var bills: Bills
    
    var body: some View {
        List {
            ForEach(Timeframe.allCases) { timeframe in
                
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
        .navigationTitle("Bills")
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
    
    var body: some View {
        NavigationLink {
            BillView(bill: bill)
        } label: {
            HStack(spacing: 10) {
                
                Image(systemName: bill.category.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(bill.category.color.gradient)
                    .clipShape(.rect(cornerRadius: 5))
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(bill.name)
                        .font(.title3.weight(.semibold))
                    Text(bill.status?.name ?? "N/A")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(bill.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .padding(.leading)
            }
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
        .alert("Delete \(bill.name) Bill", isPresented: $deletingBill) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    modelContext.delete(bill)
                }
            }
        } message: {
            Text("Are you sure you want to delete your \(bill.name) bill? This cannot be undone.")
        }

    }
    
}

#Preview {
    NavigationStack {
        BillsView()
    }
    .modelContainer(Bill.preview)
}
