//
//  ContentView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/11/25.
//

import SwiftUI

// MARK: - ContentView (TabView)
struct ContentView: View {
    var body: some View {
        TabView {
            GoalsView()
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Goals")
                }
            BillsView()
                .tabItem {
                    Image(systemName: "banknote")
                    Text("Bills")
                }
        }
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    ContentView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
