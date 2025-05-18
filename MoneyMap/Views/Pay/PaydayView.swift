//
//  PaydayView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI

struct PaydayRow: Identifiable {
    let id = UUID()
    let items: [Date]
    let bonuses: [Bool]
    let isPriority: Bool
}

struct PaydayView: View {
    
    @EnvironmentObject var paydayManager: PaydayManager
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    if let _ = paydayManager.nextPayday {
                        let paydays = paydayManager.upcomingPaydaysForNextYear()
                        let batched = batchedPaydays(paydays)
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            ForEach(batched) { row in
                                GridRow {
                                    if row.isPriority {
                                        CalendarView(for: row.items[0], priority: true, bonus: row.bonuses[0])
                                            .gridCellColumns(2)
                                    } else {
                                        CalendarView(for: row.items[0], priority: false, bonus: row.bonuses[0])
                                        if row.items.count > 1 {
                                            CalendarView(for: row.items[1], priority: false, bonus: row.bonuses[1])
                                        } else {
                                            Color.clear
                                        }
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                    } else {
                        Text("Please select your next payday")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 10))
                        
                        // Calendar picker for selecting the next payday.
                        DatePicker("Select Next Payday", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                            .padding()
                        
                        Spacer()
                                            
                        Button(action: {
                            paydayManager.savePayday(selectedDate)
                        }) {
                            Label("Set Next Payday", systemImage: "checkmark.circle")
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(gradient: Gradient(colors: [.green, .blue]),
                                                   startPoint: .leading,
                                                   endPoint: .trailing)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Pay")
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

private extension PaydayView {
    private func batchedPaydays(_ paydays: [Date]) -> [PaydayRow] {
        var rows: [PaydayRow] = []
        var i = 0
        while i < paydays.count {
            let payday = paydays[i]
            let bonus = payday.isExtraPayDay(in: paydays)
            let isPriority = (i == 0 || bonus)
            if isPriority {
                rows.append(PaydayRow(items: [payday], bonuses: [bonus], isPriority: true))
                i += 1
            } else {
                if i + 1 < paydays.count {
                    let nextPayday = paydays[i + 1]
                    let nextBonus = nextPayday.isExtraPayDay(in: paydays)
                    let nextIsPriority = ((i + 1) == 0 || nextBonus)
                    if !nextIsPriority {
                        rows.append(PaydayRow(items: [payday, nextPayday], bonuses: [bonus, nextBonus], isPriority: false))
                        i += 2
                    } else {
                        rows.append(PaydayRow(items: [payday], bonuses: [bonus], isPriority: false))
                        i += 1
                    }
                } else {
                    rows.append(PaydayRow(items: [payday], bonuses: [bonus], isPriority: false))
                    i += 1
                }
            }
        }
        return rows
    }
}

#Preview("Goals") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    PaydayView()
        .environmentObject(paydayManager)
        .modelContainer(container)
}
