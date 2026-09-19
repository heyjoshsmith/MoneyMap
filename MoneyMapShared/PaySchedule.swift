import Foundation

public enum PayScheduleKind: String, Codable, CaseIterable, Identifiable {
    case weekly, biweekly, twiceMonthly, monthly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every two weeks"
        case .twiceMonthly: return "Twice monthly"
        case .monthly: return "Monthly"
        }
    }
}

/// Calendar dates, not elapsed seconds. Zero represents the last day of a month.
public struct PaySchedule: Codable, Equatable {
    public var kind: PayScheduleKind
    public var anchor: Date
    public var firstDay: Int?
    public var secondDay: Int?
    public init(kind: PayScheduleKind = .biweekly, anchor: Date, firstDay: Int? = nil, secondDay: Int? = nil) {
        self.kind = kind; self.anchor = anchor; self.firstDay = firstDay; self.secondDay = secondDay
    }

    public func next(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: date)
        if kind == .weekly || kind == .biweekly {
            let origin = calendar.startOfDay(for: anchor)
            let interval = kind == .weekly ? 7 : 14
            let distance = calendar.dateComponents([.day], from: origin, to: day).day ?? 0
            let steps = Int(ceil(Double(distance) / Double(interval)))
            return calendar.date(byAdding: .day, value: steps * interval, to: origin)
        }
        guard let month = calendar.dateInterval(of: .month, for: day)?.start else { return nil }
        for offset in 0...2 {
            guard let start = calendar.date(byAdding: .month, value: offset, to: month),
                  let range = calendar.range(of: .day, in: .month, for: start) else { continue }
            let days = kind == .monthly ? [firstDay ?? calendar.component(.day, from: anchor)] : [firstDay ?? 1, secondDay ?? 15]
            let dates = Set(days.compactMap { value -> Date? in
                let target = value == 0 ? range.count : min(max(value, 1), range.count)
                return calendar.date(byAdding: .day, value: target - 1, to: start)
            })
            if let result = dates.filter({ $0 >= day }).min() { return result }
        }
        return nil
    }

    public func dates(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        guard start <= end else { return [] }
        var result: [Date] = []
        var current = next(onOrAfter: start, calendar: calendar)
        while let value = current, value <= end, result.count < 20_000 {
            result.append(value)
            guard let following = calendar.date(byAdding: .day, value: 1, to: value) else { break }
            current = next(onOrAfter: following, calendar: calendar)
        }
        return result
    }

    public func previous(before date: Date, calendar: Calendar = .current) -> Date? {
        guard let start = calendar.date(byAdding: .month, value: -2, to: date),
              let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) else { return nil }
        return dates(from: start, through: end, calendar: calendar).last
    }
}
