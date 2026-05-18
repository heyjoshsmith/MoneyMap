//
//  PayCycleLiveActivityManager.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import ActivityKit
import Foundation

@MainActor
final class PayCycleLiveActivityManager: ObservableObject {
    func sync(
        availableCash: Double,
        goals: [Goal],
        bills: [Bill],
        nextPayday: Date?
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let digest = FinancialPlanningEngine.digest(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )

        let nextPaydayText = nextPayday.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Not set"
        let daysUntilPayday = nextPayday.map {
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: $0)
            ).day ?? 0
        } ?? 0
        let topAction = digest.topCardName ?? digest.topGoalName ?? "Review recommendations"
        let contentState = PayCycleLiveActivityAttributes.ContentState(
            nextPaydayText: nextPaydayText,
            daysUntilPayday: max(daysUntilPayday, 0),
            upcomingBillsCount: digest.upcomingBillCount,
            behindGoalsCount: digest.behindGoalCount,
            recommendedCardPaymentTotal: digest.suggestedCardPaymentTotal,
            recommendedGoalContributionTotal: digest.suggestedGoalContributionTotal,
            topActionTitle: topAction
        )

        let content = ActivityContent(state: contentState, staleDate: nextPayday)
        let attributes = PayCycleLiveActivityAttributes()

        if let existing = Activity<PayCycleLiveActivityAttributes>.activities.first {
            Task {
                await existing.update(content)
            }
        } else {
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                print("Live Activity request error: \(error.localizedDescription)")
            }
        }
    }
}
