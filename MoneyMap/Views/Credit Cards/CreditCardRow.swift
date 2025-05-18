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
                                Text(creditCard.name)
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
                    .tint(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .overlay {
                        GeometryReader { geometry in
                            // Calculate the x-coordinate for 30% of the gauge's width
                            let markerX = geometry.size.width * 0.3
                            // Position the marker (a hollow circle with a white outline) at that position and vertically centered.
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 15, height: 15)
                                .position(x: markerX, y: geometry.size.height - 8)
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
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 15))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
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
        .listStyle(.plain)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
