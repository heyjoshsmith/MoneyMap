//
//  PayCycleLiveActivity.swift
//  MoneyMapShared
//
//  Created by Codex on 4/27/26.
//

import Foundation

#if canImport(ActivityKit) && !os(watchOS)
import ActivityKit

public struct PayCycleLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var nextPaydayText: String
        public var daysUntilPayday: Int
        public var upcomingBillsCount: Int
        public var behindGoalsCount: Int
        public var recommendedCardPaymentTotal: Double
        public var recommendedGoalContributionTotal: Double
        public var topActionTitle: String

        public init(
            nextPaydayText: String,
            daysUntilPayday: Int,
            upcomingBillsCount: Int,
            behindGoalsCount: Int,
            recommendedCardPaymentTotal: Double,
            recommendedGoalContributionTotal: Double,
            topActionTitle: String
        ) {
            self.nextPaydayText = nextPaydayText
            self.daysUntilPayday = daysUntilPayday
            self.upcomingBillsCount = upcomingBillsCount
            self.behindGoalsCount = behindGoalsCount
            self.recommendedCardPaymentTotal = recommendedCardPaymentTotal
            self.recommendedGoalContributionTotal = recommendedGoalContributionTotal
            self.topActionTitle = topActionTitle
        }
    }

    public var title: String

    public init(title: String = "Pay Cycle") {
        self.title = title
    }
}
#endif
