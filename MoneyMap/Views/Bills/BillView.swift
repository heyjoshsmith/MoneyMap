//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI

struct BillView: View {
    var bill: Bill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Bill Name
                Text(bill.name)
                    .font(.largeTitle)
                    .bold()
                    .padding(.bottom, 8)
                
                // Amount
                HStack {
                    Text("Amount")
                    Spacer()
                    Text(bill.amount, format: .currency(code: "USD"))
                }
                
                // Due Date
                HStack {
                    Text("Due Date")
                    Spacer()
                    Text(bill.dueDate, style: .date)
                }
                
                // Date Paid (if available)
                if let datePaid = bill.datePaid {
                    HStack {
                        Text("Date Paid")
                        Spacer()
                        Text(datePaid, style: .date)
                    }
                }
                
                // Category
                HStack {
                    Text("Category")
                    Spacer()
                    Label(bill.category.name, systemImage: bill.category.icon)
                        .foregroundColor(bill.category.color)
                }
                
                // Recurrence
                HStack {
                    Text("Recurrence")
                    Spacer()
                    Text("Every \(bill.recurrenceInterval) \(bill.recurrenceUnit.rawValue)\(bill.recurrenceInterval > 1 ? "s" : "")")
                }
                
                // Credit Card Details (if applicable)
                if bill.category == .creditCard, let details = bill.creditCardDetails {
                    Divider()
                    Text("Credit Card Details")
                        .font(.headline)
                    HStack {
                        Text("Credit Limit")
                        Spacer()
                        Text(details.creditLimit, format: .currency(code: "USD"))
                    }
                    HStack {
                        Text("Card Balance")
                        Spacer()
                        Text(details.cardBalance, format: .currency(code: "USD"))
                    }
                    HStack {
                        Text("Utilization")
                        Spacer()
                        utilizationIcon
                    }
                    
                    HStack {
                        Text("Max Usage")
                        Spacer()
                        Text(details.creditLimit * 0.3, format: .currency(code: "USD"))
                    }
                    
                    if let recommendedPayment {
                        HStack {
                            Text("Recommended Payment")
                            Spacer()
                            Text(recommendedPayment, format: .currency(code: "USD"))
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Bill Details")
    }
    
    var recommendedPayment: Double? {
        
        guard let details = bill.creditCardDetails else {
            return nil
        }
        
        let payment = details.cardBalance - (details.creditLimit * 0.3)
        
        if payment < 0 {
            return nil
        } else {
            return payment
        }
    }
    
    var aboveMax: Bool {
        if let creditCardDetails = bill.creditCardDetails {
            
            return (creditCardDetails.cardBalance / creditCardDetails.creditLimit) >= 0.3
            
        }
        
        return false
    }
    
    var utilizationIcon: some View {
        HStack {
            if let creditCardDetails = bill.creditCardDetails {
                
                let above = (creditCardDetails.cardBalance / creditCardDetails.creditLimit) >= 0.3
                
                if above {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                Text((creditCardDetails.cardBalance / creditCardDetails.creditLimit), format: .percent.precision(.fractionLength(0)))
                
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.gray)
                Text("N/A")
            }
        }
    }
}

#Preview {
    // Create a sample bill for preview purposes
    let sampleBill = Bill(name: "Sample Bill",
                          amount: 123.45,
                          dueDate: Date(),
                          category: .creditCard,
                          recurrenceInterval: 1,
                          recurrenceUnit: .month,
                          creditCardDetails: CreditCardDetails(creditLimit: 5000, cardBalance: 1200))
    BillView(bill: sampleBill)
}
