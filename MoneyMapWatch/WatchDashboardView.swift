//
//  WatchDashboardView.swift
//  MoneyMapWatch
//
//  Created by Codex on 5/13/26.
//

import SwiftData
import SwiftUI

struct WatchDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bills: [Bill]
    @Query private var goals: [Goal]
    @Query private var paydayConfigs: [PaydayConfig]

    private var unpaidBills: [Bill] {
        let today = Calendar.current.startOfDay(for: .now)

        return bills
            .filter { bill in
                guard bill.datePaid == nil else { return false }
                guard let dueDate = bill.dueDate else { return true }
                return Calendar.current.startOfDay(for: dueDate) >= today
            }
            .sorted(by: Bill.byDate)
    }

    private var visibleGoals: [Goal] {
        goals
            .filter { $0.remainingAmount > 0 }
            .sorted { lhs, rhs in
                if lhs.daysUntilDeadline == rhs.daysUntilDeadline {
                    return (lhs.name ?? "") < (rhs.name ?? "")
                }
                return lhs.daysUntilDeadline < rhs.daysUntilDeadline
            }
    }

    private var nextPayday: Date? {
        paydayConfigs.compactMap(\.nextPayday).map(Self.nextFuturePayday).sorted().first
    }

    private var nextBillTotal: Double {
        unpaidBills.prefix(5).reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(nextBillTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.title3.weight(.semibold))
                        Text("Next \(min(unpaidBills.count, 5)) bills")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let nextPayday {
                        Label(nextPayday.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), systemImage: "banknote")
                    }
                }

                Section("Bills") {
                    if unpaidBills.isEmpty {
                        ContentUnavailableView("No upcoming bills", systemImage: "checkmark.circle")
                    } else {
                        ForEach(unpaidBills.prefix(8)) { bill in
                            NavigationLink {
                                WatchBillDetailView(bill: bill)
                            } label: {
                                WatchBillRow(bill: bill)
                            }
                        }
                    }
                }

                Section("Goals") {
                    if visibleGoals.isEmpty {
                        ContentUnavailableView("No active goals", systemImage: "target")
                    } else {
                        ForEach(visibleGoals.prefix(6)) { goal in
                            NavigationLink {
                                WatchGoalDetailView(goal: goal)
                            } label: {
                                WatchGoalRow(goal: goal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MoneyMap")
        }
    }

    private static func nextFuturePayday(from date: Date) -> Date {
        let calendar = Calendar.current
        var payday = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)

        while payday < today {
            payday = calendar.date(byAdding: .day, value: 14, to: payday) ?? payday
        }

        return payday
    }
}

private struct WatchBillRow: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(bill.name ?? "Bill", systemImage: bill.category?.icon ?? "calendar")
                .font(.headline)
            HStack {
                if let dueDate = bill.dueDate {
                    Text(dueDate, format: .dateTime.month(.abbreviated).day())
                }
                Spacer()
                Text(bill.amount ?? 0, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct WatchBillDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var bill: Bill

    var body: some View {
        List {
            Section {
                Text(bill.amount ?? 0, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.title3.weight(.semibold))

                if let dueDate = bill.dueDate {
                    Label(dueDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), systemImage: "calendar")
                }
            }

            Section {
                Button {
                    bill.makePayment(of: bill.amount ?? 0)
                    try? modelContext.save()
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .navigationTitle(bill.name ?? "Bill")
    }
}

private struct WatchGoalRow: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(goal.name ?? "Goal")
                .font(.headline)
            ProgressView(value: min(goal.progress(), 1))
            Text(goal.remainingAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: Goal

    var body: some View {
        List {
            Section {
                ProgressView(value: min(goal.progress(), 1)) {
                    Text(goal.name ?? "Goal")
                }
                Text(goal.remainingAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.title3.weight(.semibold))
            }

            Section {
                Button {
                    addContribution(goal.amountPerPaycheck ?? 25)
                } label: {
                    Label("Add Paycheck", systemImage: "plus.circle.fill")
                }

                Button {
                    addContribution(10)
                } label: {
                    Label("Add $10", systemImage: "plus")
                }
            }
        }
        .navigationTitle(goal.name ?? "Goal")
    }

    private func addContribution(_ amount: Double) {
        goal.amountSaved = min((goal.targetAmount ?? .greatestFiniteMagnitude), goal.amountSaved + amount)
        try? modelContext.save()
    }
}
