//
//  MoneyMapAction.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation

enum MoneyMapAction: String, CaseIterable {
    case addBill = "add_bill"
    case importTransactions = "import_transactions"
    case editCardLimit = "edit_card_limit"
    case makePayment = "make_payment"
    case editBalance = "edit_balance"
    case editLimit = "edit_limit"
    case showUpcomingBills = "show_upcoming_bills"
    case showCardUtilization = "show_card_utilization"
    case openBill = "open_bill"
    case openGoal = "open_goal"
    case showRecommendations = "show_recommendations"

    var title: String {
        switch self {
        case .addBill:
            return "Add Bill"
        case .importTransactions:
            return "Import Transactions"
        case .editCardLimit:
            return "Edit Card Limit"
        case .makePayment:
            return "Pay"
        case .editBalance:
            return "Balance"
        case .editLimit:
            return "Limit"
        case .showUpcomingBills:
            return "Upcoming Bills"
        case .showCardUtilization:
            return "Card Utilization"
        case .openBill:
            return "Open Bill"
        case .openGoal:
            return "Open Goal"
        case .showRecommendations:
            return "Recommendations"
        }
    }

    var systemImage: String {
        switch self {
        case .addBill:
            return "plus"
        case .importTransactions:
            return "square.and.arrow.down"
        case .editCardLimit:
            return "slider.horizontal.3"
        case .makePayment:
            return "dollarsign.arrow.trianglehead.counterclockwise.rotate.90"
        case .editBalance, .editLimit:
            return "dollarsign.gauge.chart.lefthalf.righthalf"
        case .showUpcomingBills:
            return "calendar.badge.exclamationmark"
        case .showCardUtilization:
            return "chart.pie"
        case .openBill:
            return "doc.text.magnifyingglass"
        case .openGoal:
            return "target"
        case .showRecommendations:
            return "wand.and.stars"
        }
    }
}
