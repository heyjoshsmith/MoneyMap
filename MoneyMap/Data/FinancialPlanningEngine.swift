//
//  FinancialPlanningEngine.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import Foundation

struct GoalSavingInsight: Equatable {
    let goalID: UUID
    let goalName: String
    let recommendedContribution: Double
    let isBehindSchedule: Bool
    let shortfallAmount: Double
    let targetPerPaycheck: Double
}

struct CreditCardPaymentRecommendation: Equatable {
    let billID: UUID
    let billName: String
    let recommendedPayment: Double
    let activeBalance: Double
    let rationale: String
    let dueDate: Date?
    let utilization: Double
    let annualPercentageRate: Double?
    let minimumPayment: Double
}

struct PaycheckRecommendationPlan: Equatable {
    let totalAvailable: Double
    let creditCardPayments: [CreditCardPaymentRecommendation]
    let goalContributions: [GoalSavingInsight]
    let unallocatedCash: Double
    let payoffStrategy: CreditCardPayoffStrategy
    let allocationStrategy: PaycheckAllocationStrategy
    let summary: String
}

struct RecommendationScenario: Identifiable, Equatable {
    let id: String
    let title: String
    let availableCash: Double
    let plan: PaycheckRecommendationPlan
}

struct RecommendationDigest: Equatable {
    let nextPayday: Date?
    let upcomingBillCount: Int
    let behindGoalCount: Int
    let suggestedCardPaymentTotal: Double
    let suggestedGoalContributionTotal: Double
    let topCardName: String?
    let topGoalName: String?
}

struct CreditCardPlanningAccount: Equatable {
    let accountID: String
    let currentBalance: Double?
    let availableBalance: Double?

    var balanceAmount: Double {
        abs(currentBalance ?? 0)
    }
}

struct SavingsBalanceGoalAllocation: Equatable {
    let goalID: UUID
    let goalName: String
    let targetAmount: Double
    let currentSavedAmount: Double
    let allocatedAmount: Double
    let deltaAmount: Double
    let isBehindSchedule: Bool
    let targetPerPaycheck: Double

    var remainingAfterAllocation: Double {
        max(0, targetAmount - allocatedAmount)
    }
}

struct SavingsBalancePlan: Equatable {
    let totalBalance: Double
    let allocations: [SavingsBalanceGoalAllocation]
    let allocatedTotal: Double
    let unallocatedBalance: Double
}

enum FinancialPlanningEngine {
    private struct CreditCardPaymentCandidate {
        let bill: Bill
        let balance: Double
        let minimumPayment: Double
        let utilization: Double
        let annualPercentageRate: Double?
        let protectedTarget: Double
        let preferredTarget: Double
        let priorityScore: Double
        let protectionScore: Double
    }

