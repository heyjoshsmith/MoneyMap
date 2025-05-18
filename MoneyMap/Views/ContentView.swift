//
//  ContentView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI

// MARK: - ContentView (TabView)
struct ContentView: View {
    
    @State private var selection: Tab = .pay
    
    var body: some View {
        TabView(selection: $selection) {
            GoalsView().tag(Tab.goals)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Goals")
                }
            PaydayView().tag(Tab.pay)
                .tabItem {
                    Image(systemName: "dollarsign.arrow.circlepath")
                    Text("Pay")
                }
            BillsHome().tag(Tab.bills)
                .tabItem {
                    Image(systemName: "banknote")
                    Text("Bills")
                }
        }
    }
    
    enum Tab: String, CaseIterable, Identifiable {
        case goals, pay, bills
        var id: Self { return self }
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    ContentView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
