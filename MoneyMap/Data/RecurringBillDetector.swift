//
//  RecurringBillDetector.swift
//  MoneyMap
//
//  Created by Codex on 7/7/26.
//

import Foundation

enum RecurringBillCadence: Equatable {
    case weekly
    case biweekly
    case monthly
    case annual

    var recurrenceInterval: Int {
        switch self {
        case .weekly, .monthly, .annual:
            return 1
        case .biweekly:
            return 2
        }
    }

    var recurrenceUnit: RecurrenceUnit {
        switch self {
        case .weekly, .biweekly:
            return .week
        case .monthly:
            return .month
        case .annual:
            return .year
        }
    }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Every 2 weeks"
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual"
        }
    }
}

enum RecurringChargeKind: String, Equatable {
    case bill
    case subscription
    case loan
    case membership
    case service
    case utility
    case insurance
    case housing

    var title: String {
        switch self {
        case .bill:
            return "Bill"
        case .subscription:
            return "Subscription"
        case .loan:
            return "Loan"
        case .membership:
            return "Membership"
        case .service:
            return "Service"
        case .utility:
            return "Utility"
        case .insurance:
            return "Insurance"
        case .housing:
            return "Housing"
        }
    }

    var addActionTitle: String {
        switch self {
        case .bill:
            return "Add Bill"
        default:
            return "Add \(title)"
        }
    }

    var systemImage: String {
        switch self {
        case .bill:
            return "calendar.badge.clock"
        case .subscription:
            return "repeat"
        case .loan:
            return "banknote"
        case .membership:
            return "person.crop.circle.badge.checkmark"
        case .service:
            return "wrench.and.screwdriver"
        case .utility:
            return "bolt"
        case .insurance:
            return "shield.lefthalf.filled"
        case .housing:
            return "house"
        }
    }
}

struct RecurringBillSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let normalizedMerchant: String
    let kind: RecurringChargeKind
    let category: BillCategory
    let amount: Double
    let nextDueDate: Date
    let cadence: RecurringBillCadence
    let transactionCount: Int
    let confidence: Double
    let latestTransactionDate: Date
    let matchedBillID: UUID?
    let matchedBillLifecycleState: BillLifecycleState?
    let evidence: [RecurringChargeEvidence]

    var confidenceLabel: String {
        if confidence >= 0.86 { return "High confidence" }
        if confidence >= 0.72 { return "Medium confidence" }
        return "Low confidence"
    }

    var hasCanceledMatch: Bool {
        matchedBillLifecycleState == .canceled
    }

    var minimumEvidenceAmount: Double {
        evidence.map(\.amount).min() ?? amount
    }

    var maximumEvidenceAmount: Double {
        evidence.map(\.amount).max() ?? amount
    }

    var amountVaries: Bool {
        maximumEvidenceAmount - minimumEvidenceAmount >= 0.01
    }
}

struct RecurringChargeEvidence: Identifiable, Equatable {
    let id: String
    let date: Date
    let amount: Double
    let displayName: String
    let category: String?
    let purchasedBy: String?
    let plaidTransactionID: String?
    let plaidAccountID: String?
    let linkedCardName: String?
    let linkedCardInstitutionName: String?
    let linkedCardLastFourDigits: String?

    var sourceLabel: String {
        if let purchasedBy, !purchasedBy.isEmpty {
            return purchasedBy
        }
        return "Imported transaction"
    }
}

enum RecurringBillDetector {
    static let ignoredSuggestionIDsKey = "ignoredRecurringBillSuggestionIDs"

