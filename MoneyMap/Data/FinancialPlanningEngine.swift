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

enum FinancialPlanningEngine {
    static func recommendPaycheckPlan(
        availableCash: Double,
        goals: [Goal],
        bills: [Bill],
        nextPayday: Date?,
        allocationStrategy: PaycheckAllocationStrategy = .balanced,
        payoffStrategy: CreditCardPayoffStrategy = .balanced
    ) -> PaycheckRecommendationPlan {
        let roundedAvailable = roundedToCents(max(availableCash, 0))
        let cards = bills.filter { $0.category == .creditCard }

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

        let minimumCardCoverage = roundedToCents(cards.reduce(0) { total, bill in
            total + min(bill.creditCardDetails?.effectiveMinimumPayment ?? 0, bill.creditCardDetails?.cardBalance ?? 0)
        })
        let preferredCardBudget = roundedToCents(roundedAvailable * allocationRatio(for: allocationStrategy))
        let cardBudget = roundedToCents(min(roundedAvailable, max(minimumCardCoverage, preferredCardBudget)))
        let goalBudget = roundedToCents(max(0, roundedAvailable - cardBudget))

        let cardPayments = recommendCreditCardPayments(
            availableCash: cardBudget,
            cards: cards,
            nextPayday: nextPayday,
            strategy: payoffStrategy
        )
        let spentOnCards = roundedToCents(cardPayments.reduce(0) { $0 + $1.recommendedPayment })
        let cardRemainder = roundedToCents(max(0, cardBudget - spentOnCards))

        let goalContributions = recommendGoalContributions(
            availableCash: goalBudget + cardRemainder,
            goals: goals,
            nextPayday: nextPayday
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
        strategy: CreditCardPayoffStrategy = .balanced
    ) -> [CreditCardPaymentRecommendation] {
        var remainingCash = roundedToCents(max(availableCash, 0))
        guard remainingCash > 0 else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        let planningHorizon = Calendar.current.startOfDay(
            for: nextPayday ?? Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today
        )

        let prioritizedCards = cards
            .filter { ($0.creditCardDetails?.cardBalance ?? 0) > 0 }
            .sorted { lhs, rhs in
                let lhsScore = cardPriorityScore(for: lhs, nextPayday: nextPayday, strategy: strategy)
                let rhsScore = cardPriorityScore(for: rhs, nextPayday: nextPayday, strategy: strategy)
                if lhsScore == rhsScore {
                    return Bill.byDate(lhs: lhs, rhs: rhs)
                }
                return lhsScore > rhsScore
            }

        var recommendations: [CreditCardPaymentRecommendation] = []
        var paymentsByID: [UUID: Double] = [:]
        var targetsByID: [UUID: Double] = [:]

        // First, protect cards that matter before the next payday.
        for bill in prioritizedCards where remainingCash > 0 {
            guard let details = bill.creditCardDetails else { continue }

            let balance = max(details.cardBalance, 0)
            let minimumPayment = min(details.effectiveMinimumPayment, balance)
            let utilizationTarget = max(0, balance - (details.creditLimit * 0.3))
            let statementTarget = min(details.statementBalance ?? balance, balance)
            let dueDay = bill.dueDate.map { Calendar.current.startOfDay(for: $0) }
            let isMarkedPaid = bill.datePaid != nil || bill.status == .paid
            let isOverdue = dueDay.map { $0 < today } ?? false
            let isDueBeforeNextPayday = dueDay.map { $0 <= planningHorizon } ?? false
            let protectedBase: Double

            if isOverdue && !isMarkedPaid {
                protectedBase = max(minimumPayment, min(statementTarget, balance))
            } else if isDueBeforeNextPayday && !isMarkedPaid {
                protectedBase = minimumPayment
            } else {
                protectedBase = 0
            }

            let preferredTarget: Double

            switch strategy {
            case .balanced:
                preferredTarget = max(protectedBase, minimumPayment, utilizationTarget, min(statementTarget, balance))
            case .avalanche:
                preferredTarget = max(protectedBase, minimumPayment, min(statementTarget, balance), utilizationTarget)
            case .snowball:
                preferredTarget = balance
            case .dueDate:
                preferredTarget = isDueBeforeNextPayday ? balance : max(protectedBase, minimumPayment)
            case .utilization:
                preferredTarget = max(protectedBase, minimumPayment, utilizationTarget)
            case .statementBalance:
                preferredTarget = max(protectedBase, minimumPayment, statementTarget)
            }

            let basePayment = roundedToCents(min(remainingCash, protectedBase))
            paymentsByID[bill.id] = basePayment
            targetsByID[bill.id] = roundedToCents(min(balance, preferredTarget))
            remainingCash = roundedToCents(max(0, remainingCash - basePayment))
        }

        // Then spread any remaining cash across multiple cards based on priority and need.
        while remainingCash > 0 {
            let candidates = prioritizedCards.compactMap { bill -> (Bill, Double, Double)? in
                let currentPayment = paymentsByID[bill.id] ?? 0
                let target = targetsByID[bill.id] ?? 0
                let additionalNeed = roundedToCents(max(0, target - currentPayment))
                guard additionalNeed > 0 else { return nil }
                let score = max(cardPriorityScore(for: bill, nextPayday: nextPayday, strategy: strategy), 0.1)
                return (bill, score, additionalNeed)
            }

            guard !candidates.isEmpty else { break }

            let totalWeight = candidates.reduce(0) { $0 + $1.1 }
            var allocatedThisPass = 0.0

            for (bill, score, additionalNeed) in candidates where remainingCash > 0 {
                let weightedShare = roundedToCents(remainingCash * (score / totalWeight))
                let proposed = max(weightedShare, min(remainingCash, 25))
                let extraPayment = roundedToCents(min(remainingCash, additionalNeed, proposed))
                guard extraPayment > 0 else { continue }
                paymentsByID[bill.id, default: 0] += extraPayment
                remainingCash = roundedToCents(max(0, remainingCash - extraPayment))
                allocatedThisPass += extraPayment
            }

            if allocatedThisPass == 0 {
                for (bill, _, additionalNeed) in candidates where remainingCash > 0 {
                    let extraPayment = roundedToCents(min(remainingCash, additionalNeed))
                    guard extraPayment > 0 else { continue }
                    paymentsByID[bill.id, default: 0] += extraPayment
                    remainingCash = roundedToCents(max(0, remainingCash - extraPayment))
                }
                break
            }
        }

        for bill in prioritizedCards {
            guard let details = bill.creditCardDetails else { continue }
            let balance = max(details.cardBalance, 0)
            let minimumPayment = min(details.effectiveMinimumPayment, balance)
            let payment = roundedToCents(min(paymentsByID[bill.id] ?? 0, balance))
            guard payment > 0 else { continue }

            recommendations.append(
                CreditCardPaymentRecommendation(
                    billID: bill.id,
                    billName: bill.name ?? "Card",
                    recommendedPayment: payment,
                    rationale: rationale(for: bill, nextPayday: nextPayday, strategy: strategy),
                    dueDate: bill.dueDate,
                    utilization: details.utilization,
                    annualPercentageRate: details.annualPercentageRate,
                    minimumPayment: minimumPayment
                )
            )
        }

        return recommendations
    }

    static func recommendGoalContributions(
        availableCash: Double,
        goals: [Goal],
        nextPayday: Date?
    ) -> [GoalSavingInsight] {
        let totalAvailable = roundedToCents(max(availableCash, 0))
        let progressInsights = goalProgressInsights(goals: goals, nextPayday: nextPayday)

        guard totalAvailable > 0 else {
            return progressInsights.map { insight in
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

        let weightedGoals: [(GoalSavingInsight, Double)] = progressInsights.compactMap { insight in
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

    static func scenarioPlans(
        baseAvailableCash: Double,
        goals: [Goal],
        bills: [Bill],
        nextPayday: Date?,
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
        allocationStrategy: PaycheckAllocationStrategy = .balanced,
        payoffStrategy: CreditCardPayoffStrategy = .balanced
    ) -> RecommendationDigest {
        let plan = recommendPaycheckPlan(
            availableCash: availableCash,
            goals: goals,
            bills: bills,
            nextPayday: nextPayday,
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

    private static func cardPriorityScore(for bill: Bill, nextPayday: Date?, strategy: CreditCardPayoffStrategy) -> Double {
        guard let details = bill.creditCardDetails else { return 0 }

        let utilizationScore = details.utilization * 100
        let aprScore = (details.annualPercentageRate ?? 0) * 100
        let balanceScore = details.cardBalance > 0 ? (10_000 / max(details.cardBalance, 1)) : 0
        let statementScore = (details.statementBalance ?? 0) / 50
        let minimumPaymentScore = min(details.effectiveMinimumPayment / 10, 20)
        let isMarkedPaid = bill.datePaid != nil || bill.status == .paid
        let dueSoonScore = dueSoonWeight(for: bill.dueDate, nextPayday: nextPayday, isMarkedPaid: isMarkedPaid)
        let autopayPenalty = bill.autopayEnabled ? -3.0 : 0
        let unpaidBonus = (bill.datePaid == nil && details.cardBalance > 0) ? 15.0 : 0

        switch strategy {
        case .balanced:
            return utilizationScore + aprScore + minimumPaymentScore + dueSoonScore + unpaidBonus + autopayPenalty
        case .avalanche:
            return (aprScore * 1.6) + minimumPaymentScore + dueSoonScore + (utilizationScore * 0.5) + unpaidBonus + autopayPenalty
        case .snowball:
            return balanceScore + minimumPaymentScore + dueSoonScore + unpaidBonus + autopayPenalty
        case .dueDate:
            return (dueSoonScore * 2) + minimumPaymentScore + (aprScore * 0.4) + unpaidBonus + autopayPenalty
        case .utilization:
            return (utilizationScore * 2) + dueSoonScore + minimumPaymentScore + unpaidBonus + autopayPenalty
        case .statementBalance:
            return statementScore + dueSoonScore + minimumPaymentScore + unpaidBonus + autopayPenalty
        }
    }

    private static func rationale(for bill: Bill, nextPayday: Date?, strategy: CreditCardPayoffStrategy) -> String {
        guard let details = bill.creditCardDetails else { return "Prioritized because it is active." }
        let isMarkedPaid = bill.datePaid != nil || bill.status == .paid
        let isDueBeforeNextPayday = isDueBefore(nextPayday: nextPayday, dueDate: bill.dueDate)

        switch strategy {
        case .balanced:
            if isDueBeforeNextPayday && !isMarkedPaid { return "Due before next payday and still unpaid" }
            if details.utilization >= 0.3 { return "High utilization and active balance" }
            if let apr = details.annualPercentageRate, apr >= 0.2 { return "High APR balance" }
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
            return 45
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
