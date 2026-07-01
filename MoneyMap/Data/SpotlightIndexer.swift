//
//  SpotlightIndexer.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum SpotlightIndexer {
    private static let billsDomainIdentifier = "com.heyjoshsmith.MoneyMap.bills"
    private static let goalsDomainIdentifier = "com.heyjoshsmith.MoneyMap.goals"
    private static let transactionsDomainIdentifier = "com.heyjoshsmith.MoneyMap.transactions"
    private static let recommendationsDomainIdentifier = "com.heyjoshsmith.MoneyMap.recommendations"
    private static let billPrefix = "bill."
    private static let goalPrefix = "goal."
    private static let transactionPrefix = "transaction."
    private static let recommendationsIdentifier = "recommendations.paycheck"

    static func reindexBills(_ bills: [Bill]) {
        index(items: bills.map(makeBillItem))
    }

    static func reindexGoals(_ goals: [Goal]) {
        index(items: goals.map(makeGoalItem))
    }

    static func reindexTransactions(_ transactions: [Transaction]) {
        index(items: transactions.map(makeTransactionItem))
    }

    static func reindexRecommendations(_ digest: RecommendationDigest) {
        index(items: [makeRecommendationsItem(for: digest)])
    }

    static func removeAllBillEntries() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [
            billsDomainIdentifier,
            goalsDomainIdentifier,
            transactionsDomainIdentifier,
            recommendationsDomainIdentifier
        ]) { error in
            if let error {
                print("Spotlight delete error: \(error.localizedDescription)")
            }
        }
    }

    static func routeFromSearchableItemActivity(_ userActivity: NSUserActivity) -> MoneyMapRoute? {
        guard let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }

        if identifier.hasPrefix(billPrefix) {
            let rawUUID = String(identifier.dropFirst(billPrefix.count))
            guard let billID = UUID(uuidString: rawUUID) else { return nil }
            return .openBill(billID)
        }

        if identifier.hasPrefix(goalPrefix) {
            let rawUUID = String(identifier.dropFirst(goalPrefix.count))
            guard let goalID = UUID(uuidString: rawUUID) else { return nil }
            return .openGoal(goalID)
        }

        if identifier.hasPrefix(transactionPrefix) {
            let rawValue = String(identifier.dropFirst(transactionPrefix.count))
            let components = rawValue.components(separatedBy: ".")
            guard let billComponent = components.first,
                  let billID = UUID(uuidString: billComponent) else {
                return nil
            }
            return .openBill(billID)
        }

        if identifier == recommendationsIdentifier {
            return .showRecommendations
        }

        return nil
    }

    private static func index(items: [CSSearchableItem]) {
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }

    private static func makeBillItem(for bill: Bill) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        let entity = BillEntity(bill)
        let title = bill.name ?? "Untitled Bill"
        let amount = MoneyMapFormatters.currencyString(for: bill.amount ?? 0)
        let dueText = bill.dueDate.map { MoneyMapFormatters.mediumDateString(for: $0) } ?? "No due date"
        let category = bill.category?.name ?? "Other"

        attributeSet.title = title
        attributeSet.displayName = title
        attributeSet.contentDescription = "\(amount) • \(category) • due \(dueText)"
        attributeSet.keywords = [category, "Bill", "MoneyMap", amount]
        attributeSet.contentType = UTType.item.identifier
        attributeSet.identifier = bill.id.uuidString
        attributeSet.associateAppEntity(entity, priority: spotlightPriority(for: bill))

        if let url = MoneyMapDeepLink.url(for: .openBill(bill.id)) {
            attributeSet.relatedUniqueIdentifier = url.absoluteString
            attributeSet.contentURL = url
        }

        return CSSearchableItem(
            uniqueIdentifier: billIdentifier(for: bill.id),
            domainIdentifier: billsDomainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func makeGoalItem(for goal: Goal) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        let entity = GoalEntity(goal)
        let title = goal.name ?? "Savings Goal"
        let remaining = MoneyMapFormatters.currencyString(for: goal.remainingAmount)
        let deadline = goal.deadline.map { MoneyMapFormatters.mediumDateString(for: $0) } ?? "No deadline"
        let progress = Int((goal.progress() * 100).rounded())

        attributeSet.title = title
        attributeSet.displayName = title
        attributeSet.contentDescription = "\(remaining) remaining • \(progress)% saved • deadline \(deadline)"
        attributeSet.keywords = ["Goal", "Savings", "MoneyMap", remaining]
        attributeSet.contentType = UTType.item.identifier
        attributeSet.identifier = goal.id.uuidString
        attributeSet.associateAppEntity(entity, priority: spotlightPriority(for: goal))

        if let url = MoneyMapDeepLink.url(for: .openGoal(goal.id)) {
            attributeSet.relatedUniqueIdentifier = url.absoluteString
            attributeSet.contentURL = url
        }

        return CSSearchableItem(
            uniqueIdentifier: goalIdentifier(for: goal.id),
            domainIdentifier: goalsDomainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func makeRecommendationsItem(for digest: RecommendationDigest) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        let paydayText = digest.nextPayday.map { MoneyMapFormatters.mediumDateString(for: $0) } ?? "No payday set"
        let cardText = MoneyMapFormatters.currencyString(for: digest.suggestedCardPaymentTotal)
        let goalText = MoneyMapFormatters.currencyString(for: digest.suggestedGoalContributionTotal)

        attributeSet.title = "Paycheck Recommendations"
        attributeSet.displayName = "Paycheck Recommendations"
        attributeSet.contentDescription = "Next payday \(paydayText). Suggest \(cardText) to cards and \(goalText) to goals."
        attributeSet.keywords = ["Recommendations", "Paycheck", "MoneyMap", "Cards", "Goals"]
        attributeSet.contentType = UTType.item.identifier
        attributeSet.identifier = recommendationsIdentifier

        if let url = MoneyMapDeepLink.url(for: .showRecommendations) {
            attributeSet.relatedUniqueIdentifier = url.absoluteString
            attributeSet.contentURL = url
        }

        return CSSearchableItem(
            uniqueIdentifier: recommendationsIdentifier,
            domainIdentifier: recommendationsDomainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func makeTransactionItem(for transaction: Transaction) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        let entity = TransactionEntity(transaction)
        let title = transactionHeadline(transaction)
        let amount = MoneyMapFormatters.currencyString(for: abs(transaction.amountUSD ?? 0))
        let date = (transaction.transactionDate ?? transaction.clearingDate).map(MoneyMapFormatters.mediumDateString(for:)) ?? "Unknown date"
        let cardName = transaction.creditCard?.name ?? "Unknown card"

        attributeSet.title = title
        attributeSet.displayName = title
        attributeSet.contentDescription = "\(amount) • \(cardName) • \(date)"
        attributeSet.keywords = [transaction.merchant, transaction.category, cardName, "Transaction", "MoneyMap"]
            .compactMap { $0 }
        attributeSet.contentType = UTType.item.identifier
        attributeSet.identifier = entity.id
        attributeSet.associateAppEntity(entity, priority: 60)

        if let billID = transaction.creditCard?.id,
           let url = MoneyMapDeepLink.url(for: .openBill(billID)) {
            attributeSet.relatedUniqueIdentifier = url.absoluteString
            attributeSet.contentURL = url
        }

        return CSSearchableItem(
            uniqueIdentifier: transactionIdentifier(for: transaction),
            domainIdentifier: transactionsDomainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func billIdentifier(for id: UUID) -> String {
        "\(billPrefix)\(id.uuidString)"
    }

    private static func goalIdentifier(for id: UUID) -> String {
        "\(goalPrefix)\(id.uuidString)"
    }

    private static func transactionIdentifier(for transaction: Transaction) -> String {
        let billID = transaction.creditCard?.id.uuidString ?? "no-card"
        return "\(transactionPrefix)\(billID).\(transactionEntityID(for: transaction))"
    }

    private static func spotlightPriority(for bill: Bill) -> Int {
        if bill.status == .overdue {
            return 100
        }
        if bill.datePaid == nil {
            return 80
        }
        return 20
    }

    private static func spotlightPriority(for goal: Goal) -> Int {
        if goal.remainingAmount > 0 {
            return 70
        }
        return 30
    }
}
