import SwiftUI
import SwiftData

struct PayScheduleEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var paydayManager: PaydayManager
    @State private var kind = PayScheduleKind.biweekly
    @State private var anchor = Date()
    @State private var first = 1
    @State private var second = 15
    @State private var error: String?
    var body: some View {
        Form {
            Picker("Frequency", selection: $kind) { ForEach(PayScheduleKind.allCases) { Text($0.title).tag($0) } }
            DatePicker("Payday", selection: $anchor, displayedComponents: .date)
            if kind == .monthly || kind == .twiceMonthly {
                dayPicker("Day", selection: $first)
                if kind == .twiceMonthly { dayPicker("Second Day", selection: $second) }
            }
            Text("Dates beyond the end of a month use its last day. Weekends and holidays do not change payday dates.").font(.caption).foregroundStyle(.secondary)
            Button("Save Schedule") {
                do {
                    let config = try context.fetch(FetchDescriptor<PaydayConfig>()).first ?? PaydayConfig(nextPayday: anchor)
                    if config.modelContext == nil { context.insert(config) }
                    config.nextPayday = anchor; config.scheduleKindRaw = kind.rawValue; config.firstMonthDay = first; config.secondMonthDay = second
                    try context.save(); paydayManager.reload(); dismiss()
                } catch { context.rollback(); self.error = error.localizedDescription }
            }.disabled(kind == .twiceMonthly && first == second)
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Pay Schedule")
            .onAppear {
                if let config = try? context.fetch(FetchDescriptor<PaydayConfig>()).first {
                    kind = config.schedule.kind; anchor = config.nextPayday ?? .now
                    first = config.firstMonthDay ?? Calendar.current.component(.day, from: anchor); second = config.secondMonthDay ?? 15
                }
            }
    }
    private func dayPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) { Text("Last Day").tag(0); ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
    }
}
