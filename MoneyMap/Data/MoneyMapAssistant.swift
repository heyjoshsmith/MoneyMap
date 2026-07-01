//
//  MoneyMapAssistant.swift
//  MoneyMap
//
//  Created by Codex on 6/16/26.
//

import Foundation
import FoundationModels

enum MoneyMapAssistant {
    static let model = SystemLanguageModel.default

    static func availabilityMessage(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use the MoneyMap assistant."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing the model on this device."
        @unknown default:
            return "Apple Intelligence is unavailable right now."
        }
    }

    static func answer(question: String) async throws -> String {
        let session = LanguageModelSession(
            model: model,
            tools: [
                MoneyMapContextTool(),
                MoneyMapTransactionTool(),
                MoneyMapRecommendationTool()
            ],
            instructions: """
            You are the built-in MoneyMap assistant.
            Answer only from tool output.
            If the question is about bills, goals, payday, or savings, use the MoneyMapContextTool.
            If the question is about spending, merchants, card activity, or recent purchases, use the MoneyMapTransactionTool.
            If the question is about what to do with a paycheck, use the MoneyMapRecommendationTool.
            Keep answers short, concrete, and personal to the user's data.
            Do not invent numbers, dates, merchants, or balances.
            If the tools do not provide the answer, say what is missing.
            """
        )

        let response = try await session.respond(to: question)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Generable
private struct MoneyMapContextArguments {
    @Guide(description: "The user's question about bills, goals, payday, or savings.")
    var question: String
}

private struct MoneyMapContextTool: Tool {
    let description = "Looks up MoneyMap bills, goals, payday information, and savings progress."

    func call(arguments: MoneyMapContextArguments) async throws -> String {
        let snapshot = try MoneyMapPlanningStore.snapshot()
        let bills = snapshot.bills.sorted(by: Bill.byStatusDateUtilization)
        let goals = snapshot.goals.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        let lowercasedQuestion = arguments.question.lowercased()

        let dueBeforePayday = bills.filter { bill in
            guard let nextPayday = snapshot.nextPayday,
                  let dueDate = bill.dueDate,
                  bill.status != .paid else {
                return false
            }
            return dueDate <= nextPayday
        }

        let billLines = bills.prefix(8).map { bill in
            let amount = MoneyMapFormatters.currencyString(for: bill.amount ?? 0)
            let due = bill.dueDate.map(MoneyMapFormatters.mediumDateString(for:)) ?? "No due date"
            let status = bill.status?.name ?? "Unknown"
            return "- Bill: \(bill.name ?? "Untitled"), amount \(amount), due \(due), status \(status)"
        }

        let matchingGoals = goals.filter { goal in
            guard !lowercasedQuestion.isEmpty else { return false }
            return (goal.name ?? "").lowercased().contains(lowercasedQuestion)
        }

        let selectedGoals: [Goal] = matchingGoals.isEmpty ? Array(goals.prefix(8)) : Array(matchingGoals.prefix(8))

        let goalLines = selectedGoals.map { goal in
            let saved = MoneyMapFormatters.currencyString(for: goal.amountSaved)
            let remaining = MoneyMapFormatters.currencyString(for: goal.remainingAmount)
            let deadline = goal.deadline.map(MoneyMapFormatters.mediumDateString(for:)) ?? "No deadline"
            return "- Goal: \(goal.name ?? "Untitled"), saved \(saved), remaining \(remaining), deadline \(deadline)"
        }

        let dueBeforePaydayTotal = dueBeforePayday.reduce(0) { $0 + ($1.amount ?? 0) }
        let leftAfterBills = max(snapshot.amountPerPayday - dueBeforePaydayTotal, 0)
        let nextPaydayText = snapshot.nextPayday.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Not set"

        return """
        Next payday: \(nextPaydayText)
        Amount per payday: \(MoneyMapFormatters.currencyString(for: snapshot.amountPerPayday))
        Bills due before payday: \(dueBeforePayday.count)
        Bills due before payday total: \(MoneyMapFormatters.currencyString(for: dueBeforePaydayTotal))
        Left after bills: \(MoneyMapFormatters.currencyString(for: leftAfterBills))
        Total goals: \(goals.count)
        Total saved across goals: \(MoneyMapFormatters.currencyString(for: goals.reduce(0) { $0 + $1.amountSaved }))
        Total remaining across goals: \(MoneyMapFormatters.currencyString(for: goals.reduce(0) { $0 + $1.remainingAmount }))

        Bills:
        \(billLines.isEmpty ? "- None" : billLines.joined(separator: "\n"))

        Goals:
        \(goalLines.isEmpty ? "- None" : goalLines.joined(separator: "\n"))
        """
    }
}

@Generable
private struct MoneyMapTransactionArguments {
    @Guide(description: "The user's question about spending, merchants, cards, or recent purchases.")
    var question: String

    @Guide(description: "Maximum number of transactions to include.", .range(1...12))
    var limit: Int
}

private struct MoneyMapTransactionTool: Tool {
    let description = "Searches imported MoneyMap card transactions by merchant, category, card, and recency."

    func call(arguments: MoneyMapTransactionArguments) async throws -> String {
        let normalized = arguments.question.lowercased()
        let allTransactions = try MoneyMapTransactionStore.fetchTransactions()
        let filtered = allTransactions
            .filter { transaction in
                guard !normalized.isEmpty else { return true }
                let haystacks = [
                    transaction.friendlyName,
                    transaction.merchant,
                    transaction.transactionDescription,
                    transaction.category,
                    transaction.creditCard?.name
                ]
                return haystacks
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(normalized) }
            }
            .sorted(by: MoneyMapTransactionStore.mostRecentFirst)

        let shown = Array((filtered.isEmpty ? allTransactions.sorted(by: MoneyMapTransactionStore.mostRecentFirst) : filtered).prefix(max(arguments.limit, 1)))
        let total = shown.reduce(0) { $0 + abs($1.amountUSD ?? 0) }

        let lines = shown.map { transaction in
            let amount = MoneyMapFormatters.currencyString(for: abs(transaction.amountUSD ?? 0))
            let date = (transaction.transactionDate ?? transaction.clearingDate).map(MoneyMapFormatters.mediumDateString(for:)) ?? "Unknown date"
            let merchant = transaction.friendlyName ?? transaction.merchant ?? transaction.transactionDescription ?? "Unknown merchant"
            let category = transaction.category ?? "Uncategorized"
            let card = transaction.creditCard?.name ?? "Unknown card"
            return "- \(merchant), \(amount), \(date), category \(category), card \(card)"
        }

        return """
        Matching transactions: \(filtered.count)
        Total amount in returned results: \(MoneyMapFormatters.currencyString(for: total))
        Transactions:
        \(lines.isEmpty ? "- None" : lines.joined(separator: "\n"))
        """
    }
}