    static func detect(
        transactions: [Transaction],
        existingBills: [Bill],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [RecurringBillSuggestion] {
        let linkedCreditCardsByAccountID = linkedCreditCardsByPlaidAccountID(existingBills)
        let candidates = Dictionary(grouping: transactions.compactMap(DetectionTransaction.init)) {
            $0.normalizedMerchant
        }

        return candidates.compactMap { key, values -> RecurringBillSuggestion? in
            let uniqueValues = deduplicateSameDayTransactions(values, calendar: calendar)
                .sorted { $0.date < $1.date }
            guard uniqueValues.count >= 2 else { return nil }

            let amounts = uniqueValues.map(\.amount)
            guard amountsAreStable(amounts) else { return nil }
            let amount = roundedToCents(amounts.reduce(0, +) / Double(amounts.count))
            let category = inferredCategory(from: uniqueValues)
            let matchedBill = matchedExistingBill(
                key: key,
                amount: amount,
                category: category,
                existingBills: existingBills
            )

            if let matchedBill, matchedBill.lifecycleState != .canceled {
                return nil
            }

            let intervals = zip(uniqueValues, uniqueValues.dropFirst()).map {
                calendar.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0
            }
            guard let cadence = cadence(for: intervals, occurrenceCount: uniqueValues.count) else { return nil }

            let latest = uniqueValues.last!
            let nextDueDate = nextDate(after: latest.date, cadence: cadence, today: today, calendar: calendar)
            let confidence = confidenceScore(
                occurrenceCount: uniqueValues.count,
                amounts: amounts,
                intervals: intervals,
                cadence: cadence
            )

            return RecurringBillSuggestion(
                id: key,
                title: latest.displayName,
                normalizedMerchant: key,
                kind: inferredKind(from: uniqueValues, category: category),
                category: category,
                amount: amount,
                nextDueDate: nextDueDate,
                cadence: cadence,
                transactionCount: uniqueValues.count,
                confidence: confidence,
                latestTransactionDate: latest.date,
                matchedBillID: matchedBill?.id,
                matchedBillLifecycleState: matchedBill?.lifecycleState,
                evidence: uniqueValues.map { transaction in
                    let linkedCard = transaction.plaidAccountID.flatMap { linkedCreditCardsByAccountID[$0] }
                    return transaction.evidence(linkedCard: linkedCard)
                }
            )
        }
        .filter { $0.confidence >= 0.68 }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.latestTransactionDate > $1.latestTransactionDate
            }
            return $0.confidence > $1.confidence
        }
    }

    static func normalizedMerchantName(_ value: String?) -> String? {
        guard let value else { return nil }
        let lowercased = value.lowercased()
        let keptScalars = lowercased.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let words = String(keptScalars)
            .split(separator: " ")
            .map(String.init)
            .filter { word in
                !["inc", "llc", "com", "the", "payment", "autopay"].contains(word)
                    && !word.allSatisfy(\.isNumber)
            }

        let normalized = words.joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    private static func matchedExistingBill(
        key: String,
        amount: Double,
        category: BillCategory,
        existingBills: [Bill]
    ) -> Bill? {
        let candidates = existingBills.filter { $0.category != .creditCard }
        let keyTokens = Set(key.split(separator: " ").map(String.init))

        if let nameMatch = candidates.first(where: { bill in
            guard let billKey = normalizedMerchantName(bill.name) else { return false }
            if billKey == key || billKey.contains(key) || key.contains(billKey) {
                return true
            }
            let billTokens = Set(billKey.split(separator: " ").map(String.init))
            let overlap = keyTokens.intersection(billTokens).count
            return overlap >= min(2, min(keyTokens.count, billTokens.count))
        }) {
            return nameMatch
        }

        return candidates.first { bill in
            guard let billAmount = bill.amount else { return false }
            let tolerance = max(2.0, amount * 0.03)
            let amountMatches = abs(billAmount - amount) <= tolerance
            let categoryMatches = bill.category == category
                || bill.category?.isSubscriptionCategory == category.isSubscriptionCategory
                || bill.recurrenceInterval != nil
            return amountMatches && categoryMatches
        }
    }

    private static func linkedCreditCardsByPlaidAccountID(_ bills: [Bill]) -> [String: Bill] {
        Dictionary(
            bills.compactMap { bill -> (String, Bill)? in
                guard bill.category == .creditCard,
                      let plaidAccountID = bill.plaidAccountID?.nilIfBlank else {
                    return nil
                }
                return (plaidAccountID, bill)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func deduplicateSameDayTransactions(
        _ transactions: [DetectionTransaction],
        calendar: Calendar
    ) -> [DetectionTransaction] {
        var seen = Set<String>()
        return transactions.filter { transaction in
            let dateKey = calendar.startOfDay(for: transaction.date).timeIntervalSinceReferenceDate
            let amountKey = Int((transaction.amount * 100).rounded())
            return seen.insert("\(dateKey):\(amountKey)").inserted
        }
    }

    private static func amountsAreStable(_ amounts: [Double]) -> Bool {
        guard let average = amounts.average, average > 0 else { return false }
        let tolerance = max(2.0, average * 0.18)
        return amounts.allSatisfy { abs($0 - average) <= tolerance }
    }

    private static func cadence(for intervals: [Int], occurrenceCount: Int) -> RecurringBillCadence? {
        guard !intervals.isEmpty else { return nil }
        let median = intervals.sorted()[intervals.count / 2]

        if (5...9).contains(median), occurrenceCount >= 3 {
            return .weekly
        }
        if (11...17).contains(median), occurrenceCount >= 3 {
            return .biweekly
        }
        if (24...38).contains(median) {
            return .monthly
        }
        if (330...400).contains(median) {
            return .annual
        }
        return nil
    }

    private static func nextDate(
        after date: Date,
        cadence: RecurringBillCadence,
        today: Date,
        calendar: Calendar
    ) -> Date {
        var next = advance(date, cadence: cadence, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)

        while next < todayStart {
            next = advance(next, cadence: cadence, calendar: calendar)
        }

        return next
    }

    private static func advance(
        _ date: Date,
        cadence: RecurringBillCadence,
        calendar: Calendar
    ) -> Date {
        switch cadence {
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .annual:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    private static func confidenceScore(
        occurrenceCount: Int,
        amounts: [Double],
        intervals: [Int],
        cadence: RecurringBillCadence
    ) -> Double {
        let countScore = min(Double(occurrenceCount) / 5.0, 1.0)
        let amountScore = amountStabilityScore(amounts)
        let intervalScore = intervalStabilityScore(intervals, cadence: cadence)
        return min(1.0, (countScore * 0.35) + (amountScore * 0.4) + (intervalScore * 0.25))
    }

    private static func amountStabilityScore(_ amounts: [Double]) -> Double {
        guard let average = amounts.average, average > 0 else { return 0 }
        let largestDelta = amounts.map { abs($0 - average) }.max() ?? 0
        return max(0, 1 - (largestDelta / max(average, 1)))
    }

    private static func intervalStabilityScore(_ intervals: [Int], cadence: RecurringBillCadence) -> Double {
        guard !intervals.isEmpty else { return 0 }
        let expected: Double
        switch cadence {
        case .weekly:
            expected = 7
        case .biweekly:
            expected = 14
        case .monthly:
            expected = 30
        case .annual:
            expected = 365
        }

        let averageDelta = intervals
            .map { abs(Double($0) - expected) }
            .reduce(0, +) / Double(intervals.count)
        return max(0, 1 - (averageDelta / max(expected, 1)))
    }

    private static func inferredCategory(from transactions: [DetectionTransaction]) -> BillCategory {
        let joined = transactions
            .flatMap { [$0.displayName, $0.category ?? ""] }
            .joined(separator: " ")
            .lowercased()

        if joined.contains("netflix") || joined.contains("hulu") || joined.contains("spotify") || joined.contains("stream") {
            return .streaming
        }
        if joined.contains("software") || joined.contains("icloud") || joined.contains("github") || joined.contains("adobe") {
            return .software
        }
        if joined.contains("membership") || joined.contains("gym") || joined.contains("club") {
            return .membership
        }
        if joined.contains("loan") || joined.contains("auto") || joined.contains("car payment") || joined.contains("wells fargo auto") {
            return .loans
        }
        if joined.contains("insurance") {
            return .insurance
        }
        if joined.contains("internet") || joined.contains("wifi") || joined.contains("broadband") {
            return .internet
        }
        if joined.contains("phone") || joined.contains("wireless") || joined.contains("mobile") {
            return .phone
        }
        if joined.contains("utility") || joined.contains("electric") || joined.contains("water") || joined.contains("gas") {
            return .utilities
        }
        return .subscription
    }

    private static func inferredKind(
        from transactions: [DetectionTransaction],
        category: BillCategory
    ) -> RecurringChargeKind {
        let joined = transactions
            .flatMap { [$0.displayName, $0.category ?? ""] }
            .joined(separator: " ")
            .lowercased()

        if category == .rent || category == .mortgage || joined.contains("rent") || joined.contains("mortgage") {
            return .housing
        }
        if category == .loans || joined.contains("loan") || joined.contains("auto") || joined.contains("car payment") {
            return .loan
        }
        if category == .insurance || joined.contains("insurance") {
            return .insurance
        }
        if category == .utilities || category == .phone || category == .internet {
            return .utility
        }
        if category == .membership {
            return .membership
        }
        if category == .homeServices || joined.contains("service") {
            return .service
        }
        if category.isSubscriptionCategory {
            return .subscription
        }
        return .bill
    }

    private static func roundedToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

private struct DetectionTransaction {
    let date: Date
    let amount: Double
    let displayName: String
    let normalizedMerchant: String
    let category: String?
    let purchasedBy: String?
    let plaidTransactionID: String?
    let plaidAccountID: String?

    init?(_ transaction: Transaction) {
        guard
            transaction.plaidIsPending != true,
            let date = transaction.transactionDate ?? transaction.clearingDate,
            let amount = transaction.amountUSD,
            amount > 0
        else {
            return nil
        }

        let displayName = transaction.friendlyName?.nilIfBlank
            ?? transaction.merchant?.nilIfBlank
            ?? transaction.transactionDescription?.nilIfBlank
        guard let displayName else { return nil }

        let category = transaction.category
        let exclusionText = "\(displayName) \(category ?? "")".lowercased()
        guard !Self.isLikelyTransferOrPayment(exclusionText) else { return nil }
        guard let normalizedMerchant = RecurringBillDetector.normalizedMerchantName(displayName) else { return nil }

        self.date = date
        self.amount = amount
        self.displayName = displayName
        self.normalizedMerchant = normalizedMerchant
        self.category = category
        purchasedBy = transaction.purchasedBy
        plaidTransactionID = transaction.plaidTransactionID
        plaidAccountID = transaction.plaidAccountID
    }

    func evidence(linkedCard: Bill?) -> RecurringChargeEvidence {
        let dateKey = Int(date.timeIntervalSinceReferenceDate)
        let amountKey = Int((amount * 100).rounded())
        let accountKey = plaidAccountID ?? purchasedBy ?? displayName
        let transactionKey = plaidTransactionID ?? "\(dateKey)|\(amountKey)|\(accountKey)"
        return RecurringChargeEvidence(
            id: "\(normalizedMerchant)|\(transactionKey)",
            date: date,
            amount: amount,
            displayName: displayName,
            category: category,
            purchasedBy: purchasedBy,
            plaidTransactionID: plaidTransactionID,
            plaidAccountID: plaidAccountID,
            linkedCardName: linkedCard?.name?.nilIfBlank,
            linkedCardInstitutionName: linkedCard?.creditCardDetails?.issuerName?.nilIfBlank,
            linkedCardLastFourDigits: linkedCard?.creditCardDetails?.lastFourDigits?.lastFourDigits
        )
    }

    private static func isLikelyTransferOrPayment(_ value: String) -> Bool {
        let excluded = [
            "payment thank you",
            "credit card payment",
            "online payment",
            "ach payment",
            "transfer",
            "deposit",
            "payroll",
            "venmo",
            "zelle",
            "cash app"
        ]
        return excluded.contains { value.contains($0) }
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var lastFourDigits: String? {
        let digits = filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(4))
    }
}
