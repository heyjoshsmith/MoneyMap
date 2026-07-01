//
//  AppRefreshEvents.swift
//  MoneyMap
//
//  Created by Codex on 6/7/26.
//

import Foundation

enum AppRefreshEvents {
    static let billsDidChange = Notification.Name("MoneyMap.billsDidChange")

    static func notifyBillsDidChange() {
        NotificationCenter.default.post(name: billsDidChange, object: nil)
    }
}