@Generable
private struct MoneyMapRecommendationArguments {
    @Guide(description: "Available cash to plan, if the user gave one.", .range(0...100000))
    var availableCash: Double?
}

private struct MoneyMapRecommendationTool: Tool {
    let description = "Builds a grounded paycheck recommendation from the user's MoneyMap bills, goals, and payday."

    func call(arguments: MoneyMapRecommendationArguments) async throws -> String {
        let snapshot = try MoneyMapPlanningStore.snapshot()
        let cash = max(arguments.availableCash ?? snapshot.amountPerPayday, 0)
        let plan = FinancialPlanningEngine.recommendPaycheckPlan(
            availableCash: cash,
            goals: snapshot.goals,
            bills: snapshot.bills,
            nextPayday: snapshot.nextPayday,
            allocationStrategy: RecommendationPreferencesStore.paycheckStrategy,
            payoffStrategy: RecommendationPreferencesStore.cardStrategy
        )

        let topCard = plan.creditCardPayments.first.map {
            "\($0.billName) \(MoneyMapFormatters.currencyString(for: $0.recommendedPayment))"
        } ?? "None"
        let topGoal = plan.goalContributions.first.map {
            "\($0.goalName) \(MoneyMapFormatters.currencyString(for: $0.recommendedContribution))"
        } ?? "None"

        return """
        Available cash: \(MoneyMapFormatters.currencyString(for: cash))
        Next payday: \(snapshot.nextPayday.map(MoneyMapFormatters.mediumDateString(for:)) ?? "Not set")
        Summary: \(plan.summary)
        Top card action: \(topCard)
        Top goal action: \(topGoal)
        Unallocated cash: \(MoneyMapFormatters.currencyString(for: plan.unallocatedCash))
        """
    }
}
