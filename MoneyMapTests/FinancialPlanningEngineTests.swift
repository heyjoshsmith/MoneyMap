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

    func testPaycheckCashAccountAllowsCheckingAccountNamedForCreditCards() {
        let account = PlaidAccountSnapshot(
            accountID: "credit-card-payoff",
            itemID: "item-1",
            institutionName: "OnePay",
            accountName: "Credit Cards",
            type: "depository",
            subtype: "checking",
            currentBalance: 2403.05,
            availableBalance: 2403.05
        )

        XCTAssertTrue(MoneyMapPlanningStore.isEligiblePaycheckCashAccount(account))
    }

    func testCardOwnedTransactionCanConnectToBillWithoutLeavingCard() {
        let appleCard = Bill(
            name: "Apple Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 20, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )
        let internetBill = Bill(
            name: "Xfinity",
            amount: 94.12,
            dueDate: .now,
            category: .internet,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )
        let transaction = Transaction(
            transactionDate: .now,
            clearingDate: nil,
            transactionDescription: "Xfinity mobile",
            merchant: "Xfinity",
            category: "Internet",
            type: "Purchase",
            amountUSD: 94.12,
            purchasedBy: "Josh",
            creditCard: appleCard,
            linkedBillID: internetBill.id
        )

        let connected = BillPaymentMatcher.connectedTransactions(for: internetBill, in: [transaction])

        XCTAssertEqual(connected.count, 1)
        XCTAssertEqual(transaction.creditCard?.id, appleCard.id)
        XCTAssertTrue(BillPaymentMatcher.refreshStatuses(for: [internetBill], transactions: [transaction]))
        XCTAssertEqual(internetBill.status, .paid)
        XCTAssertEqual(transaction.creditCard?.id, appleCard.id)
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

    func testCreditCardRecommendationSpreadsLimitedCashAcrossUrgentCards() {
        let firstDueCard = Bill(
            name: "First Due Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5000,
                cardBalance: 900,
                annualPercentageRate: 0.1899,
                minimumPayment: 240,
                statementBalance: 900
            )
        )
        let higherBalanceCard = Bill(
            name: "Higher Balance Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 8000,
                cardBalance: 3600,
                annualPercentageRate: 0.2199,
                minimumPayment: 45,
                statementBalance: 3600
            )
        )
        let thirdUrgentCard = Bill(
            name: "Third Urgent Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 6000,
                cardBalance: 1800,
                annualPercentageRate: 0.1999,
                minimumPayment: 55,
                statementBalance: 1800
            )
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 200,
            cards: [firstDueCard, higherBalanceCard, thirdUrgentCard],
            strategy: .balanced
        )

        XCTAssertEqual(recommendations.count, 3)
        XCTAssertEqual(recommendations.reduce(0) { $0 + $1.recommendedPayment }, 200, accuracy: 0.01)
        XCTAssertTrue(recommendations.allSatisfy { $0.recommendedPayment > 0 })
        XCTAssertTrue(recommendations.contains { $0.billName == "Higher Balance Card" })
    }

    func testCreditCardRecommendationIncludesDueCardWithOnlyPaymentAmount() {
        let detailedCard = Bill(
            name: "Detailed Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 4, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5000,
                cardBalance: 1200,
                annualPercentageRate: 0.1899,
                minimumPayment: 60,
                statementBalance: 1200
            )
        )
        let paymentOnlyCard = Bill(
            name: "Payment Only Card",
            amount: 95,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 300,
            cards: [detailedCard, paymentOnlyCard],
            strategy: .balanced
        )

        let paymentOnlyRecommendation = recommendations.first { $0.billName == "Payment Only Card" }
        XCTAssertNotNil(paymentOnlyRecommendation)
        XCTAssertEqual(paymentOnlyRecommendation?.recommendedPayment ?? 0, 95, accuracy: 0.01)
        XCTAssertEqual(paymentOnlyRecommendation?.minimumPayment ?? 0, 95, accuracy: 0.01)
    }

    func testCreditCardRecommendationTreatsNegativeCardBalanceAsDebt() {
        let negativeBalanceCard = Bill(
            name: "Negative Balance Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5000,
                cardBalance: -1250,
                annualPercentageRate: 0.1999,
                minimumPayment: 75,
                statementBalance: -1250
            )
        )
        let positiveBalanceCard = Bill(
            name: "Positive Balance Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 6000,
                cardBalance: 1800,
                annualPercentageRate: 0.1899,
                minimumPayment: 80,
                statementBalance: 1800
            )
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 500,
            cards: [negativeBalanceCard, positiveBalanceCard],
            strategy: .balanced
        )

        XCTAssertTrue(recommendations.contains { $0.billName == "Negative Balance Card" })
        XCTAssertTrue(recommendations.contains { $0.billName == "Positive Balance Card" })
    }

    func testBalancedStrategyUsesBalancePressureWhenUrgencyTies() {
        let sharedDueDate = Calendar.current.date(byAdding: .day, value: 2, to: .now)
        let smallerBalanceCard = Bill(
            name: "Smaller Balance Card",
            amount: 0,
            dueDate: sharedDueDate,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 2000,
                cardBalance: 500,
                annualPercentageRate: 0.1999,
                minimumPayment: 50,
                statementBalance: 500
            )
        )
        let largerBalanceCard = Bill(
            name: "Larger Balance Card",
            amount: 0,
            dueDate: sharedDueDate,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 16000,
                cardBalance: 4000,
                annualPercentageRate: 0.1999,
                minimumPayment: 50,
                statementBalance: 4000
            )
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 300,
            cards: [smallerBalanceCard, largerBalanceCard],
            strategy: .balanced
        )

        XCTAssertEqual(recommendations.first?.billName, "Larger Balance Card")
        XCTAssertGreaterThan(
            recommendations.first?.recommendedPayment ?? 0,
            recommendations.last?.recommendedPayment ?? 0
        )
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

    func testBalancedPaycheckPlanTargetsCardBalancesBeforeAheadGoals() {
        let firstCard = Bill(
            name: "Rewards Card",
            amount: 45,
            dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5000,
                cardBalance: 1800,
                annualPercentageRate: 0.1999,
                minimumPayment: 45,
                statementBalance: nil
            )
        )
        let secondCard = Bill(
            name: "Store Card",
            amount: 35,
            dueDate: Calendar.current.date(byAdding: .day, value: 5, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 3000,
                cardBalance: 600,
                annualPercentageRate: 0.2499,
                minimumPayment: 35,
                statementBalance: nil
            )
        )
        let aheadGoal = Goal(
            "Vacation",
            targetAmount: 2000,
            deadline: Calendar.current.date(byAdding: .day, value: 180, to: .now),
            weight: 1,
            paydaysUntil: 12
        )
        aheadGoal.amountSaved = 1200

        let plan = FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: 1000,
            goals: [aheadGoal],
            bills: [firstCard, secondCard],
            nextPayday: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            allocationStrategy: .balanced,
            payoffStrategy: .balanced
        )

        XCTAssertEqual(plan.creditCardPayments.count, 2)
        XCTAssertEqual(plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }, 1000, accuracy: 0.01)
        XCTAssertEqual(plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }, 0, accuracy: 0.01)
        XCTAssertEqual(plan.unallocatedCash, 0, accuracy: 0.01)
    }

    func testBalancedPaycheckPlanUsesLinkedCreditAccountBalanceOverStaleBillBalance() {
        let linkedCard = Bill(
            name: "Apple Card",
            amount: 16,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5000,
                cardBalance: 16,
                annualPercentageRate: 0.1999,
                minimumPayment: 16,
                statementBalance: nil
            ),
            plaidAccountID: "apple-card"
        )
        let aheadGoal = Goal(
            "Phone",
            targetAmount: 1200,
            deadline: Calendar.current.date(byAdding: .day, value: 180, to: .now),
            weight: 1,
            paydaysUntil: 12
        )
        aheadGoal.amountSaved = 900

        let plan = FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: 1000,
            goals: [aheadGoal],
            bills: [linkedCard],
            nextPayday: Calendar.current.date(byAdding: .day, value: 14, to: .now),
            creditAccounts: [
                CreditCardPlanningAccount(
                    accountID: "apple-card",
                    currentBalance: 1228.75,
                    availableBalance: 3771.25
                )
            ],
            allocationStrategy: .balanced,
            payoffStrategy: .balanced
        )

        XCTAssertEqual(plan.creditCardPayments.first?.recommendedPayment ?? 0, 1000, accuracy: 0.01)
        XCTAssertEqual(plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }, 0, accuracy: 0.01)
    }

    func testBalancedPayoffDoesNotFullyProtectUnknownOverdueBalance() {
        let overdueLowUtilizationCard = Bill(
            name: "American Express",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 19_789.70,
                cardBalance: 1_978.97,
                annualPercentageRate: nil,
                minimumPayment: nil,
                statementBalance: nil
            )
        )
        let higherBalanceCard = Bill(
            name: "Apple Card",
            amount: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: 30, to: .now),
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 21_053.33,
                cardBalance: 6_316,
                annualPercentageRate: nil,
                minimumPayment: nil,
                statementBalance: nil
            )
        )

        let recommendations = FinancialPlanningEngine.recommendCreditCardPayments(
            availableCash: 2_224.15,
            cards: [overdueLowUtilizationCard, higherBalanceCard],
            strategy: .balanced
        )

        let amexPayment = recommendations.first { $0.billName == "American Express" }?.recommendedPayment ?? 0
        let applePayment = recommendations.first { $0.billName == "Apple Card" }?.recommendedPayment ?? 0

        XCTAssertGreaterThan(applePayment, amexPayment)
        XCTAssertLessThan(amexPayment, 1_978.97)
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

    func testPendingPlanSettlementWaitsForPostedBankDebit() {
        let createdAt = Date()
        let card = Bill(
            name: "Rewards Card",
            amount: 75,
            dueDate: createdAt,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5_000,
                cardBalance: 600,
                minimumPayment: 75
            )
        )
        let plan = ExtraMoneyPlan(
            source: .linkedAccount,
            sourceAccountID: "checking-1",
            sourceAccountName: "Checking",
            startingBalance: 600,
            alreadyAllocated: 0,
            available: 125,
            plannedCardAmount: 125,
            plannedGoalAmount: 0,
            unallocatedAmount: 0,
            strategyRaw: PaycheckAllocationStrategy.balanced.rawValue,
            payoffStrategyRaw: CreditCardPayoffStrategy.balanced.rawValue,
            appliedAt: createdAt
        )
        plan.createdAt = createdAt
        let item = ExtraMoneyPlanItem(
            planID: plan.id,
            kind: .creditCardPayment,
            targetID: card.id,
            targetName: "Rewards Card",
            amount: 125
        )
        let pendingTransaction = Transaction(
            transactionDate: createdAt,
            clearingDate: nil,
            transactionDescription: "CARD PAYMENT",
            merchant: "Rewards Card",
            category: "Payment",
            type: "Pending",
            amountUSD: -125,
            purchasedBy: nil,
            plaidTransactionID: "tx-pending",
            plaidAccountID: "checking-1",
            plaidIsPending: true
        )

        let summary = ExtraMoneyPlanSettlementService.settlePendingPayments(
            plans: [plan],
            items: [item],
            bills: [card],
            transactions: [pendingTransaction]
        )

        XCTAssertEqual(summary.paidCardCount, 0)
        XCTAssertNil(item.matchedTransactionIDText)
        XCTAssertEqual(card.creditCardDetails?.cardBalance, 600)
        XCTAssertEqual(plan.status, .active)
    }

    func testPendingPlanSettlementAppliesPostedMatchingCardPayment() {
        let createdAt = Date()
        let card = Bill(
            name: "Rewards Card",
            amount: 75,
            dueDate: createdAt,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5_000,
                cardBalance: 600,
                minimumPayment: 75
            )
        )
        let plan = ExtraMoneyPlan(
            source: .linkedAccount,
            sourceAccountID: "checking-1",
            sourceAccountName: "Checking",
            startingBalance: 600,
            alreadyAllocated: 0,
            available: 125,
            plannedCardAmount: 125,
            plannedGoalAmount: 0,
            unallocatedAmount: 0,
            strategyRaw: PaycheckAllocationStrategy.balanced.rawValue,
            payoffStrategyRaw: CreditCardPayoffStrategy.balanced.rawValue,
            appliedAt: createdAt
        )
        plan.createdAt = createdAt
        let item = ExtraMoneyPlanItem(
            planID: plan.id,
            kind: .creditCardPayment,
            targetID: card.id,
            targetName: "Rewards Card",
            amount: 125
        )
        let transaction = Transaction(
            transactionDate: createdAt,
            clearingDate: nil,
            transactionDescription: "CARD PAYMENT",
            merchant: "Rewards Card",
            category: "Payment",
            type: "Posted",
            amountUSD: -125,
            purchasedBy: nil,
            plaidTransactionID: "tx-posted",
            plaidAccountID: "checking-1",
            plaidIsPending: false
        )

        let summary = ExtraMoneyPlanSettlementService.settlePendingPayments(
            plans: [plan],
            items: [item],
            bills: [card],
            transactions: [transaction],
            now: createdAt
        )

        XCTAssertEqual(summary.paidCardCount, 1)
        XCTAssertEqual(summary.completedPlanCount, 1)
        XCTAssertEqual(item.matchedTransactionIDText, "tx-posted")
        XCTAssertEqual(item.matchedAt, createdAt)
        XCTAssertEqual(card.creditCardDetails?.cardBalance, 475)
        XCTAssertEqual(card.status, .paid)
        XCTAssertEqual(plan.status, .completed)
        XCTAssertEqual(plan.completedAt, createdAt)
    }

    func testUnappliedSavedPlanDoesNotSettleFromBankDebit() {
        let createdAt = Date()
        let card = Bill(
            name: "Rewards Card",
            amount: 75,
            dueDate: createdAt,
            category: .creditCard,
            recurrenceInterval: 1,
            recurrenceUnit: .month,
            creditCardDetails: CreditCardDetails(
                creditLimit: 5_000,
                cardBalance: 600,
                minimumPayment: 75
            )
        )
        let plan = ExtraMoneyPlan(
            source: .linkedAccount,
            sourceAccountID: "checking-1",
            sourceAccountName: "Checking",
            startingBalance: 600,
            alreadyAllocated: 0,
            available: 125,
            plannedCardAmount: 125,
            plannedGoalAmount: 0,
            unallocatedAmount: 0,
            strategyRaw: PaycheckAllocationStrategy.balanced.rawValue,
            payoffStrategyRaw: CreditCardPayoffStrategy.balanced.rawValue
        )
        plan.createdAt = createdAt
        let item = ExtraMoneyPlanItem(
            planID: plan.id,
            kind: .creditCardPayment,
            targetID: card.id,
            targetName: "Rewards Card",
            amount: 125
        )
        let transaction = Transaction(
            transactionDate: createdAt,
            clearingDate: nil,
            transactionDescription: "CARD PAYMENT",
            merchant: "Rewards Card",
            category: "Payment",
            type: "Posted",
            amountUSD: -125,
            purchasedBy: nil,
            plaidTransactionID: "tx-posted",
            plaidAccountID: "checking-1",
            plaidIsPending: false
        )

        let summary = ExtraMoneyPlanSettlementService.settlePendingPayments(
            plans: [plan],
            items: [item],
            bills: [card],
            transactions: [transaction],
            now: createdAt
        )

        XCTAssertEqual(summary.paidCardCount, 0)
        XCTAssertNil(item.matchedTransactionIDText)
        XCTAssertEqual(card.creditCardDetails?.cardBalance, 600)
        XCTAssertEqual(plan.status, .active)
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
