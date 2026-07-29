//
//  FinancialPlanningEngineTests.swift
//  MoneyMapTests
//
//  Created by Codex on 4/27/26.
//

import XCTest
@testable import MoneyMap

final class FinancialPlanningEngineTests: XCTestCase {
    func testPaycheckCashResolverUsesManualAmountInManualMode() {
        let account = PlaidAccountSnapshot(
            accountID: "account-1",
            itemID: "item-1",
            institutionName: "Test Bank",
            accountName: "Savings",
            type: "depository",
            currentBalance: 900,
            availableBalance: 850
        )

        let amount = PaycheckCashResolver.availableCash(
            source: .manual,
            manualAmount: 250,
            selectedAccountID: account.accountID,
            accounts: [PaycheckCashAccount(account)]
        )

        XCTAssertEqual(amount, 250)
    }

    func testPaycheckCashResolverUsesSelectedAccountAvailableBalance() {
        let checking = PlaidAccountSnapshot(
            accountID: "checking",
            itemID: "item-1",
            institutionName: "Test Bank",
            accountName: "Checking",
            type: "depository",
            currentBalance: 1200,
            availableBalance: 975
        )
        let savings = PlaidAccountSnapshot(
            accountID: "savings",
            itemID: "item-1",
            institutionName: "Test Bank",
            accountName: "Savings",
            type: "depository",
            currentBalance: 3200,
            availableBalance: 3000
        )

        let amount = PaycheckCashResolver.availableCash(
            source: .linkedAccount,
            manualAmount: 250,
            selectedAccountID: savings.accountID,
            accounts: [PaycheckCashAccount(checking), PaycheckCashAccount(savings)]
        )

        XCTAssertEqual(amount, 3000)
    }

    func testPaycheckCashResolverFallsBackToCurrentBalanceWhenAvailableBalanceIsMissing() {
        let account = PlaidAccountSnapshot(
            accountID: "account-1",
            itemID: "item-1",
            institutionName: "Test Bank",
            accountName: "Checking",
            type: "depository",
            currentBalance: 1200,
            availableBalance: nil
        )

        let amount = PaycheckCashResolver.availableCash(
            source: .linkedAccount,
            manualAmount: 250,
            selectedAccountID: account.accountID,
            accounts: [PaycheckCashAccount(account)]
        )

        XCTAssertEqual(amount, 1200)
    }

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

    func testSavingsBalancePlanAllocatesManualAccountBalanceAcrossGoals() {
        let urgentGoal = Goal(
            "Emergency Fund",
            targetAmount: 1000,
            deadline: Calendar.current.date(byAdding: .day, value: 30, to: .now),
            weight: 2,
            paydaysUntil: 2
        )
        let flexibleGoal = Goal(
            "Vacation",
            targetAmount: 800,
            deadline: Calendar.current.date(byAdding: .day, value: 120, to: .now),
            weight: 1,
            paydaysUntil: 8
        )

        let plan = FinancialPlanningEngine.allocateSavingsBalance(
            balance: 600,
            goals: [urgentGoal, flexibleGoal],
            nextPayday: Calendar.current.date(byAdding: .day, value: 14, to: .now)
        )

        XCTAssertEqual(plan.totalBalance, 600)
        XCTAssertEqual(plan.allocatedTotal, 600, accuracy: 0.01)
        XCTAssertEqual(plan.unallocatedBalance, 0, accuracy: 0.01)
        XCTAssertEqual(plan.allocations.count, 2)
        XCTAssertEqual(plan.allocations.reduce(0) { $0 + $1.allocatedAmount }, 600, accuracy: 0.01)
    }

    func testSavingsBalancePlanTreatsBalanceAsTotalNotNewDeposit() {
        let goal = Goal(
            "Emergency Fund",
            targetAmount: 1000,
            deadline: Calendar.current.date(byAdding: .day, value: 30, to: .now),
            weight: 1,
            paydaysUntil: 2
        )
        goal.amountSaved = 400

        let plan = FinancialPlanningEngine.allocateSavingsBalance(
            balance: 250,
            goals: [goal],
            nextPayday: nil
        )

        XCTAssertEqual(plan.allocations.first?.allocatedAmount, 250)
        XCTAssertEqual(plan.allocations.first?.deltaAmount, -150)
        XCTAssertEqual(plan.allocatedTotal, 250)
    }

    func testSavingsBalancePlanCapsFundedGoalsAndReportsUnallocatedBalance() {
        let firstGoal = Goal("Camera", targetAmount: 100, deadline: nil, weight: 1, paydaysUntil: nil)
        let secondGoal = Goal("Trip", targetAmount: 200, deadline: nil, weight: 1, paydaysUntil: nil)

        let plan = FinancialPlanningEngine.allocateSavingsBalance(
            balance: 500,
            goals: [firstGoal, secondGoal],
            nextPayday: nil
        )

        XCTAssertEqual(plan.allocatedTotal, 300)
        XCTAssertEqual(plan.unallocatedBalance, 200)
        XCTAssertTrue(plan.allocations.allSatisfy { $0.allocatedAmount <= $0.targetAmount })
    }

    func testExtraMoneyPlanMatcherMatchesActiveLinkedAccountDeduction() {
        let createdAt = Date()
        let plan = ExtraMoneyPlan(
            source: .linkedAccount,
            sourceAccountID: "checking-1",
            sourceAccountName: "Checking",
            startingBalance: 1500,
            alreadyAllocated: 0,
            available: 1500,
            plannedCardAmount: 125,
            plannedGoalAmount: 0,
            unallocatedAmount: 1375,
            strategyRaw: PaycheckAllocationStrategy.balanced.rawValue,
            payoffStrategyRaw: CreditCardPayoffStrategy.balanced.rawValue
        )
        plan.createdAt = createdAt
        let item = ExtraMoneyPlanItem(
            planID: plan.id,
            kind: .creditCardPayment,
            targetName: "Rewards Card",
            amount: 125
        )
        let transaction = Transaction(
            transactionDate: createdAt,
            clearingDate: nil,
            transactionDescription: "CARD PAYMENT",
            merchant: "Rewards Card",
            category: "Payment",
            type: "Debit",
            amountUSD: -125,
            purchasedBy: nil,
            plaidTransactionID: "tx-1",
            plaidAccountID: "checking-1"
        )

        let matches = ExtraMoneyPlanMatcher.likelyMatches(
            plans: [plan],
            items: [item],
            transactions: [transaction]
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.transactionID, "tx-1")
        XCTAssertEqual(matches.first?.itemID, item.id)
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
