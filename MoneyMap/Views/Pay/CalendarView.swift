//
//  CalendarView.swift
//  MoneyMap
//
//  Created by Josh Smith on 5/18/25.
//

import SwiftUI

struct CalendarView: View {
    
    init(for date: Date, priority: Bool = false, bonus: Bool = false) {
        self.date = date
        self.priority = priority
        self.bonus = bonus
    }
    
    var date: Date
    var priority: Bool = false
    var bonus: Bool = false
    
    var body: some View {
        VStack {
            if priority {
                VStack {
                    Text(date.daysUntil)
                        .font(.largeTitle.weight(.semibold))
                    Text(date.formatted(date: .long, time: .omitted))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .frame(minHeight: 200)
                .background(MoneyMapDesign.moneyGradient)
                .clipShape(.rect(cornerRadius: MoneyMapDesign.sectionCornerRadius))
            } else {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.title3.weight(.medium))
                .padding()
                .frame(maxWidth: .infinity)
                .background(MoneyMapDesign.surfaceBackground)
                .clipShape(.rect(cornerRadius: MoneyMapDesign.cornerRadius))
            }
        }
    }
}

#Preview {
    CalendarView(for: .now, priority: true)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoneyMapDesign.groupedBackground)
}
