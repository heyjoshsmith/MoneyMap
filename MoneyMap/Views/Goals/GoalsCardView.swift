//
//  GoalsCardView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import SwiftData
import MoneyMapShared

struct GoalsCardView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var paydayManager: PaydayManager
    @Query(sort: [
        SortDescriptor(\Goal.deadline, order: .forward),
        SortDescriptor(\Goal.targetAmount, order: .forward),
        SortDescriptor(\Goal.name, order: .forward)
    ]) var goals: [Goal]
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(goals) { goal in
                    NavigationLink(destination: GoalDetailView(goal)) {
                        CardView(for: goal)
                            .shadow(radius: 5)
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(goal)
                        }.tint(.red)
                    }
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        GoalsCardView()
            .navigationTitle("Goals")
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
    
}
