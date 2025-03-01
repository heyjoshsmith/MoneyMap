//
//  GridView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/28/25.
//

import SwiftUI

struct GridView: View {
    
    init(_ goal: Goal, choosingImage: Binding<Bool>) {
        self.goal = goal
        self._targetAmount = State(initialValue: goal.targetAmount)
        self._amountSaved = State(initialValue: goal.amountSaved)
        self._deadline = State(initialValue: goal.deadline)
        self._priority = State(initialValue: goal.weight)
        self._choosingImage = choosingImage
    }
    
    var goal: Goal
    @Binding var choosingImage: Bool
    
    @State private var editingAmountSaved = false
    @State private var amountSaved: Double?
    
    @State private var editingTargetAmount = false
    @State private var targetAmount: Double?
    
    @State private var editingDeadline = false
    @State private var deadline: Date = .now
    
    @State private var editingPriority = false
    @State private var priority: Double?
    
    var body: some View {
        Grid() {
            
            if goal.loadImage() == nil, let name = goal.name {
                GridRow {
                    Button {
                        choosingImage.toggle()
                    } label: {
                        HStack {
                            Text(name)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.callout)
                        }
                        .font(.title.weight(.bold))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.primary)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .gridCellColumns(2)
                }
            }
            
            GridRow {
                
                Widget(.targetAmount, value: goal.targetAmount) {
                    editingTargetAmount.toggle()
                }
                
                Widget(.deadline, date: goal.deadline) {
                    editingDeadline.toggle()
                }
                
            }
            
            GridRow {
                Widget(.daysUntilDeadline, value: Double(daysUntilDeadline), currency: false)
                Widget(.numberOfPaydays, value: Double(paydayManager.numberOfPaydaysUntil(goal.deadline)), currency: false)
            }
            
            GridRow {
                Widget(.amountSaved, value: goal.amountSaved) {
                    editingAmountSaved.toggle()
                }
                Widget(.remainingValue, value: remainingAmount)
            }
            
            GridRow {
                Widget(.priority, value: goal.weight, currency: false) {
                    editingPriority.toggle()
                }
                .gridCellColumns(2)
            }
            
            GridRow {
                URLCarousel(for: goal)
            }
            
        }
        .padding()
        .sheet(isPresented: $editingPriority) {
            VStack(alignment: .leading) {
                
                Text("Priority")
                    .font(.title2.weight(.semibold))
                
                ForEach(Priority.allCases) { priority in
                    Button {
                        withAnimation {
                            goal.weight = priority.value
                            editingPriority.toggle()
                        }
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: priority.icon)
                                .foregroundStyle(priority.color)
                            Text(priority.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
                
            }
            .padding()
            .presentationDetents([.fraction(0.33)])
        }
        .sheet(isPresented: $editingDeadline) {
            DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .presentationDetents([.medium])
        }
        .alert("Amount Saved", isPresented: $editingAmountSaved, actions: {
            TextField(goal.amountSaved.formatted(.currency(code: "USD").precision(.fractionLength(0))), value: $amountSaved, format: .currency(code: "USD").precision(.fractionLength(0)))
            Button("Cancel", role: .cancel) { }
            Button("Add Amount") {
                goal.amountSaved += (amountSaved ?? 0)
            }
            Button("Save Total") {
                goal.amountSaved = amountSaved ?? 0
            }
        }, message: {
            Text("You currently have \(goal.amountSaved, format: .currency(code: "USD").precision(.fractionLength(0))) saved.")
        })
        .alert("Target Amount", isPresented: $editingTargetAmount, actions: {
            TextField(goal.targetAmount.formatted(.currency(code: "USD").precision(.fractionLength(0))), value: $targetAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                goal.targetAmount = targetAmount ?? 0
            }
        })
    }
    
    /// Days remaining until the deadline.
    var daysUntilDeadline: Int {
        let now = Date()
        let components = Calendar.current.dateComponents([.day], from: now, to: goal.deadline)
        return components.day ?? 0
    }
    
    /// The remaining amount left to save.
    var remainingAmount: Double {
        return max(goal.targetAmount - goal.amountSaved, 0)
    }
    
    @EnvironmentObject var paydayManager: PaydayManager
    
}

enum Priority: Double, CaseIterable, Identifiable {
    case high = 2, medium = 1, low = 0.5
    
    var name: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Loa"
        }
    }
    
    var icon: String {
        switch self {
        case .high:
            return "exclamationmark.triangle.fill"
        case .medium:
            return "flag"
        case .low:
            return "circle.dashed"
        }
    }
    
    var color: Color {
        switch self {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .gray
        }
    }
    
    var value: Double {
        switch self {
        case .high:
            return 2
        case .medium:
            return 1
        case .low:
            return 0.5
        }
    }
    
    var id: Self { return self }
}

#Preview {
        
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        GridView(Goal("Test", targetAmount: 300, deadline: .now, weight: 1, imageURL: nil, paydaysUntil: 3), choosingImage: .constant(false))
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
}
