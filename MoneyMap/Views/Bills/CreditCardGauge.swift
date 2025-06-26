//
//  CreditCardGauge.swift
//  MoneyMap
//
//  Created by Josh Smith on 6/19/25.
//

import SwiftUI

struct CreditCardGauge: View {
    
    var bills: Bills
    
    var body: some View {
        Section {
            
            Gauge(value: bills.totalBalance, in: 0...(bills.totalCreditLimit)) {
                VStack {
                    HStack {
                        Text("Credit Cards")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text(bills.creditCardUtilization, format: .percent.precision(.fractionLength(0)))
                            .fontDesign(.rounded)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(bills.totalBalance, format: .currency(code: "USD").precision(.fractionLength(0)))
                        Spacer()
                        Text(bills.totalCreditLimit, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .tint(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
            
            if bills.creditCardUtilization >= 0.3 {
                HStack {
                    Text("Amount Over Utilization")
                    Spacer()
                    Text((bills.totalBalance - bills.totalCreditLimit * 0.3), format: .currency(code: "USD"))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            
            if let recommendedPayment = bills.recommendedPayment {
                HStack {
                    Text("Recommended Payment")
                    Spacer()
                    Button("Info", systemImage:"info.circle") {
                        
                    }
                    .labelStyle(.iconOnly)
                    Text(recommendedPayment.formatted(.currency(code: "USD")))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
                
            
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    List {
        CreditCardGauge(bills: [])
    }
    .listStyle(.insetGrouped)
}