    static func recommendPaycheckPlan(
        availableCash: Double,
        goals: [Goal],
        bills: [Bill],
        nextPayday: Date?,
        creditAccounts: [CreditCardPlanningAccount] = [],
        allocationStrategy: PaycheckAllocationStrategy = .balanced,
        payoffStrategy: CreditCardPayoffStrategy = .balanced
    ) -> PaycheckRecommendationPlan {
        let roundedAvailable = roundedToCents(max(availableCash, 0))
        let cards = bills.filter { $0.category == .creditCard }
        let creditAccountsByID = Dictionary(uniqueKeysWithValues: creditAccounts.map { ($0.accountID, $0) })

        guard roundedAvailable > 0 else {
            return PaycheckRecommendationPlan(
                totalAvailable: 0,
                creditCardPayments: [],
                goalContributions: recommendGoalContributions(
                    availableCash: 0,
                    goals: goals,
                    nextPayday: nextPayday
                ),
                unallocatedCash: 0,
                payoffStrategy: payoffStrategy,
                allocationStrategy: allocationStrategy,
                summary: "No cash is available to allocate right now."
            )
        }

        let cardPayoffNeed = roundedToCents(cards.reduce(0) { total, bill in
            total + effectiveCardBalance(for: bill, creditAccountsByID: creditAccountsByID)
        })
        let minimumCardCoverage = roundedToCents(cards.reduce(0) { total, bill in
            let balance = effectiveCardBalance(for: bill, creditAccountsByID: creditAccountsByID)
            return total + min(effectiveMinimumPayment(for: bill), balance)
        })
        let protectedGoalBudget = protectedGoalBudget(
            availableCash: roundedAvailable,
            goals: goals,
            nextPayday: nextPayday,
            allocationStrategy: allocationStrategy,
            hasCardDebt: cardPayoffNeed > 0
        )
        let preferredCardBudget = roundedToCents(roundedAvailable * allocationRatio(for: allocationStrategy))
        let cardBudget: Double
        if cardPayoffNeed <= 0 {
            cardBudget = 0
        } else {
            switch allocationStrategy {
            case .balanced:
                cardBudget = roundedToCents(min(
                    roundedAvailable,
                    max(minimumCardCoverage, min(cardPayoffNeed, roundedAvailable - protectedGoalBudget))
                ))
            case .debtFirst:
                cardBudget = roundedToCents(min(roundedAvailable, max(minimumCardCoverage, cardPayoffNeed)))
            case .goalsFirst:
                cardBudget = roundedToCents(min(roundedAvailable, max(minimumCardCoverage, preferredCardBudget)))
            }
        }
        let goalBudget = roundedToCents(max(0, roundedAvailable - cardBudget))

        let cardPayments = recommendCreditCardPayments(
            availableCash: cardBudget,
            cards: cards,
            nextPayday: nextPayday,
            creditAccounts: creditAccounts,
            strategy: payoffStrategy
        )
        let spentOnCards = roundedToCents(cardPayments.reduce(0) { $0 + $1.recommendedPayment })
        let cardRemainder = roundedToCents(max(0, cardBudget - spentOnCards))
        let hasRemainingCardDebt = roundedToCents(max(0, cardPayoffNeed - spentOnCards)) > 0
        let includeOnTrackGoals = !hasRemainingCardDebt || allocationStrategy == .goalsFirst

        let goalContributions = recommendGoalContributions(
            availableCash: goalBudget + cardRemainder,
            goals: goals,
            nextPayday: nextPayday,
            includeOnTrackGoals: includeOnTrackGoals
        )
        let spentOnGoals = roundedToCents(goalContributions.reduce(0) { $0 + $1.recommendedContribution })
        let unallocatedCash = roundedToCents(max(0, roundedAvailable - spentOnCards - spentOnGoals))

        return PaycheckRecommendationPlan(
            totalAvailable: roundedAvailable,
            creditCardPayments: cardPayments,
            goalContributions: goalContributions,
            unallocatedCash: unallocatedCash,
            payoffStrategy: payoffStrategy,
            allocationStrategy: allocationStrategy,
            summary: summary(
                for: roundedAvailable,
                cardPayments: cardPayments,
                goalContributions: goalContributions,
                unallocatedCash: unallocatedCash
            )
        )
    }

