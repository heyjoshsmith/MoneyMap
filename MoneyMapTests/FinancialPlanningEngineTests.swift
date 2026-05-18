//
//  FinancialPlanningEngineTests.swift
//  MoneyMapTests
//
//  Created by Codex on 4/27/26.
//

import XCTest
@testable import MoneyMap

final class FinancialPlanningEngineTests: XCTestCase {
    func testCreditCardRecommendationPrioritizesDueSoonHighAPRCard() {
        let urgentCard = Bill(
            name: "Urgent Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 2000,
                cardBalance: 1200,
                annualPercentageRate: 0.2499,
                minimumPayment: 75,
                statementBalance: 1200
            )
        )
        let lowerPriorityCard = Bill(
            name: "Lower Priority Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 12, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 8000,
                cardBalance: 900,
                annualPercentageRate: 0.1299,
                minimumPayment: 35,
                statementBalance: 900
            )
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 1000,
            cards: [lowerPriorityCard, urgentCard]
        )

        XCTAssertEqual(recommendations.first?.billName, "Urgent Card")
        XCTAssertTrue(recommendations.first?.recommendedPayment ?? 0 >= 75)
    }

    func testPaycheckPlanFlagsBehindGoalAndAllocatesCash() {
        let deadline = Calendar.current.date(byAdding: .day, value: 20, to: .now) ?? .now
        let behindGoal = Goal("Emergency Fund", targetAmount: 1000, deadline: deadline, weight: 1.5, paydaysUntil: 2)
        behindGoal.amountSaved = 50

        let onTrackGoal = Goal("Vacation", targetAmount: 400, deadline: Calendar.current.date(byAdding: .day, value: 80, to: .now), weight: 1.0, paydaysUntil: 6)
        onTrackGoal.amountSaved = 200

        let plan = FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: 600,
            goals: [behindGoal, onTrackGoal],
            bills: [],
            nextPayday: Calendar.current.date(byAdding: .day, value: 14, to: .now)
        )

        XCTAssertEqual(plan.creditCardPayments.count, 0)
        XCTAssertFalse(plan.goalContributions.isEmpty)
        XCTAssertEqual(plan.goalContributions.first?.goalName, "Emergency Fund")
        XCTAssertTrue(plan.goalContributions.first?.isBehindSchedule ?? false)
        XCTAssertGreaterThan(plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }, 0)
    }

    func testGoalProgressInsightsStillFlagBehindGoalWithoutAvailableCash() {
        let nextPayday = Calendar.current.date(byAdding: .day, value: 14, to: .now)
        let goal = Goal(
            "Emergency Fund",
            targetAmount: 1200,
            deadline: Calendar.current.date(byAdding: .day, value: 28, to: .now),
            weight: 1.0,
            paydaysUntil: 2
        )
        goal.amountSaved = 100
        goal.createdDate = Calendar.current.date(byAdding: .day, value: -20, to: .now) ?? .now

        let insights = FinancialPlanningEngine.goalProgressInsights(goals: [goal], nextPayday: nextPayday)

        XCTAssertEqual(insights.first?.goalName, "Emergency Fund")
        XCTAssertTrue(insights.first?.isBehindSchedule ?? false)
        XCTAssertGreaterThan(insights.first?.shortfallAmount ?? 0, 0)
    }

    func testSnowballStrategyPrioritizesSmallestBalance() {
        let smallBalance = Bill(
            name: "Small Balance",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 10, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5000,
                cardBalance: 200,
                annualPercentageRate: 0.1299,
                minimumPayment: 25,
                statementBalance: 200
            )
        )
        let largeBalance = Bill(
            name: "Large Balance",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 10, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 7000,
                cardBalance: 1800,
                annualPercentageRate: 0.2499,
                minimumPayment: 70,
                statementBalance: 1800
            )
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 300,
            cards: [largeBalance, smallBalance],
            strategy: .snowball
        )

        XCTAssertEqual(recommendations.first?.billName, "Small Balance")
    }
}
