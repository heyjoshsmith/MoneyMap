//
//  BillPaymentMatcher.swift
//  MoneyMap
//
//  Created by Codex on 7/22/26.
//

import Foundation

enum BillPaymentMatcher {
    static func refreshStatuses(
        for bills: [Bill],
        transactions: [Transaction],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        var didChange = false
        let candidates = preparedPayments(transactions, relatedTransactions: bills.flatMap { $0.transactions ?? [] })

        for bill in bills {
            let previousDueDate = bill.dueDate
            let previousDatePaid = bill.datePaid
            let previousStatus = bill.status

            if let payment = currentCyclePaymentTransaction(
                for: bill,
                candidates: candidates,
                today: today,
                calendar: calendar
            ) {
                bill.datePaid = calendar.startOfDay(for: transactionDate(for: payment) ?? today)
                bill.status = .paid
            }

            bill.checkStatus()

            if previousDueDate != bill.dueDate ||
                previousDatePaid != bill.datePaid ||
                previousStatus != bill.status {
                didChange = true
            }
        }

        return didChange
    }

    static func matchedHistoryTransactions(
        for bill: Bill,
        in transactions: [Transaction],
        calendar: Calendar = .current
    ) -> [Transaction] {
        let directTransactions = connectedTransactions(for: bill, in: transactions)

        guard bill.category != .creditCard else {
            return directTransactions
        }

        var matched = transactions.filter { transaction in
            isPaymentCandidate(transaction) &&
                amountMatches(bill: bill, transaction: transaction) &&
                textMatches(bill: bill, transaction: transaction)
        }

        var seenKeys = Set<String>()
        matched.append(contentsOf: directTransactions)
        return matched
            .filter { transaction in
                seenKeys.insert(identityKey(for: transaction)).inserted
            }
            .sorted { lhs, rhs in
                (transactionDate(for: lhs) ?? .distantPast) > (transactionDate(for: rhs) ?? .distantPast)
            }
    }

