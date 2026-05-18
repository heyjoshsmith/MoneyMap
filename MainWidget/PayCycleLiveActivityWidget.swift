//
//  PayCycleLiveActivityWidget.swift
//  MainWidget
//
//  Created by Codex on 4/27/26.
//

import ActivityKit
import SwiftUI
import WidgetKit
import MoneyMapShared

struct PayCycleLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PayCycleLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                Text("Before Next Payday")
                    .font(.headline)
                Text("Next payday: \(context.state.nextPaydayText)")
                    .font(.subheadline)
                Text(summaryLine(for: context.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    Label("\(context.state.upcomingBillsCount) upcoming bills", systemImage: "calendar")
                    Label("\(context.state.behindGoalsCount) goals behind", systemImage: "target")
                }
                .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top focus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(context.state.topActionTitle)
                        .font(.caption.weight(.semibold))
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("Payday")
                            .font(.caption2)
                        Text("\(context.state.daysUntilPayday)d")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("Needs")
                            .font(.caption2)
                        Text("\(context.state.upcomingBillsCount + context.state.behindGoalsCount)")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested for cards: \(WidgetFormatters.currency(context.state.recommendedCardPaymentTotal))")
                        Text("Suggested for goals: \(WidgetFormatters.currency(context.state.recommendedGoalContributionTotal))")
                        Text("Focus on \(context.state.topActionTitle)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Text("\(context.state.daysUntilPayday)d")
            } compactTrailing: {
                Image(systemName: "banknote")
            } minimal: {
                Image(systemName: "banknote")
            }
        }
    }

    private func summaryLine(for state: PayCycleLiveActivityAttributes.ContentState) -> String {
        if state.recommendedCardPaymentTotal == 0, state.recommendedGoalContributionTotal == 0 {
            return "No recommended money moves right now."
        }
        return "Suggested now: cards \(WidgetFormatters.currency(state.recommendedCardPaymentTotal)), goals \(WidgetFormatters.currency(state.recommendedGoalContributionTotal))."
    }
}
