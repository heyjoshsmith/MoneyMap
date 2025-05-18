//
//  GoalsListView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import SwiftData
import MoneyMapShared

struct GoalsListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var paydayManager: PaydayManager
    @Query(sort: \Goal.deadline, order: .forward) var goals: [Goal]
    
    var body: some View {
        List {
            
            if paydayManager.nextPayday == nil {
                Section("Warning") {
                    Text("Please set your next payday in the Payday tab before creating a goal.")
                        .foregroundColor(.red)
                }
            }
            
            ForEach(goals) { goal in
                NavigationLink(destination: GoalDetailView(goal)) {
                    HStack {
                        
                        if let image = goal.loadImage() {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50, alignment: .center)
                                .cornerRadius(10)
                        } else {
                            Image(systemName: "target")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(
                                    LinearGradient(gradient: Gradient(colors: [.orange, .red]),
                                                   startPoint: .top,
                                                   endPoint: .bottom)
                                )
                                .frame(width: 50, height: 50, alignment: .center)
                        }
                        
                        VStack(alignment: .leading) {
                            if let name = goal.name {
                                Text(name)
                                    .font(.title2.weight(.semibold))
                            } else {
                                Text("Save $\(goal.targetAmount, specifier: "%.2f")")
                                    .font(.headline)
                            }
                            Text("By \(goal.deadline, style: .date)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        
                        if goal.name != nil {
                            Spacer()
                            
                            Gauge(value: goal.progress(), in: 0...1) {
                                Text("Progress")
                            } currentValueLabel: {
                                Text("\(Int(goal.progress() * 100))%")
                            }
                            .tint(.green)
                            .gaugeStyle(.accessoryCircularCapacity)
                            
                        }
                        
                    }
                    .padding(.vertical, 5)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash") {
                        modelContext.delete(goal)
                    }.tint(.red)
                }
            }
            
        }
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
