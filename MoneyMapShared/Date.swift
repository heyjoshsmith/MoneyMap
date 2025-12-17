//
//  Date.swift
//  MoneyMap
//
//  Created by Josh Smith on 4/2/25.
//

import Foundation

extension Date {
    /// Returns a string representing the number of days until the given date.
    /// - Parameter target: The date to compare with.
    /// - Returns: "Overdue" if the target is in the past, "Today" if it’s the same day,
    ///            "Tomorrow" if it’s one day away, or "x Days" for any other future date.
    var daysUntil: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let targetDay = calendar.startOfDay(for: self)
        let daysDifference = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
        
        switch daysDifference {
        case let days where days < 0:
            return "Overdue"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return "\(daysDifference) Days"
        }
    }
    
    func isExtraPayDay(in paydays: [Date]) -> Bool {
        let calendar = Calendar.current
        let paydayMonth = calendar.component(.month, from: self)
        let paydayYear = calendar.component(.year, from: self)
        // Count how many paydays in this month up to this index
        guard let index = paydays.firstIndex(of: self) else {
            return false
        }
        let countInMonth = paydays[0...index].filter {
            calendar.component(.month, from: $0) == paydayMonth &&
            calendar.component(.year, from: $0) == paydayYear
        }.count
        let isThirdPaydayInMonth = countInMonth == 3
        return isThirdPaydayInMonth
    }
}
