//
//  ActivityFeedView.swift
//  MoneyMap
//
//  Created by Codex on 5/6/26.
//

import SwiftUI
import SwiftData

struct ActivityFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AuditEvent.timestamp, order: .reverse) private var allEvents: [AuditEvent]

    let title: String
    var entityID: UUID? = nil
    var entityTypes: Set<AuditEntityType> = []

    @State private var filter: ActivityFilter = .all

    var body: some View {
        List {
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Changes to bills, cards, goals, and recommendations will appear here.")
                )
            } else {
                ForEach(groupedEvents, id: \.dateKey) { group in
                    Section(group.label) {
                        ForEach(group.events, id: \.id) { event in
                            ActivityEventRow(event: event) {
                                try? AuditService.undo(event, context: modelContext)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(ActivityFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var filteredEvents: [AuditEvent] {
        allEvents.filter { event in
            let entityMatches = entityID == nil || event.entityID == entityID
            let typeMatches = entityTypes.isEmpty || entityTypes.contains(event.entityType)
            let filterMatches: Bool
            switch filter {
            case .all:
                filterMatches = true
            case .money:
                filterMatches = event.entityType == .creditCard || event.entityType == .bill
            case .goals:
                filterMatches = event.entityType == .goal
            case .undoable:
                filterMatches = event.canUndo
            }
            return entityMatches && typeMatches && filterMatches
        }
    }

    private var groupedEvents: [ActivitySection] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            Calendar.current.startOfDay(for: event.timestamp)
        }

        return grouped.keys.sorted(by: >).map { key in
            ActivitySection(
                dateKey: key,
                label: key.formatted(date: .abbreviated, time: .omitted),
                events: grouped[key]?.sorted(by: { $0.timestamp > $1.timestamp }) ?? []
            )
        }
    }
}

private struct ActivitySection {
    let dateKey: Date
    let label: String
    let events: [AuditEvent]
}

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case money
    case goals
    case undoable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .money: return "Bills & Cards"
        case .goals: return "Goals"
        case .undoable: return "Undoable"
        }
    }
}

private struct ActivityEventRow: View {
    let event: AuditEvent
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.titleText)
                        .font(.headline)
                    Text(event.summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let amount = event.amountValue {
                    Text(MoneyMapFormatters.currencyString(for: amount))
                        .font(.subheadline.weight(.semibold))
                }
            }

            HStack {
                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.source.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let undoneAt = event.undoneAt {
                    Text("Undone \(undoneAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if event.canUndo {
                    Button("Undo", action: onUndo)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ActivityFeedView(title: "Activity")
    }
    .modelContainer(PreviewDataProvider.createContainer().0)
}
