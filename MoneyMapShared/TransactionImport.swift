//
//  TransactionImport.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SwiftData

public func importTransactions(fromCSVAt url: URL, to bill: Bill, context: ModelContext) throws -> Int {
    let content = try String(contentsOf: url, encoding: .utf8)
    let rows = parseCSVRows(content)
    guard let headerRow = rows.first, rows.count > 1 else { return 0 }

    let header = headerRow.map { sanitizeCSVField($0) }
    let dataRows = rows.dropFirst()
    var importedCount = 0
    var knownSignatures = Set((bill.transactions ?? []).map(transactionSignature))

    for row in dataRows {
        guard row.count == header.count else { continue }

        var dict = [String: String]()
        for (index, key) in header.enumerated() {
            dict[key] = sanitizeCSVField(row[index])
        }

        guard let transaction = createTransaction(from: dict) else { continue }
        let signature = transactionSignature(transaction)
        guard knownSignatures.insert(signature).inserted else { continue }

        transaction.creditCard = bill

        if let merchant = transaction.merchant,
           let existingFriendly = (bill.transactions ?? []).first(where: {
               $0.merchant == merchant && ($0.friendlyName?.isEmpty == false)
           })?.friendlyName {
            transaction.friendlyName = existingFriendly
        }

        context.insert(transaction)
        importedCount += 1
    }

    try context.save()
    return importedCount
}

private struct TransactionSignature: Hashable {
    let transactionDate: TimeInterval?
    let clearingDate: TimeInterval?
    let transactionDescription: String
    let merchant: String
    let category: String
    let type: String
    let amountInCents: Int?
    let purchasedBy: String
}

private func createTransaction(from dict: [String: String]) -> Transaction? {
    Transaction(
        transactionDate: dict["Transaction Date"]?.replacingOccurrences(of: "\"", with: ""),
        clearingDate: dict["Clearing Date"]?.replacingOccurrences(of: "\"", with: ""),
        transactionDescription: dict["Description"]?.replacingOccurrences(of: "\"", with: ""),
        merchant: dict["Merchant"]?.replacingOccurrences(of: "\"", with: ""),
        category: dict["Category"]?.replacingOccurrences(of: "\"", with: ""),
        type: dict["Type"]?.replacingOccurrences(of: "\"", with: ""),
        amountUSD: Double(dict["Amount (USD)"]?.replacingOccurrences(of: "\"", with: "") ?? ""),
        purchasedBy: dict["Purchased By"]?.replacingOccurrences(of: "\"", with: "")
    )
}

private func transactionSignature(_ transaction: Transaction) -> TransactionSignature {
    TransactionSignature(
        transactionDate: transaction.transactionDate.map { Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate },
        clearingDate: transaction.clearingDate.map { Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate },
        transactionDescription: normalized(transaction.transactionDescription),
        merchant: normalized(transaction.merchant),
        category: normalized(transaction.category),
        type: normalized(transaction.type),
        amountInCents: transaction.amountUSD.map { Int(($0 * 100).rounded()) },
        purchasedBy: normalized(transaction.purchasedBy)
    )
}

private func normalized(_ value: String?) -> String {
    value?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
}

private func sanitizeCSVField(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\u{FEFF}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseCSVRows(_ input: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var isInsideQuotes = false
    var index = input.startIndex

    while index < input.endIndex {
        let char = input[index]

        if char == "\"" {
            let next = input.index(after: index)
            if isInsideQuotes, next < input.endIndex, input[next] == "\"" {
                field.append("\"")
                index = next
            } else {
                isInsideQuotes.toggle()
            }
        } else if char == "," && !isInsideQuotes {
            row.append(field)
            field = ""
        } else if (char == "\n" || char == "\r") && !isInsideQuotes {
            row.append(field)
            let cleaned = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if cleaned.contains(where: { !$0.isEmpty }) {
                rows.append(cleaned)
            }
            row = []
            field = ""

            if char == "\r" {
                let next = input.index(after: index)
                if next < input.endIndex, input[next] == "\n" {
                    index = next
                }
            }
        } else {
            field.append(char)
        }

        index = input.index(after: index)
    }

    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        let cleaned = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if cleaned.contains(where: { !$0.isEmpty }) {
            rows.append(cleaned)
        }
    }

    return rows
}
