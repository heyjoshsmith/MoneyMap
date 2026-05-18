//
//  PendingRouteStore.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation

enum PendingRouteStore {
    private static let suiteName = "group.com.heyjoshsmith.MoneyMap"
    private static let typeKey = "pending_route_type"
    private static let billIDKey = "pending_route_bill_id"
    private static let goalIDKey = "pending_route_goal_id"

    private enum RouteType: String {
        case openBill
        case openGoal
        case showUpcomingBills
        case showCardUtilization
        case showRecommendations
    }

    static func set(_ route: MoneyMapRoute) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        set(route, defaults: defaults)
    }

    static func set(_ route: MoneyMapRoute, defaults: UserDefaults) {
        switch route {
        case .openBill(let billID):
            defaults.set(RouteType.openBill.rawValue, forKey: typeKey)
            defaults.set(billID.uuidString, forKey: billIDKey)
            defaults.removeObject(forKey: goalIDKey)
        case .openGoal(let goalID):
            defaults.set(RouteType.openGoal.rawValue, forKey: typeKey)
            defaults.set(goalID.uuidString, forKey: goalIDKey)
            defaults.removeObject(forKey: billIDKey)
        case .showUpcomingBills:
            defaults.set(RouteType.showUpcomingBills.rawValue, forKey: typeKey)
            defaults.removeObject(forKey: billIDKey)
            defaults.removeObject(forKey: goalIDKey)
        case .showCardUtilization:
            defaults.set(RouteType.showCardUtilization.rawValue, forKey: typeKey)
            defaults.removeObject(forKey: billIDKey)
            defaults.removeObject(forKey: goalIDKey)
        case .showRecommendations:
            defaults.set(RouteType.showRecommendations.rawValue, forKey: typeKey)
            defaults.removeObject(forKey: billIDKey)
            defaults.removeObject(forKey: goalIDKey)
        case .importCSV:
            break
        }
    }

    static func consume() -> MoneyMapRoute? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        return consume(defaults: defaults)
    }

    static func consume(defaults: UserDefaults) -> MoneyMapRoute? {
        guard let rawType = defaults.string(forKey: typeKey),
              let type = RouteType(rawValue: rawType) else {
            return nil
        }

        defaults.removeObject(forKey: typeKey)
        defer {
            defaults.removeObject(forKey: billIDKey)
            defaults.removeObject(forKey: goalIDKey)
        }

        switch type {
        case .openBill:
            guard let rawID = defaults.string(forKey: billIDKey),
                  let billID = UUID(uuidString: rawID) else {
                return nil
            }
            return .openBill(billID)
        case .openGoal:
            guard let rawID = defaults.string(forKey: goalIDKey),
                  let goalID = UUID(uuidString: rawID) else {
                return nil
            }
            return .openGoal(goalID)
        case .showUpcomingBills:
            return .showUpcomingBills
        case .showCardUtilization:
            return .showCardUtilization
        case .showRecommendations:
            return .showRecommendations
        }
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        clear(defaults: defaults)
    }

    static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: typeKey)
        defaults.removeObject(forKey: billIDKey)
        defaults.removeObject(forKey: goalIDKey)
    }
}
