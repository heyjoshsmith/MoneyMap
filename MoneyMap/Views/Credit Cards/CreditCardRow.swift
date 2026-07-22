//
//  CreditCardRow.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/30/25.
//

import SwiftUI

struct CreditCardRow: View {
    
    init(for creditCard: Bill) {
        self.creditCard = creditCard
    }
    
    var creditCard: Bill
    
    @State private var isPresented: Bool = false
    
    var body: some View {
        Button {
            isPresented = true
        } label: {
            VStack {
                if let details = creditCard.creditCardDetails {
                    
                    Gauge(value: details.cardBalance, in: 0...(details.creditLimit)) {
                        VStack {
                            HStack {
                                Text(creditCard.name ?? "Untitled")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text(creditCard.status?.name ?? "")
                                    .fontDesign(.rounded)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(creditCard.status?.color ?? .secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text(details.cardBalance, format: .currency(code: "USD").precision(.fractionLength(0)))
                                Spacer()
                                Text(details.creditLimit, format: .currency(code: "USD").precision(.fractionLength(0)))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .tint(MoneyMapDesign.moneyGradient)
                    .overlay {
                        GeometryReader { geometry in
                            // Position the marker (a hollow circle with a white outline) at that position and vertically centered.
                            Group {
                                if details.utilization >= 0.3 {
                                    Image(systemName: "30.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .fontWeight(.light)
                                        .frame(width: 15, height: 15)
                                        .position(x: geometry.size.width * 0.3, y: geometry.size.height - 8)
                                } else if details.utilization >= 0.1 {
                                    Image(systemName: "10.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .fontWeight(.light)
                                        .frame(width: 15, height: 15)
                                        .position(x: geometry.size.width * 0.1, y: geometry.size.height - 8)
                                }
                            }
                            .symbolVariant(.fill)
                            .foregroundStyle(MoneyMapDesign.attentionRed, .white)
                        }
                    }
                    
                    if details.overUtilized {
                        Text("Using **\(details.utilization, format: .percent.precision(.fractionLength(0)))** of Limit")
                            .font(.callout)
                            .padding(.top, 5)
                    }

                }
            }
            .padding()
            .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius)
                    .stroke(MoneyMapDesign.separator, lineWidth: 1)
            }
            .task {
                creditCard.checkStatus()
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 7, leading: 15, bottom: 7, trailing: 15))
        .listRowBackground(Color.clear)
        .navigationDestination(isPresented: $isPresented) {
            BillView(bill: creditCard)
        }
    }
    
}

#Preview {
    NavigationStack {
        List {
            ForEach(Bill.sampleBills(type: .creditCard)) {  bill in
                CreditCardRow(for: bill)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
}
