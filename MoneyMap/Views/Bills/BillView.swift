//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI

struct BillView: View {
    var bill: Bill
    
    @State private var animate = false
    @State private var editingLimit = false
    @State private var cardLimit = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                VStack(spacing: 10) {
                    
                    if bill.category != .creditCard {
                        Text(bill.amount, format: .currency(code: "USD"))
                            .font(.title.weight(.medium))
                    }
                    
                    Label(bill.name, systemImage: bill.category.icon)
                        .font(.largeTitle.weight(.semibold))
                        
                    Text(bill.dueDate, style: .date)
                        .opacity(0.7)
                    
                }
                .scaleEffect(animate ? 1.0 : 0.75)
                .opacity(animate ? 1.0 : 0.0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8)) {
                        animate = true
                    }
                }
                .frame(maxWidth: .infinity, idealHeight: 300)
                .foregroundStyle(.white)
                .background(bill.category.color.gradient)

                
                VStack(spacing: 10) {
                    
                    // Credit Card Details (if applicable)
                    if bill.category == .creditCard, let details = bill.creditCardDetails {
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Card Balance")
                                    .font(.title3.weight(.medium))
                                Text("\(details.cardBalance.abbreviatedCurrency) of \(details.creditLimit.abbreviatedCurrency)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Gauge(value: details.cardBalance, in: 0...details.creditLimit) {
                                Text(details.utilization, format: .percent.precision(.fractionLength(0)))
                                    .font(.callout.weight(.medium))
                            }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(aboveMax ? .red : .green)
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 15))
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                        .padding(.bottom)
                        
                        HStack {
                            Text("Max Usage")
                            Spacer()
                            Text(details.creditLimit * 0.3, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        
                        if let recommendedPayment {
                            HStack {
                                Text("Recommended Payment")
                                Spacer()
                                Text(recommendedPayment, format: .currency(code: "USD"))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Recurrence
                    HStack {
                        Text("Recurrence")
                        Spacer()
                        Text("Every \(bill.recurrenceInterval) \(bill.recurrenceUnit.rawValue)\(bill.recurrenceInterval > 1 ? "s" : "")")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                }
                .padding()
            }
        }
        .navigationTitle("Bill Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            if bill.category == .creditCard {
                Menu("Options", systemImage: "ellipsis.circle") {
                    Button("Adjust Card Limit", systemImage: "creditcard.trianglebadge.exclamationmark") {
                        editingLimit.toggle()
                    }
                }
            }
        }
        .alert("Card Limit", isPresented: $editingLimit) {
            TextField((bill.creditCardDetails?.creditLimit ?? 0).formatted(.currency(code: "USD")), text: $cardLimit)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                bill.creditCardDetails?.creditLimit = Double(cardLimit) ?? 0
            }
        } message: {
            if let details = bill.creditCardDetails {
                Text("What is your new card limit? Your current limit is \(details.creditLimit, format: .currency(code: "USD"))")
            }
        }

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
                          creditCardDetails: CreditCardDetails(creditLimit: 5000, cardBalance: 1200)
    )
    NavigationStack {
        BillView(bill: sampleBill)
    }
}
