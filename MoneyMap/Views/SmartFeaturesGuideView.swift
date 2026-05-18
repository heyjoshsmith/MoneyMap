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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Smart Features")
                        .font(.title2.bold())
                    Text("MoneyMap can work from your Lock Screen, widgets, Siri, Shortcuts, Spotlight, and the share sheet. This page explains what each one does and when to use it.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Live Activity") {
                GuideRow(
                    icon: "rectangle.badge.clock",
                    title: "What it shows",
                    detail: "A quick plan for the period before your next payday: when that payday is, how many upcoming bills you still have, how many goals are behind, and how much the app currently suggests for cards and goals."
                )
                GuideRow(
                    icon: "lightbulb",
                    title: "How to read it",
                    detail: "\"Suggested for cards\" is the total the recommendation engine wants you to pay across credit cards right now. \"Suggested for goals\" is the total it wants you to put toward savings goals. \"Top focus\" is the single most urgent card or goal."
                )
                GuideRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "When it updates",
                    detail: "It refreshes when your goals, bills, payday amount, or recommendation inputs change while you use the app."
                )
            }

            Section("Siri & Shortcuts") {
                GuideRow(
                    icon: "waveform",
                    title: "What it can do",
                    detail: "You can ask Siri or run Shortcuts to open bills, open goals, add bills, show upcoming bills, open recommendations, compare paycheck scenarios, and mark a bill paid."
                )
                GuideRow(
                    icon: "sparkles",
                    title: "Best uses",
                    detail: "Use Shortcuts when you want quick actions without opening the full app, like checking what bill is due next or asking what to do with a paycheck amount."
                )
            }

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

            Section("Spotlight") {
                GuideRow(
                    icon: "magnifyingglass",
                    title: "What it does",
                    detail: "MoneyMap indexes bills, goals, and recommendations so you can find them from iPhone search and jump straight into the app."
                )
            }

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

            Section("Good Starting Point") {
                Text("If you’re not sure where to start, use the Recommendations tab in the app first. After that, add the payday widget, then try the Upcoming Bills Siri shortcut.")
                    .foregroundStyle(.secondary)
            }
        }
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
                .frame(width: 24)
                .foregroundStyle(.accent)
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
