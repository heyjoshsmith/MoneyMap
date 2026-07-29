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

        for bill in bills {
            let previousDueDate = bill.dueDate
            let previousDatePaid = bill.datePaid
            let previousStatus = bill.status

            if let payment = currentCyclePaymentTransaction(
                for: bill,
                in: transactions,
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
        guard bill.category != .creditCard else {
            return bill.transactions ?? []
        }

        let directTransactions = bill.transactions ?? []
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
        guard bill.lifecycleState == .active,
              bill.category != .creditCard,
              bill.status != .paid,
              let dueDate = bill.dueDate else {
            return nil
        }

        let dueDay = calendar.startOfDay(for: dueDate)
        let todayDay = calendar.startOfDay(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -3, to: dueDay) ?? dueDay
        let graceDays = max(bill.gracePeriodDays ?? 0, 3)
        let windowEnd = calendar.date(byAdding: .day, value: graceDays, to: dueDay) ?? dueDay

        return transactions
            .filter { transaction in
                guard isPaymentCandidate(transaction),
                      amountMatches(bill: bill, transaction: transaction),
                      textMatches(bill: bill, transaction: transaction),
                      let date = transactionDate(for: transaction) else {
                    return false
                }

                let transactionDay = calendar.startOfDay(for: date)
                return transactionDay >= windowStart &&
                    transactionDay <= min(windowEnd, todayDay)
            }
            .sorted { lhs, rhs in
                (transactionDate(for: lhs) ?? .distantPast) > (transactionDate(for: rhs) ?? .distantPast)
            }
            .first
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

    private static func isPaymentCandidate(_ transaction: Transaction) -> Bool {
        guard transaction.plaidIsPending != true,
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
        guard let billName = bill.name?.nilIfBlank else { return false }
        let billText = normalizedText(billName)
        guard !billText.isEmpty else { return false }

        return transactionMatchTexts(for: transaction).contains { transactionText in
            guard !transactionText.isEmpty else { return false }
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