    static func recommendCreditCardPayments(
        availableCash: Double,
        cards: [Bill],
        nextPayday: Date? = nil,
        creditAccounts: [CreditCardPlanningAccount] = [],
        strategy: CreditCardPayoffStrategy = .balanced
    ) -> [CreditCardPaymentRecommendation] {
        var remainingCash = roundedToCents(max(availableCash, 0))
        guard remainingCash > 0 else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        let planningHorizon = Calendar.current.startOfDay(
            for: nextPayday ?? Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today
        )
        let creditAccountsByID = Dictionary(uniqueKeysWithValues: creditAccounts.map { ($0.accountID, $0) })

        let prioritizedCards = cards
            .filter { effectiveCardBalance(for: $0, creditAccountsByID: creditAccountsByID) > 0 }
            .sorted { lhs, rhs in
                let lhsScore = cardPriorityScore(for: lhs, nextPayday: nextPayday, creditAccountsByID: creditAccountsByID, strategy: strategy)
                let rhsScore = cardPriorityScore(for: rhs, nextPayday: nextPayday, creditAccountsByID: creditAccountsByID, strategy: strategy)
                if lhsScore == rhsScore {
                    return Bill.byDate(lhs: lhs, rhs: rhs)
                }
                return lhsScore > rhsScore
            }

        var paymentsByID: [UUID: Double] = [:]
        let candidates: [CreditCardPaymentCandidate] = prioritizedCards.compactMap { bill in
            let details = bill.creditCardDetails
            let linkedAccount = linkedCreditAccount(for: bill, creditAccountsByID: creditAccountsByID)
            let balance = effectiveCardBalance(for: bill, creditAccountsByID: creditAccountsByID)
            guard balance > 0 else { return nil }

            let minimumPayment = min(effectiveMinimumPayment(for: bill), balance)
            let creditLimit = effectiveCreditLimit(details: details, linkedAccount: linkedAccount, balance: balance)
            let utilization = creditLimit > 0 ? balance / creditLimit : 0
            let utilizationTarget = max(0, balance - (creditLimit * 0.3))
            let statementTarget = statementTarget(for: bill, balance: balance)
            let duePaymentTarget = duePaymentTarget(for: bill, balance: balance)
            let dueDay = bill.dueDate.map { Calendar.current.startOfDay(for: $0) }
            let isMarkedPaid = bill.datePaid != nil || bill.status == .paid
            let isOverdue = dueDay.map { $0 < today } ?? false
            let isDueBeforeNextPayday = dueDay.map { $0 <= planningHorizon } ?? false
            let protectedBase: Double

            if isOverdue && !isMarkedPaid {
                protectedBase = max(minimumPayment, duePaymentTarget)
            } else if isDueBeforeNextPayday && !isMarkedPaid {
                protectedBase = minimumPayment
            } else {
                protectedBase = 0
            }

            let preferredTarget: Double

            switch strategy {
            case .balanced:
                preferredTarget = balance
            case .avalanche:
                preferredTarget = balance
            case .snowball:
                preferredTarget = balance
            case .dueDate:
                preferredTarget = balance
            case .utilization:
                preferredTarget = max(protectedBase, minimumPayment, utilizationTarget)
            case .statementBalance:
                preferredTarget = max(protectedBase, minimumPayment, statementTarget)
            }

            let priorityScore = max(cardPriorityScore(for: bill, nextPayday: nextPayday, creditAccountsByID: creditAccountsByID, strategy: strategy), 0.1)
            return CreditCardPaymentCandidate(
                bill: bill,
                balance: balance,
                minimumPayment: minimumPayment,
                utilization: utilization,
                annualPercentageRate: details?.annualPercentageRate,
                protectedTarget: roundedToCents(min(balance, protectedBase)),
                preferredTarget: roundedToCents(min(balance, preferredTarget)),
                priorityScore: priorityScore,
                protectionScore: max(priorityScore + largeBalanceScore(for: balance), 0.1)
            )
        }

        // First, protect every urgent card before allowing extra payoff to crowd out peers.
        allocateCreditCardCash(
            remainingCash: &remainingCash,
            candidates: candidates.filter { $0.protectedTarget > 0 },
            paymentsByID: &paymentsByID,
            target: \.protectedTarget,
            weight: \.protectionScore
        )

        // Then spread any remaining cash across multiple cards based on priority and need.
        allocateCreditCardCash(
            remainingCash: &remainingCash,
            candidates: candidates,
            paymentsByID: &paymentsByID,
            target: \.preferredTarget,
            weight: \.priorityScore
        )

        var recommendations: [CreditCardPaymentRecommendation] = []
        for candidate in candidates {
            let payment = roundedToCents(min(paymentsByID[candidate.bill.id] ?? 0, candidate.balance))
            guard payment > 0 else { continue }

            recommendations.append(
                CreditCardPaymentRecommendation(
                    billID: candidate.bill.id,
                    billName: candidate.bill.name ?? "Card",
                    recommendedPayment: payment,
                    activeBalance: candidate.balance,
                    rationale: rationale(for: candidate.bill, nextPayday: nextPayday, strategy: strategy),
                    dueDate: candidate.bill.dueDate,
                    utilization: candidate.utilization,
                    annualPercentageRate: candidate.annualPercentageRate,
                    minimumPayment: candidate.minimumPayment
                )
            )
        }

        return recommendations
    }

    static func recommendGoalContributions(
        availableCash: Double,
        goals: [Goal],
        nextPayday: Date?,
        includeOnTrackGoals: Bool = true
    ) -> [GoalSavingInsight] {
        let totalAvailable = roundedToCents(max(availableCash, 0))
        let progressInsights = goalProgressInsights(goals: goals, nextPayday: nextPayday)
        let eligibleInsights = includeOnTrackGoals ? progressInsights : progressInsights.filter(\.isBehindSchedule)

        guard totalAvailable > 0 else {
            return eligibleInsights.map { insight in
                GoalSavingInsight(
                    goalID: insight.goalID,
                    goalName: insight.goalName,
                    recommendedContribution: 0,
                    isBehindSchedule: insight.isBehindSchedule,
                    shortfallAmount: insight.shortfallAmount,
                    targetPerPaycheck: insight.targetPerPaycheck
                )
            }
        }

        let weightedGoals: [(GoalSavingInsight, Double)] = eligibleInsights.compactMap { insight in
            guard let goal = goals.first(where: { $0.id == insight.goalID }), goal.remainingAmount > 0 else { return nil }
            let urgency = goal.daysUntilDeadline > 0 ? 1.0 / Double(goal.daysUntilDeadline) : 1.0
            let behindWeight = insight.isBehindSchedule ? 1.5 : 0
            return (insight, goal.weight + urgency + behindWeight)
        }

        let totalWeight = weightedGoals.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return [] }

