//
//  BillRow.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import SwiftUI
import SwiftData
import AppIntents

struct BillRow: View {
    
    var bills: Bills
    @Query(sort: \PaymentMethod.name) private var paymentMethods: [PaymentMethod]
    
    var body: some View {
        VStack {
            
            HStack {
                Text("Bills")
                    .font(.title3.weight(.medium))
                Spacer()
                NavigationLink {
                    BillsView()
                } label: {
                    Label("View All", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .foregroundStyle(MoneyMapDesign.calmGreen)
            }.padding(.horizontal)
            
            ScrollView(.horizontal) {
                HStack {
                    ForEach(bills.withoutCreditCards) { bill in
                        BillButton(bill: bill, paymentMethods: paymentMethods)
                    }
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
    var paymentMethods: [PaymentMethod] = []

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

    private var paymentLabel: String {
        if let methodName = bill.paymentMethodName(in: paymentMethods) {
            return "\(bill.paymentModeTitle) - \(methodName)"
        }
        return bill.autopayEnabled ? "Autopay" : "Manual"
    }
    
    var body: some View {
        NavigationLink {
            BillView(bill: bill)
        } label: {
            BillStateRow(bill: bill, paymentMethods: paymentMethods)
                .padding(12)
                .frame(width: 320, alignment: .leading)
                .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius)
                        .stroke(MoneyMapDesign.separator, lineWidth: 1)
                }
        }
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
    .modelContainer(Bill.preview)
}
