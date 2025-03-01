//
//  BackgroundView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/16/25.
//

import SwiftUI
import SwiftData

struct BackgroundView: View {
    
    @Query private var goals: [Goal]
    
    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack {
                    ForEach(goals) { goal in
                        NavigationLink {
                            GoalDetailView(goal)
                        } label: {
                            CardView(for: goal)
                                .shadow(radius: 5)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        BackgroundView()
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
}
