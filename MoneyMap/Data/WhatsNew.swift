//
//  WhatsNew.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import Foundation

struct WhatsNewRelease: Identifiable {
    let id: String
    let version: String
    let releaseDate: String
    let highlights: [String]
}

enum MoneyMapVersion {
    static var marketingVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }
}

enum WhatsNewRepository {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            id: "1.2.0-2026-04-27",
            version: "1.2.0",
            releaseDate: "April 27, 2026",
            highlights: [
                "New paycheck planning engine with balanced, avalanche, snowball, due-date, utilization, and statement-driven payoff modes.",
                "Recommendations screen now compares lean, planned, and stretch paycheck scenarios and can apply goal contributions or card payments directly.",
                "Goal progress notifications now warn when savings goals fall behind schedule.",
                "New Siri + Shortcuts actions to add bills, open goals, open recommendations, and summarize paycheck plans.",
                "Spotlight now indexes goals and paycheck recommendations alongside bills.",
                "New widgets for next payday countdown, next bill due, and upcoming bills list.",
                "New pay-cycle Live Activity support for glanceable bill and goal pressure before payday.",
                "Bill and credit-card data are more flexible with notes, autopay source, grace period, issuer, last four digits, statement close date, and promo APR tracking.",
                "TipKit guidance now introduces autopay and paycheck recommendation features in context."
            ]
        ),
        WhatsNewRelease(
            id: "1.1.1-2026-03-04",
            version: "1.1.1",
            releaseDate: "March 4, 2026",
            highlights: [
                "Transaction import now accepts CSV files labeled as generic text, fixing grayed-out file selection.",
                "Unified action/deep-link system for bill flows, used consistently by app UI and integrations.",
                "New Siri + Shortcuts actions: open bill, show card utilization, mark bill paid.",
                "New quick actions: open next due bill and pay recommended amount on your most utilized card.",
                "Open Next Due Bill now returns a Siri/Shortcuts detail card with spoken summary and a tap-to-open button into the exact bill screen.",
                "Spotlight indexing for bills with tap-to-open routing into the exact bill screen.",
                "Actionable bill reminders with Open Bill, Mark Paid, and Snooze 1h actions.",
                "Interactive widget extension with quick actions for Upcoming Bills and Card Utilization."
            ]
        )
    ]

    static var latest: WhatsNewRelease? {
        releases.first
    }
}
