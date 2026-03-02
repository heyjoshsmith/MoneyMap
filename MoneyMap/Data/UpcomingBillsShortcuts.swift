// UpcomingBillsShortcuts.swift
// MoneyMap
//
// Adds an App Shortcut to report upcoming Bill models.

import Foundation
import AppIntents
import SwiftData

// Helper to build a human-friendly summary for both voice and visual output
fileprivate struct BillSummaries {
    let spoken: String
    let visual: String
}

fileprivate func summarize(bills: [Bill]) -> BillSummaries {
    // No results
    guard !bills.isEmpty else {
        return BillSummaries(
            spoken: "No upcoming bills.",
            visual: "You have no upcoming bills."
        )
    }

    // Sort by due date then name
    let sorted = bills.sorted { lhs, rhs in
        if let l = lhs.dueDate, let r = rhs.dueDate, l != r { return l < r }
        return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedAscending
    }

    // Limit for voice, but show more visually
    let voiceMax = 3
    let visualMax = 10

    let formatter = DateFormatter()
    formatter.dateStyle = .medium

    // Build items
    func line(for bill: Bill) -> (spoken: String, visual: String) {
        let name = bill.name ?? "Unnamed bill"
        let amount = bill.amount ?? 0
        let amountStr = NumberFormatter.currency.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
        let dateStr = bill.dueDate.map { formatter.string(from: $0) } ?? "no due date"
        return (
            spoken: "\(name) \(amountStr) on \(dateStr)",
            visual: "• \(name) — \(amountStr) — due \(dateStr)"
        )
    }

    // Spoken: concise headline + up to voiceMax items
    let spokenItems = sorted.prefix(voiceMax).map { line(for: $0).spoken }
    var spoken = "\(bills.count) bill\(bills.count == 1 ? "" : "s") coming up."
    if !spokenItems.isEmpty {
        spoken += " Next: " + spokenItems.joined(separator: "; ") + "."
        if bills.count > voiceMax { spoken += " And more." }
    }

    // Visual: a friendly list with up to visualMax items
    let visualItems = sorted.prefix(visualMax).map { line(for: $0).visual }
    var visual = "Upcoming bills (\(bills.count))\n" + visualItems.joined(separator: "\n")
    if bills.count > visualMax { visual += "\n…and more" }

    return BillSummaries(spoken: spoken, visual: visual)
}

extension NumberFormatter {
    static let currency: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        return nf
    }()
}

struct UpcomingBillsIntent: AppIntent {
    static var title: LocalizedStringResource = "Upcoming Bills"
    static var description = IntentDescription("Get a summary of bills due soon and not yet paid.")

    @Parameter(title: "Within Days")
    var withinDays: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Upcoming bills due within \(\.$withinDays)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let days = max(1, withinDays ?? 14)
        let now = Date()
        guard let upper = Calendar.current.date(byAdding: .day, value: days, to: now) else {
            return .result(value: "Couldn't calculate the date range.", dialog: IntentDialog(stringLiteral: "Couldn't calculate the date range."))
        }

        // Fetch from Swift Data using the shared app group store
        let modelContainer: ModelContainer
        do {
            modelContainer = try SharedModelContainerFactory.make()
        } catch {
            return .result(value: "Couldn't open the data store: \(error.localizedDescription)", dialog: IntentDialog(stringLiteral: "Couldn't open the data store: \(error.localizedDescription)"))
        }
        let context = ModelContext(modelContainer)

        // Build predicate: dueDate in [now, upper], and (datePaid == nil)
        let predicate = #Predicate<Bill> { bill in
            if let due = bill.dueDate {
                return due >= now && due <= upper && bill.datePaid == nil
            } else {
                return false
            }
        }

        let descriptor = FetchDescriptor<Bill>(predicate: predicate)
        let results = try context.fetch(descriptor)

        let summaries = summarize(bills: results)
        return .result(value: summaries.visual, dialog: IntentDialog(stringLiteral: summaries.spoken))
    }
}

struct MoneyMapShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: UpcomingBillsIntent(),
                phrases: [
                    "What bills are due soon in \(.applicationName)",
                    "Upcoming bills in \(.applicationName)",
                    "Bills due in \(.applicationName)"
                ],
                shortTitle: "Upcoming Bills",
                systemImageName: "calendar.badge.exclamationmark"
            )
        ]
    }
}

