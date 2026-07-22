//
//  GoalsCardView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import SwiftData
import AppIntents


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
            let columns = [
                GridItem(.adaptive(minimum: 260), spacing: MoneyMapDesign.sectionSpacing)
            ]
            Group {
                if goals.isEmpty {
                    MoneyMapEmptyState(
                        title: "No Goals Yet",
                        message: "Add a savings goal to track progress toward something specific.",
                        systemImage: "target"
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVGrid(columns: columns, spacing: MoneyMapDesign.sectionSpacing) {
                        ForEach(goals) { goal in
                            NavigationLink(destination: GoalDetailView(goal)) {
                                CardView(for: goal)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                MoneyMapIntentDonations.donateOpenGoal(goal)
                            })
                            .userActivity("com.heyjoshsmith.MoneyMap.viewingGoalCard") { activity in
                                let entity = GoalEntity(goal)
                                activity.title = "Browsing \(entity.name)"
                                activity.appEntityIdentifier = EntityIdentifier(for: entity)
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(goal)
                                }
                            }
                        }
                    }
                }
            }
            .padding(MoneyMapDesign.sectionSpacing)
        }
        .background(MoneyMapDesign.groupedBackground)
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