    static func currentCyclePaymentTransaction(
        for bill: Bill,
        in transactions: [Transaction],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Transaction? {
        currentCyclePaymentTransaction(
            for: bill,
            candidates: preparedPayments(transactions, relatedTransactions: bill.transactions ?? []),
            today: today,
            calendar: calendar
        )
    }

    private struct PreparedPayment {
        let transaction: Transaction
        let date: Date
        let linkedBillID: UUID?
        let creditCardID: UUID?
        let canInfer: Bool
    }

    private static func preparedPayments(_ transactions: [Transaction], relatedTransactions: [Transaction]) -> [PreparedPayment] {
        var seen = Set<ObjectIdentifier>()
        let inferable = Set(transactions.map(ObjectIdentifier.init))
        return (transactions + relatedTransactions).compactMap { transaction in
            guard seen.insert(ObjectIdentifier(transaction)).inserted,
                  isPaymentCandidate(transaction),
                  let date = transactionDate(for: transaction) else { return nil }
            return PreparedPayment(transaction: transaction, date: date,
                                   linkedBillID: transaction.linkedBillID,
                                   creditCardID: transaction.creditCard?.id,
                                   canInfer: inferable.contains(ObjectIdentifier(transaction)))
        }
    }

    private static func currentCyclePaymentTransaction(
        for bill: Bill,
        candidates: [PreparedPayment],
        today: Date,
        calendar: Calendar
    ) -> Transaction? {
        guard bill.lifecycleState == .active, bill.category != .creditCard,
              bill.status != .paid, let dueDate = bill.dueDate else { return nil }
        let dueDay = calendar.startOfDay(for: dueDate)
        let todayDay = calendar.startOfDay(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -3, to: dueDay) ?? dueDay
        let windowEnd = calendar.date(byAdding: .day, value: max(bill.gracePeriodDays ?? 0, 3), to: dueDay) ?? dueDay
        let lastDay = min(windowEnd, todayDay)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        let billTexts = billMatchTexts(for: bill)
        var direct: PreparedPayment?
        var inferred: PreparedPayment?
        for candidate in candidates {
            guard candidate.date >= windowStart, candidate.date < endExclusive else { continue }
            if candidate.linkedBillID == bill.id || candidate.creditCardID == bill.id {
                if direct == nil || candidate.date > direct!.date { direct = candidate }
            } else if candidate.canInfer, direct == nil,
                      (inferred == nil || candidate.date > inferred!.date),
                      amountMatches(bill: bill, transaction: candidate.transaction),
                      textMatches(billTexts: billTexts, transaction: candidate.transaction) {
                inferred = candidate
            }
        }
        return (direct ?? inferred)?.transaction
    }

    static func connectedTransactions(for bill: Bill, in transactions: [Transaction]) -> [Transaction] {
        var seenKeys = Set<String>()
        return ((bill.transactions ?? []) + transactions)
            .filter { isConnected($0, to: bill) }
            .filter { seenKeys.insert(identityKey(for: $0)).inserted }
            .sorted(by: mostRecentFirst)
    }

    static func isConnected(_ transaction: Transaction, to bill: Bill) -> Bool {
        transaction.linkedBillID == bill.id || transaction.creditCard?.id == bill.id
    }

    static func identityKey(for transaction: Transaction) -> String {
        if let plaidTransactionID = transaction.plaidTransactionID?.nilIfBlank {
            return "plaid:\(plaidTransactionID)"
        }

        let date = transactionDate(for: transaction)?.timeIntervalSinceReferenceDate ?? 0
        let amount = transaction.amountUSD ?? 0
        let title = displayTitle(for: transaction) ?? ""
        return "fallback:\(Int(date))|\(Int((amount * 100).rounded()))|\(normalizedText(title))"
    }

    static func transactionDate(for transaction: Transaction) -> Date? {
        transaction.transactionDate ?? transaction.clearingDate ?? transaction.plaidImportedAt
    }

    private static func mostRecentFirst(lhs: Transaction, rhs: Transaction) -> Bool {
        (transactionDate(for: lhs) ?? .distantPast) > (transactionDate(for: rhs) ?? .distantPast)
    }

    private static func isPaymentCandidate(_ transaction: Transaction) -> Bool {
        guard transaction.plaidIsPending != true,
              transaction.plaidBankRemovedAt == nil,
              let amount = transaction.amountUSD,
              amount > 0,
              transactionDate(for: transaction) != nil else {
            return false
        }

        let text = [
            transaction.friendlyName,
            transaction.merchant,
            transaction.transactionDescription,
            transaction.category,
            transaction.type
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        let excludedTerms = [
            "payment thank you",
            "credit card payment",
            "online payment",
            "ach payment",
            "transfer",
            "deposit",
            "payroll"
        ]
        return !excludedTerms.contains { text.contains($0) }
    }

    private static func amountMatches(bill: Bill, transaction: Transaction) -> Bool {
        guard let billAmount = bill.amount, billAmount > 0 else { return true }
        guard let transactionAmount = transaction.amountUSD else { return false }

        let tolerance = max(1.0, billAmount * 0.08)
        return abs(transactionAmount - billAmount) <= tolerance
    }

    private static func textMatches(bill: Bill, transaction: Transaction) -> Bool {
        textMatches(billTexts: billMatchTexts(for: bill), transaction: transaction)
    }

    private static func textMatches(billTexts: [String], transaction: Transaction) -> Bool {
        guard !billTexts.isEmpty else { return false }

        return transactionMatchTexts(for: transaction).contains { transactionText in
            billTexts.contains { billText in
                textsMatch(billText: billText, transactionText: transactionText)
            }
        }
    }

    private static func billMatchTexts(for bill: Bill) -> [String] {
        var seen = Set<String>()
        let values = [bill.name] + (bill.transactions ?? []).flatMap { transaction in
            [
                transaction.friendlyName,
                transaction.merchant,
                transaction.transactionDescription
            ]
        }

        return values
            .compactMap { $0?.nilIfBlank }
            .map(normalizedText)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func textsMatch(billText: String, transactionText: String) -> Bool {
        guard !billText.isEmpty, !transactionText.isEmpty else { return false }
        if transactionText == billText ||
            transactionText.contains(billText) ||
            billText.contains(transactionText) {
            return true
        }

        let billTokens = Set(significantTokens(in: billText))
        let transactionTokens = Set(significantTokens(in: transactionText))
        guard !billTokens.isEmpty, !transactionTokens.isEmpty else { return false }
        let overlap = billTokens.intersection(transactionTokens).count
        return min(billTokens.count, transactionTokens.count) <= 2 ? overlap >= 1 : overlap >= 2
    }

    private static func transactionMatchTexts(for transaction: Transaction) -> [String] {
        [
            transaction.friendlyName,
            transaction.merchant,
            transaction.transactionDescription
        ]
        .compactMap { $0?.nilIfBlank }
        .map(normalizedText)
    }

    private static func displayTitle(for transaction: Transaction) -> String? {
        transaction.friendlyName?.nilIfBlank ??
            transaction.merchant?.nilIfBlank ??
            transaction.transactionDescription?.nilIfBlank
    }

    private static func normalizedText(_ value: String) -> String {
        let lowercased = value.lowercased()
        let keptScalars = lowercased.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(keptScalars)
            .split(separator: " ")
            .map(String.init)
            .filter { !ignoredTokenWords.contains($0) && !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }

    private static func significantTokens(in value: String) -> [String] {
        value
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !ignoredTokenWords.contains($0) }
    }

    private static let ignoredTokenWords: Set<String> = [
        "the",
        "inc",
        "llc",
        "com",
        "payment",
        "autopay",
        "auto",
        "bill",
        "billing",
        "subscription",
        "service",
        "services",
        "company",
        "corp"
    ]
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
