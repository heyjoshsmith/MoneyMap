//
//  TransactionImport.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SwiftData

public struct TransactionCSVImportPreviewRow: Identifiable, Hashable {
    public let id = UUID()
    public let dateText: String
    public let merchant: String
    public let amount: Double?
    public let category: String

    public init(dateText: String, merchant: String, amount: Double?, category: String) {
        self.dateText = dateText
        self.merchant = merchant
        self.amount = amount
        self.category = category
    }
}

public struct TransactionCSVImportFileSummary: Identifiable, Hashable {
    public let id = UUID()
    public let fileName: String
    public let totalRows: Int
    public let importableRows: Int
    public let duplicateRows: Int
    public let invalidRows: Int

    public init(fileName: String, totalRows: Int, importableRows: Int, duplicateRows: Int, invalidRows: Int) {
        self.fileName = fileName
        self.totalRows = totalRows
        self.importableRows = importableRows
        self.duplicateRows = duplicateRows
        self.invalidRows = invalidRows
    }
}

public struct TransactionCSVImportPreview: Hashable {
    public let files: [TransactionCSVImportFileSummary]
    public let sampleRows: [TransactionCSVImportPreviewRow]

    public init(files: [TransactionCSVImportFileSummary], sampleRows: [TransactionCSVImportPreviewRow]) {
        self.files = files
        self.sampleRows = sampleRows
    }

    public var fileCount: Int { files.count }
    public var totalRows: Int { files.reduce(0) { $0 + $1.totalRows } }
    public var importableRows: Int { files.reduce(0) { $0 + $1.importableRows } }
    public var duplicateRows: Int { files.reduce(0) { $0 + $1.duplicateRows } }
    public var invalidRows: Int { files.reduce(0) { $0 + $1.invalidRows } }
}

public struct TransactionCSVImportSummary: Hashable {
    public let fileCount: Int
    public let totalRows: Int
    public let importedRows: Int
    public let duplicateRows: Int
    public let invalidRows: Int

    public init(fileCount: Int, totalRows: Int, importedRows: Int, duplicateRows: Int, invalidRows: Int) {
        self.fileCount = fileCount
        self.totalRows = totalRows
        self.importedRows = importedRows
        self.duplicateRows = duplicateRows
        self.invalidRows = invalidRows
    }
}

public func importTransactions(fromCSVAt url: URL, to bill: Bill, context: ModelContext) throws -> Int {
    try importTransactionCSVFiles(from: [url], to: bill, context: context).importedRows
}

public func previewTransactionCSVFiles(from urls: [URL], for bill: Bill) throws -> TransactionCSVImportPreview {
    let plan = try makeImportPlan(from: urls, for: bill)
    return plan.preview
}

public func importTransactionCSVFiles(from urls: [URL], to bill: Bill, context: ModelContext) throws -> TransactionCSVImportSummary {
    let plan = try makeImportPlan(from: urls, for: bill)

    for candidate in plan.candidates {
        let transaction = candidate.transaction
        transaction.creditCard = bill

        if let merchant = transaction.merchant,
           let existingFriendly = (bill.transactions ?? []).first(where: {
               $0.merchant == merchant && ($0.friendlyName?.isEmpty == false)
           })?.friendlyName {
            transaction.friendlyName = existingFriendly
        }

        context.insert(transaction)
    }

    try context.save()

    return TransactionCSVImportSummary(
        fileCount: plan.preview.fileCount,
        totalRows: plan.preview.totalRows,
        importedRows: plan.preview.importableRows,
        duplicateRows: plan.preview.duplicateRows,
        invalidRows: plan.preview.invalidRows
    )
}

private struct TransactionImportCandidate {
    let transaction: Transaction
}

private struct TransactionImportPlan {
    let preview: TransactionCSVImportPreview
    let candidates: [TransactionImportCandidate]
}

private func makeImportPlan(from urls: [URL], for bill: Bill) throws -> TransactionImportPlan {
    var knownSignatures = Set((bill.transactions ?? []).map(transactionSignature))
    var fileSummaries: [TransactionCSVImportFileSummary] = []
    var candidates: [TransactionImportCandidate] = []
    var sampleRows: [TransactionCSVImportPreviewRow] = []

    for url in urls {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSVRows(content)
        guard let headerRow = rows.first, rows.count > 1 else {
            fileSummaries.append(
                TransactionCSVImportFileSummary(
                    fileName: url.lastPathComponent,
                    totalRows: max(rows.count - 1, 0),
                    importableRows: 0,
                    duplicateRows: 0,
                    invalidRows: max(rows.count, 1)
                )
            )
            continue
        }

        let header = headerRow.map { sanitizeCSVField($0) }
        let dataRows = rows.dropFirst()
        var importableRows = 0
        var duplicateRows = 0
        var invalidRows = 0

        for row in dataRows {
            guard row.count == header.count else {
                invalidRows += 1
                continue
            }

            var dict = [String: String]()
            for (index, key) in header.enumerated() {
                dict[key] = sanitizeCSVField(row[index])
            }

            guard let transaction = createTransaction(from: dict) else {
                invalidRows += 1
                continue
            }

            let signature = transactionSignature(transaction)
            guard knownSignatures.insert(signature).inserted else {
                duplicateRows += 1
                continue
            }

            importableRows += 1
            candidates.append(TransactionImportCandidate(transaction: transaction))

            if sampleRows.count < 5 {
                sampleRows.append(previewRow(from: transaction))
            }
        }

        fileSummaries.append(
            TransactionCSVImportFileSummary(
                fileName: url.lastPathComponent,
                totalRows: dataRows.count,
                importableRows: importableRows,
                duplicateRows: duplicateRows,
                invalidRows: invalidRows
            )
        )
    }

    return TransactionImportPlan(
        preview: TransactionCSVImportPreview(files: fileSummaries, sampleRows: sampleRows),
        candidates: candidates
    )
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
    let hasAppleCardColumns = [
        "Transaction Date",
        "Description",
        "Merchant",
        "Amount (USD)"
    ].allSatisfy { dict.keys.contains($0) }

    guard hasAppleCardColumns else { return nil }

    return Transaction(
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

private func previewRow(from transaction: Transaction) -> TransactionCSVImportPreviewRow {
    TransactionCSVImportPreviewRow(
        dateText: transaction.transactionDate?.formatted(date: .abbreviated, time: .omitted)
            ?? transaction.clearingDate?.formatted(date: .abbreviated, time: .omitted)
            ?? "No date",
        merchant: transaction.merchant?.isEmpty == false
            ? transaction.merchant ?? "Unknown merchant"
            : transaction.transactionDescription ?? "Unknown merchant",
        amount: transaction.amountUSD,
        category: transaction.category?.isEmpty == false ? transaction.category ?? "Uncategorized" : "Uncategorized"
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
