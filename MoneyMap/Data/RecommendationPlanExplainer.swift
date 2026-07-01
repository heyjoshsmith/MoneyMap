//
//  RecommendationPlanExplainer.swift
//  MoneyMap
//
//  Created by Codex on 6/8/26.
//

import Foundation
import FoundationModels

enum RecommendationPlanExplainer {
    static let model = SystemLanguageModel.default

    static func availabilityMessage(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to get an on-device explanation."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing the model on this device."
        @unknown default:
            return "Apple Intelligence is unavailable right now."
        }
    }

    static func explain(
        plan: PaycheckRecommendationPlan,
        digest: RecommendationDigest,
        nextPayday: Date?
    ) async throws -> String {
        let instructions = """
        You explain paycheck plans inside a personal finance app.
        Keep the response under 110 words.
        Use plain language.
        Base the answer only on the provided facts.
        Mention the card strategy, the paycheck strategy, the top card action, and the top goal action when they exist.
        Do not invent numbers, dates, or risks.
        Do not add a disclaimer.
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: prompt(plan: plan, digest: digest, nextPayday: nextPayday))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prompt(
        plan: PaycheckRecommendationPlan,
        digest: RecommendationDigest,
        nextPayday: Date?
    ) -> String {
        let nextPaydayText = nextPayday.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Not set"
        let cardLines = plan.creditCardPayments.prefix(3).map { recommendation in
            let dueDate = recommendation.dueDate.map(MoneyMapFormatters.mediumDateString(for:)) ?? "No due date"
            let apr = recommendation.annualPercentageRate.map {
                $0.formatted(.percent.precision(.fractionLength(1)))
            } ?? "APR not set"
            return "- \(recommendation.billName): pay \(MoneyMapFormatters.currencyString(for: recommendation.recommendedPayment)); minimum \(MoneyMapFormatters.currencyString(for: recommendation.minimumPayment)); due \(dueDate); utilization \(recommendation.utilization.formatted(.percent.precision(.fractionLength(0)))); \(apr); rationale: \(recommendation.rationale)"
        }.joined(separator: "\n")

        let goalLines = plan.goalContributions.prefix(3).map { insight in
            let schedule = insight.isBehindSchedule
                ? "behind by \(MoneyMapFormatters.currencyString(for: insight.shortfallAmount))"
                : "on track"
            return "- \(insight.goalName): contribute \(MoneyMapFormatters.currencyString(for: insight.recommendedContribution)); target per paycheck \(MoneyMapFormatters.currencyString(for: insight.targetPerPaycheck)); \(schedule)"
        }.joined(separator: "\n")

        return """
        Explain this paycheck plan in one short paragraph followed by one short action sentence.

        Planning facts:
        - Next payday: \(nextPaydayText)
        - Available cash: \(MoneyMapFormatters.currencyString(for: plan.totalAvailable))
        - Card strategy: \(plan.payoffStrategy.title)
        - Paycheck strategy: \(plan.allocationStrategy.title)
        - Summary: \(plan.summary)
        - Upcoming bills before payday: \(digest.upcomingBillCount)
        - Behind goals: \(digest.behindGoalCount)
        - Top card action: \(digest.topCardName ?? "None")
        - Top goal action: \(digest.topGoalName ?? "None")
        - Planned for cards: \(MoneyMapFormatters.currencyString(for: digest.suggestedCardPaymentTotal))
        - Planned for goals: \(MoneyMapFormatters.currencyString(for: digest.suggestedGoalContributionTotal))
        - Left unallocated: \(MoneyMapFormatters.currencyString(for: plan.unallocatedCash))

        Card recommendations:
        \(cardLines.isEmpty ? "- None" : cardLines)

        Goal recommendations:
        \(goalLines.isEmpty ? "- None" : goalLines)
        """
    }
}
