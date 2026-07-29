//
//  SmartFeaturesGuideView.swift
//  MoneyMap
//
//  Created by Codex on 5/6/26.
//

import SwiftUI

struct SmartFeaturesGuideView: View {
    var body: some View {
        List {
            Section {
                MoneyMapSummaryRow(
                    title: "Smart Features",
                    value: "System shortcuts",
                    detail: "Lock Screen, widgets, Siri, Spotlight, and sharing all lead back to your money map.",
                    systemImage: "sparkles",
                    tint: MoneyMapDesign.calmGreen
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Siri & Shortcuts") {
                GuideRow(
                    icon: "waveform",
                    title: "What it can do",
                    detail: "You can ask Siri about bill due dates, next payday, cash left after bills, savings progress, recent transactions, spending totals, recommendations, and more."
                )
                GuideRow(
                    icon: "sparkles",
                    title: "Best uses",
                    detail: "Use Siri for quick answers like what is due next, what you spent recently, or how to allocate available money. Use Shortcuts when you want repeatable one-tap actions."
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Ask") {
                GuideRow(
                    icon: "sparkles",
                    title: "Search with answers",
                    detail: "Search bills, goals, transactions, and allocation recommendations, then ask MoneyMap for grounded Apple Intelligence answers from the same data."
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Notifications") {
                GuideRow(
                    icon: "bell.badge",
                    title: "Bill reminders",
                    detail: "Upcoming bill reminders can open the bill, snooze for an hour, or mark a manual bill paid right from the notification."
                )
                GuideRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Autopay bills",
                    detail: "Turn on autopay for a bill when you still want the reminder but do not want to manually mark it paid each cycle."
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Widgets") {
                GuideRow(
                    icon: "square.grid.2x2",
                    title: "Available widgets",
                    detail: "You have widgets for next payday, next bill due, upcoming bills, and quick actions into bills and utilization."
                )
                GuideRow(
                    icon: "hand.tap",
                    title: "Best uses",
                    detail: "Use widgets when you want passive visibility. They’re best for checking countdowns and upcoming due dates without opening the app."
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Spotlight") {
                GuideRow(
                    icon: "magnifyingglass",
                    title: "What it does",
                    detail: "MoneyMap indexes bills, goals, and recommendations so you can find them from iPhone search and jump straight into the app."
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Share Sheet & CSV Import") {
                GuideRow(
                    icon: "square.and.arrow.up",
                    title: "Share to goals",
                    detail: "From Safari or other apps, share a page into MoneyMap to save it to a new or existing goal."
                )
                GuideRow(
                    icon: "tablecells",
                    title: "CSV import",
                    detail: "Import supported card transaction CSV files and attach them to a credit card so you can review activity inside the app."
                )
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)

            Section("Good Starting Point") {
                Text("If you’re not sure where to start, use the Plan tab in the app first. After that, add the payday widget, then try the Upcoming Bills Siri shortcut.")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("Smart Features")
    }
}

private struct GuideRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 26)
                .foregroundStyle(MoneyMapDesign.calmGreen)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        SmartFeaturesGuideView()
    }
}
