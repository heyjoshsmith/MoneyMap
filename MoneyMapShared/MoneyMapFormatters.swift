//
//  MoneyMapFormatters.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation

enum MoneyMapFormatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.autoupdatingCurrent
        return formatter
    }()

    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.autoupdatingCurrent
        return formatter
    }()

    static func currencyString(for value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func mediumDateString(for date: Date) -> String {
        mediumDate.string(from: date)
    }
}
