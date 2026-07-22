//
//  GoalsListView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import SwiftData
import AppIntents


struct GoalsListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var paydayManager: PaydayManager
    @Query(sort: \Goal.deadline, order: .forward) var goals: [Goal]
    
    var body: some View {
        List {
            
            if paydayManager.nextPayday == nil {
                Section("Payday Timing") {
                    MoneyMapActionListRow(
                        title: "Payday not set",
                        detail: "Goals still work, but paycheck pacing and recommendations improve once payday is set.",
                        systemImage: "calendar.badge.exclamationmark",
                        tint: MoneyMapDesign.warningGold
                    )
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }

            Section("Goals") {
                if goals.isEmpty {
                    MoneyMapEmptyState(
                        title: "No Goals Yet",
                        message: "Add a savings goal to track progress toward something specific.",
                        systemImage: "target"
                    )
                } else {
                    ForEach(goals) { goal in
                        NavigationLink(destination: GoalDetailView(goal)) {
                            GoalRowView(goal: goal)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            MoneyMapIntentDonations.donateOpenGoal(goal)
                        })
                        .userActivity("com.heyjoshsmith.MoneyMap.viewingGoalRow") { activity in
                            let entity = GoalEntity(goal)
                            activity.title = "Reviewing \(entity.name)"
                            activity.appEntityIdentifier = EntityIdentifier(for: entity)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(goal)
                            }
                        }
                    }
                }
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
    }
}

#Preview {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        GoalsListView()
            .navigationTitle("Goals")
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
    
}