        return weightedGoals.compactMap { insight, weight in
            guard let goal = goals.first(where: { $0.id == insight.goalID }) else { return nil }
            let suggested = roundedToCents(min(goal.remainingAmount, totalAvailable * (weight / totalWeight)))
            return GoalSavingInsight(
                goalID: insight.goalID,
                goalName: insight.goalName,
                recommendedContribution: suggested,
                isBehindSchedule: insight.isBehindSchedule,
                shortfallAmount: roundedToCents(max(0, insight.shortfallAmount - suggested)),
                targetPerPaycheck: insight.targetPerPaycheck
            )
        }
        .filter { $0.recommendedContribution > 0 || $0.isBehindSchedule }
        .sorted(by: goalInsightSort)
    }

    static func goalProgressInsights(goals: [Goal], nextPayday: Date?) -> [GoalSavingInsight] {
        goals.compactMap { goal in
            guard goal.remainingAmount > 0 else { return nil }
            let paydaysRemaining = goal.deadline.map { paydaysUntil(deadline: $0, nextPayday: nextPayday) } ?? 1
            let targetPerPaycheck = roundedToCents(goal.amountPerPaycheck ?? (goal.remainingAmount / Double(max(paydaysRemaining, 1))))
            let expectedSavedByNow = targetPerPaycheck * Double(max(paydaysElapsed(for: goal, nextPayday: nextPayday), 1))
            let shortfallAmount = roundedToCents(max(0, expectedSavedByNow - goal.amountSaved))
            return GoalSavingInsight(
                goalID: goal.id,
                goalName: goal.name ?? "Goal",
                recommendedContribution: roundedToCents(min(goal.remainingAmount, targetPerPaycheck)),
                isBehindSchedule: shortfallAmount > 0,
                shortfallAmount: shortfallAmount,
                targetPerPaycheck: targetPerPaycheck
            )
        }
        .sorted(by: goalInsightSort)
    }

    static func allocateSavingsBalance(
        balance: Double,
        goals: [Goal],
        nextPayday: Date?
    ) -> SavingsBalancePlan {
        let totalBalance = roundedToCents(max(balance, 0))
        let candidates = goals.compactMap { goal -> Goal? in
            guard (goal.targetAmount ?? 0) > 0 else { return nil }
            return goal
        }

        guard !candidates.isEmpty else {
            return SavingsBalancePlan(
                totalBalance: totalBalance,
                allocations: [],
                allocatedTotal: 0,
                unallocatedBalance: totalBalance
            )
        }

        let insightsByID = Dictionary(
            uniqueKeysWithValues: goalProgressInsights(goals: goals, nextPayday: nextPayday).map { ($0.goalID, $0) }
        )
        var remainingBalance = totalBalance
        var allocationsByGoalID: [UUID: Double] = [:]

        while remainingBalance > 0 {
            let openGoals = candidates.compactMap { goal -> (goal: Goal, capacity: Double, weight: Double)? in
                let currentAllocation = allocationsByGoalID[goal.id] ?? 0
                let capacity = roundedToCents(max(0, (goal.targetAmount ?? 0) - currentAllocation))
                guard capacity > 0 else { return nil }
                return (
                    goal,
                    capacity,
                    savingsBalanceWeight(for: goal, insight: insightsByID[goal.id])
                )
            }

            guard !openGoals.isEmpty else { break }

            let passBalance = remainingBalance
            let totalWeight = openGoals.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { break }

            var allocatedThisPass = 0.0

            for item in openGoals where remainingBalance > 0 {
                let weightedShare = roundedToCents(passBalance * (item.weight / totalWeight))
                let proposed = max(weightedShare, min(remainingBalance, 0.01))
                let amount = roundedToCents(min(remainingBalance, item.capacity, proposed))
                guard amount > 0 else { continue }
                allocationsByGoalID[item.goal.id, default: 0] = roundedToCents((allocationsByGoalID[item.goal.id] ?? 0) + amount)
                remainingBalance = roundedToCents(max(0, remainingBalance - amount))
                allocatedThisPass = roundedToCents(allocatedThisPass + amount)
            }

            if allocatedThisPass == 0 {
                break
            }
        }

        let allocations = candidates.compactMap { goal -> SavingsBalanceGoalAllocation? in
            guard let targetAmount = goal.targetAmount, targetAmount > 0 else { return nil }
            let allocatedAmount = roundedToCents(min(targetAmount, allocationsByGoalID[goal.id] ?? 0))
            let insight = insightsByID[goal.id]
            return SavingsBalanceGoalAllocation(
                goalID: goal.id,
                goalName: goal.name ?? "Goal",
                targetAmount: roundedToCents(targetAmount),
                currentSavedAmount: roundedToCents(goal.amountSaved),
                allocatedAmount: allocatedAmount,
                deltaAmount: roundedToCents(allocatedAmount - goal.amountSaved),
                isBehindSchedule: insight?.isBehindSchedule ?? false,
                targetPerPaycheck: insight?.targetPerPaycheck ?? roundedToCents(goal.amountPerPaycheck ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isBehindSchedule != rhs.isBehindSchedule {
                return lhs.isBehindSchedule && !rhs.isBehindSchedule
            }
            if lhs.allocatedAmount != rhs.allocatedAmount {
                return lhs.allocatedAmount > rhs.allocatedAmount
            }
            return lhs.goalName.localizedStandardCompare(rhs.goalName) == .orderedAscending
        }

        let allocatedTotal = roundedToCents(allocations.reduce(0) { $0 + $1.allocatedAmount })
        return SavingsBalancePlan(
            totalBalance: totalBalance,
            allocations: allocations,
            allocatedTotal: allocatedTotal,
            unallocatedBalance: roundedToCents(max(0, totalBalance - allocatedTotal))
        )
    }

    static func scenarioPlans(
        baseAvailableCash: Double,
        goals: [Goal],
        bills: [Bill],
        nextPayday: Date?,
        creditAccounts: [CreditCardPlanningAccount] = [],
        allocationStrategy: PaycheckAllocationStrategy = .balanced,
        payoffStrategy: CreditCardPayoffStrategy = .balanced
    ) -> [RecommendationScenario] {
        let base = roundedToCents(max(baseAvailableCash, 0))
        let scenarios: [(String, Double)] = [
            ("Lean", roundedToCents(max(0, base * 0.75))),
            ("Planned", base),
            ("Stretch", roundedToCents(base * 1.25))
        ]

        return scenarios.map { title, amount in
            RecommendationScenario(
                id: "\(title.lowercased())-\(amount)",
                title: title,
                availableCash: amount,
                plan: recommendPaycheckPlan(
                    availableCash: amount,
                    goals: goals,
                    bills: bills,
                    nextPayday: nextPayday,
                    creditAccounts: creditAccounts,
                    allocationStrategy: allocationStrategy,
                    payoffStrategy: payoffStrategy
                )
            )
        }
    }

    static func digest(
        availableCash: Double,
        goals: [Goal],
        bills: [Bill],
        nextPayday: Date?,
        creditAccounts: [CreditCardPlanningAccount] = [],
        allocationStrategy: PaycheckAllocationStrategy = .balanced,
        payoffStrategy: CreditCardPayoffStrategy = .balanced
    ) -> RecommendationDigest {
        let plan = recommendPaycheckPlan(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
            creditAccounts: creditAccounts,
            allocationStrategy: allocationStrategy,
            payoffStrategy: payoffStrategy
        )
        let upcomingBillCount = bills.filter { bill in
            guard bill.datePaid == nil, let dueDate = bill.dueDate else { return false }
            let dueDay = Calendar.current.startOfDay(for: dueDate)
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.startOfDay(for: nextPayday ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date())
            return dueDay >= start && dueDay <= end
        }.count

        return RecommendationDigest(
            nextPayday: nextPayday,
            upcomingBillCount: upcomingBillCount,
            behindGoalCount: goalProgressInsights(goals: goals, nextPayday: nextPayday).filter(\.isBehindSchedule).count,
            suggestedCardPaymentTotal: roundedToCents(plan.creditCardPayments.reduce(0) { $0 + $1.recommendedPayment }),
            suggestedGoalContributionTotal: roundedToCents(plan.goalContributions.reduce(0) { $0 + $1.recommendedContribution }),
            topCardName: plan.creditCardPayments.first?.billName,
            topGoalName: plan.goalContributions.first?.goalName
        )
    }

    private static func allocationRatio(for strategy: PaycheckAllocationStrategy) -> Double {
        switch strategy {
        case .balanced:
            return 0.55
        case .debtFirst:
            return 0.75
        case .goalsFirst:
            return 0.35
        }
    }

    private static func summary(
        for availableCash: Double,
        cardPayments: [CreditCardPaymentRecommendation],
        goalContributions: [GoalSavingInsight],
        unallocatedCash: Double
    ) -> String {
        let cardTotal = roundedToCents(cardPayments.reduce(0) { $0 + $1.recommendedPayment })
        let goalTotal = roundedToCents(goalContributions.reduce(0) { $0 + $1.recommendedContribution })

        if cardTotal == 0, goalTotal == 0 {
            return "No immediate card or goal actions were generated for \(MoneyMapFormatters.currencyString(for: availableCash))."
        }

        return "Plan \(MoneyMapFormatters.currencyString(for: cardTotal)) for cards, \(MoneyMapFormatters.currencyString(for: goalTotal)) for goals, and leave \(MoneyMapFormatters.currencyString(for: unallocatedCash)) flexible."
    }

    private static func goalInsightSort(lhs: GoalSavingInsight, rhs: GoalSavingInsight) -> Bool {
        if lhs.isBehindSchedule != rhs.isBehindSchedule {
            return lhs.isBehindSchedule && !rhs.isBehindSchedule
        }
        if lhs.shortfallAmount != rhs.shortfallAmount {
            return lhs.shortfallAmount > rhs.shortfallAmount
        }
        return lhs.recommendedContribution > rhs.recommendedContribution
    }

    private static func savingsBalanceWeight(for goal: Goal, insight: GoalSavingInsight?) -> Double {
        let urgency = goal.daysUntilDeadline > 0 ? 1.0 / Double(goal.daysUntilDeadline) : 1.0
        let behindWeight = insight?.isBehindSchedule == true ? 1.5 : 0
        return max(0.1, goal.weight) + urgency + behindWeight
    }

    private static func protectedGoalBudget(
        availableCash: Double,
        goals: [Goal],
        nextPayday: Date?,
        allocationStrategy: PaycheckAllocationStrategy,
        hasCardDebt: Bool
    ) -> Double {
        guard hasCardDebt else { return 0 }
        let behindNeed = goalProgressInsights(goals: goals, nextPayday: nextPayday)
            .filter(\.isBehindSchedule)
            .reduce(0) { total, insight in
                total + max(insight.shortfallAmount, insight.targetPerPaycheck)
            }
        guard behindNeed > 0 else { return 0 }

        let capRatio: Double
        switch allocationStrategy {
        case .balanced:
            capRatio = 1 - allocationRatio(for: allocationStrategy)
        case .debtFirst:
            capRatio = 0.1
        case .goalsFirst:
            capRatio = 1 - allocationRatio(for: allocationStrategy)
        }

        return roundedToCents(min(behindNeed, availableCash * capRatio))
    }

    private static func allocateCreditCardCash(
        remainingCash: inout Double,
        candidates: [CreditCardPaymentCandidate],
        paymentsByID: inout [UUID: Double],
        target: KeyPath<CreditCardPaymentCandidate, Double>,
        weight: KeyPath<CreditCardPaymentCandidate, Double>
    ) {
        while remainingCash > 0 {
            let openCandidates = candidates.compactMap { candidate -> (CreditCardPaymentCandidate, Double, Double)? in
                let currentPayment = paymentsByID[candidate.bill.id] ?? 0
                let additionalNeed = roundedToCents(max(0, candidate[keyPath: target] - currentPayment))
                guard additionalNeed > 0 else { return nil }
                return (candidate, max(candidate[keyPath: weight], 0.1), additionalNeed)
            }

            guard !openCandidates.isEmpty else { break }

            let passCash = remainingCash
            let totalWeight = openCandidates.reduce(0) { $0 + $1.1 }
            let minimumSlice = roundedToCents(min(passCash / Double(openCandidates.count), 25))
            var allocatedThisPass = 0.0

            for (candidate, score, additionalNeed) in openCandidates where remainingCash > 0 {
                let weightedShare = roundedToCents(passCash * (score / totalWeight))
                let proposed = max(weightedShare, minimumSlice)
                let extraPayment = roundedToCents(min(remainingCash, additionalNeed, proposed))
                guard extraPayment > 0 else { continue }
                paymentsByID[candidate.bill.id, default: 0] = roundedToCents(
                    (paymentsByID[candidate.bill.id] ?? 0) + extraPayment
                )
                remainingCash = roundedToCents(max(0, remainingCash - extraPayment))
                allocatedThisPass = roundedToCents(allocatedThisPass + extraPayment)
            }

            if allocatedThisPass == 0 {
                break
            }
        }
    }

    private static func cardPriorityScore(
        for bill: Bill,
        nextPayday: Date?,
        creditAccountsByID: [String: CreditCardPlanningAccount] = [:],
        strategy: CreditCardPayoffStrategy
    ) -> Double {
        let details = bill.creditCardDetails
        let linkedAccount = linkedCreditAccount(for: bill, creditAccountsByID: creditAccountsByID)
        let balance = effectiveCardBalance(for: bill, creditAccountsByID: creditAccountsByID)
        let creditLimit = effectiveCreditLimit(details: details, linkedAccount: linkedAccount, balance: balance)
        let utilization = creditLimit > 0 ? balance / creditLimit : 0
        let utilizationScore = utilization * 100
        let aprScore = (details?.annualPercentageRate ?? 0) * 100
        let largeBalanceScore = largeBalanceScore(for: balance)
        let smallBalanceScore = balance > 0 ? (10_000 / max(balance, 1)) : 0
        let statementScore = statementTarget(for: bill, balance: balance) / 50
        let minimumPaymentScore = min(effectiveMinimumPayment(for: bill) / 10, 20)
        let isMarkedPaid = bill.datePaid != nil || bill.status == .paid
        let dueSoonScore = dueSoonWeight(for: bill.dueDate, nextPayday: nextPayday, isMarkedPaid: isMarkedPaid)
        let autopayPenalty = bill.autopayEnabled ? -3.0 : 0
        let unpaidBonus = (bill.datePaid == nil && balance > 0) ? 15.0 : 0

        switch strategy {
        case .balanced:
            return utilizationScore + aprScore + minimumPaymentScore + (dueSoonScore * 0.35) + (largeBalanceScore * 1.2) + unpaidBonus + autopayPenalty
        case .avalanche:
            return (aprScore * 1.6) + minimumPaymentScore + dueSoonScore + (utilizationScore * 0.5) + (largeBalanceScore * 0.25) + unpaidBonus + autopayPenalty
        case .snowball:
            return smallBalanceScore + minimumPaymentScore + dueSoonScore + unpaidBonus + autopayPenalty
        case .dueDate:
            return (dueSoonScore * 2) + minimumPaymentScore + (aprScore * 0.4) + (largeBalanceScore * 0.35) + unpaidBonus + autopayPenalty
        case .utilization:
            return (utilizationScore * 2) + dueSoonScore + minimumPaymentScore + unpaidBonus + autopayPenalty
        case .statementBalance:
            return statementScore + dueSoonScore + minimumPaymentScore + (largeBalanceScore * 0.2) + unpaidBonus + autopayPenalty
        }
    }

    private static func largeBalanceScore(for balance: Double) -> Double {
        min(max(balance, 0) / 100, 50)
    }

    private static func effectiveCardBalance(
        for bill: Bill,
        creditAccountsByID: [String: CreditCardPlanningAccount] = [:]
    ) -> Double {
        guard bill.category == .creditCard else { return 0 }
        let details = bill.creditCardDetails
        let linkedBalance = linkedCreditAccount(for: bill, creditAccountsByID: creditAccountsByID)?.balanceAmount ?? 0
        return max(
            linkedBalance,
            abs(details?.cardBalance ?? 0),
            abs(details?.statementBalance ?? 0),
            details?.effectiveMinimumPayment ?? 0,
            bill.amount ?? 0,
            0
        )
    }

    private static func effectiveMinimumPayment(for bill: Bill) -> Double {
        let detailedMinimum = bill.creditCardDetails?.effectiveMinimumPayment ?? 0
        if detailedMinimum > 0 {
            return detailedMinimum
        }
        return max(bill.amount ?? 0, 0)
    }

    private static func linkedCreditAccount(
        for bill: Bill,
        creditAccountsByID: [String: CreditCardPlanningAccount]
    ) -> CreditCardPlanningAccount? {
        guard let plaidAccountID = bill.plaidAccountID, !plaidAccountID.isEmpty else { return nil }
        return creditAccountsByID[plaidAccountID]
    }

    private static func effectiveCreditLimit(
        details: CreditCardDetails?,
        linkedAccount: CreditCardPlanningAccount?,
        balance: Double
    ) -> Double {
        let linkedLimit = balance + max(linkedAccount?.availableBalance ?? 0, 0)
        return max(details?.creditLimit ?? 0, linkedLimit, balance, 0)
    }

    private static func statementTarget(for bill: Bill, balance: Double) -> Double {
        if let statementBalance = bill.creditCardDetails?.statementBalance {
            return min(abs(statementBalance), balance)
        }
        if let amount = bill.amount, amount > 0 {
            return min(amount, balance)
        }
        return balance
    }

    private static func duePaymentTarget(for bill: Bill, balance: Double) -> Double {
        if let statementBalance = bill.creditCardDetails?.statementBalance {
            return min(abs(statementBalance), balance)
        }
        if let minimumPayment = bill.creditCardDetails?.effectiveMinimumPayment, minimumPayment > 0 {
            return min(minimumPayment, balance)
        }
        if let amount = bill.amount, amount > 0 {
            return min(amount, balance)
        }
        return 0
    }

    private static func rationale(for bill: Bill, nextPayday: Date?, strategy: CreditCardPayoffStrategy) -> String {
        let details = bill.creditCardDetails
        let isMarkedPaid = bill.datePaid != nil || bill.status == .paid
        let isDueBeforeNextPayday = isDueBefore(nextPayday: nextPayday, dueDate: bill.dueDate)

        switch strategy {
        case .balanced:
            if isDueBeforeNextPayday && !isMarkedPaid { return "Due before next payday and still unpaid" }
            if (details?.utilization ?? 0) >= 0.3 { return "High utilization and active balance" }
            if let apr = details?.annualPercentageRate, apr >= 0.2 { return "High APR balance" }
            if dueSoonWeight(for: bill.dueDate, nextPayday: nextPayday, isMarkedPaid: isMarkedPaid) >= 20 { return "Payment due soon" }
            return "Balanced payoff priority"
        case .avalanche:
            return isDueBeforeNextPayday && !isMarkedPaid ? "Unpaid and due before next payday, with APR priority" : "Highest interest cost first"
        case .snowball:
            return isDueBeforeNextPayday && !isMarkedPaid ? "Due before next payday, then smallest balance first" : "Smallest balance for faster payoff wins"
        case .dueDate:
            return isMarkedPaid ? "Later card priority because this cycle is already marked paid" : "Next due card gets priority"
        case .utilization:
            return isDueBeforeNextPayday && !isMarkedPaid ? "Unpaid before next payday, with extra focus on utilization" : "Highest utilization should come down first"
        case .statementBalance:
            return isDueBeforeNextPayday && !isMarkedPaid ? "Unpaid before next payday, with statement balance priority" : "Statement balance is the main target"
        }
    }

    private static func dueSoonWeight(for dueDate: Date?, nextPayday: Date?, isMarkedPaid: Bool) -> Double {
        guard let dueDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: dueDate)).day ?? 99
        if days < 0 {
            return isMarkedPaid ? 0 : 55
        }
        if isDueBefore(nextPayday: nextPayday, dueDate: dueDate) && !isMarkedPaid {
            return 45 + max(0, Double(14 - min(days, 14)))
        }
        switch days {
        case 0...3:
            return 40
        case 4...7:
            return 25
        case 8...14:
            return 10
        default:
            return 0
        }
    }

    private static func isDueBefore(nextPayday: Date?, dueDate: Date?) -> Bool {
        guard let dueDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: dueDate)
        let horizon = Calendar.current.startOfDay(
            for: nextPayday ?? Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today
        )
        return dueDay >= today && dueDay <= horizon
    }

    private static func paydaysUntil(deadline: Date, nextPayday: Date?) -> Int {
        guard let nextPayday else { return 1 }

        var count = 0
        var current = Calendar.current.startOfDay(for: nextPayday)
        let end = Calendar.current.startOfDay(for: deadline)

        while current <= end {
            count += 1
            current = Calendar.current.date(byAdding: .day, value: 14, to: current) ?? current.addingTimeInterval(60 * 60 * 24 * 14)
        }

        return max(count, 1)
    }

    private static func paydaysElapsed(for goal: Goal, nextPayday: Date?) -> Int {
        guard
            let nextPayday,
            let firstPayday = Calendar.current.date(byAdding: .day, value: -14, to: nextPayday)
        else {
            return 1
        }

        let createdDay = Calendar.current.startOfDay(for: goal.createdDate)
        var current = Calendar.current.startOfDay(for: firstPayday)
        let today = Calendar.current.startOfDay(for: Date())
        var count = 0

        while current <= today {
            if current >= createdDay {
                count += 1
            }
            current = Calendar.current.date(byAdding: .day, value: 14, to: current) ?? current.addingTimeInterval(60 * 60 * 24 * 14)
        }

        return max(count, 1)
    }

    private static func roundedToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
