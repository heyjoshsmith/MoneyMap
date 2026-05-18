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

    // Build items
    func line(for bill: Bill) -> (spoken: String, visual: String) {
        let name = bill.name ?? "Unnamed bill"
        let amount = bill.amount ?? 0
        let amountStr = MoneyMapFormatters.currencyString(for: amount)
        let dateStr = bill.dueDate.map { MoneyMapFormatters.mediumDateString(for: $0) } ?? "no due date"
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let upper = calendar.date(byAdding: .day, value: days, to: today) else {
            return .result(value: "Couldn't calculate the date range.", dialog: IntentDialog(stringLiteral: "Couldn't calculate the date range."))
        }

        do {
            let bills = try MoneyMapBillStore.fetchBills().filter { bill in
                guard bill.datePaid == nil, let dueDate = bill.dueDate else { return false }
                return dueDate >= today && dueDate <= upper
            }
            let summaries = summarize(bills: bills)
            return .result(value: summaries.visual, dialog: IntentDialog(stringLiteral: summaries.spoken))
        } catch {
            return .result(value: "Couldn't open the data store: \(error.localizedDescription)", dialog: IntentDialog(stringLiteral: "Couldn't open the data store: \(error.localizedDescription)"))
        }
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
            ),
            AppShortcut(
                intent: OpenBillIntent(),
                phrases: [
                    "Open a bill in \(.applicationName)",
                    "Open my bill in \(.applicationName)"
                ],
                shortTitle: "Open Bill",
                systemImageName: "doc.text.magnifyingglass"
            ),
            AppShortcut(
                intent: AddBillIntent(),
                phrases: [
                    "Add a bill in \(.applicationName)",
                    "Create a bill in \(.applicationName)",
                    "Add a credit card in \(.applicationName)"
                ],
                shortTitle: "Add Bill",
                systemImageName: "plus.circle"
            ),
            AppShortcut(
                intent: OpenRecommendationsIntent(),
                phrases: [
                    "Open recommendations in \(.applicationName)",
                    "Show paycheck recommendations in \(.applicationName)"
                ],
                shortTitle: "Recommendations",
                systemImageName: "wand.and.stars"
            ),
            AppShortcut(
                intent: GetPaycheckRecommendationIntent(),
                phrases: [
                    "What should I do with my paycheck in \(.applicationName)",
                    "Plan my paycheck in \(.applicationName)"
                ],
                shortTitle: "Paycheck Plan",
                systemImageName: "banknote"
            ),
            AppShortcut(
                intent: ComparePaycheckScenariosIntent(),
                phrases: [
                    "Compare paycheck scenarios in \(.applicationName)",
                    "What if I had more paycheck cash in \(.applicationName)"
                ],
                shortTitle: "Compare Scenarios",
                systemImageName: "arrow.left.arrow.right"
            ),
            AppShortcut(
                intent: ShowCardUtilizationIntent(),
                phrases: [
                    "Show card utilization in \(.applicationName)",
                    "What's my card utilization in \(.applicationName)"
                ],
                shortTitle: "Card Utilization",
                systemImageName: "chart.pie"
            ),
            AppShortcut(
                intent: MarkBillPaidIntent(),
                phrases: [
                    "Mark bill paid in \(.applicationName)",
                    "Pay a bill in \(.applicationName)"
                ],
                shortTitle: "Mark Paid",
                systemImageName: "checkmark.circle"
            ),
            AppShortcut(
                intent: OpenNextDueBillIntent(),
                phrases: [
                    "Open my next due bill in \(.applicationName)",
                    "Show next bill due in \(.applicationName)"
                ],
                shortTitle: "Next Due Bill",
                systemImageName: "calendar.badge.clock"
            ),
            AppShortcut(
                intent: PayRecommendedCardIntent(),
                phrases: [
                    "Pay recommended card amount in \(.applicationName)",
                    "Apply recommended payment in \(.applicationName)"
                ],
                shortTitle: "Pay Recommended",
                systemImageName: "creditcard.and.123"
            )
        ]
    }
}
