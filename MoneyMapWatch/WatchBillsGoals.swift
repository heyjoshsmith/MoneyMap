import SwiftUI
import SwiftData
import WatchKit

struct WatchBillsView: View {
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var filter = "Upcoming"
    @State private var adding = false
    private var visible: [Bill] {
        bills.filter { bill in
            switch filter {
            case "Paid": return bill.datePaid != nil
            case "All": return true
            default: return bill.lifecycleState == .active && bill.datePaid == nil
            }
        }
    }
    var body: some View {
        List {
            Picker("Show", selection: $filter) { ForEach(["Upcoming", "Paid", "All"], id: \.self) { Text($0) } }
            ForEach(visible) { bill in
                NavigationLink { WatchBillDetailView(bill: bill) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bill.name ?? "Bill").font(.headline)
                        Text(WatchDesign.money(bill.amount ?? 0)).font(.title3.monospacedDigit()).privacySensitive()
                        Text(bill.lifecycleState == .active ? (bill.dueDate?.daysUntil ?? "No due date") : bill.lifecycleState.title)
                            .font(.caption).foregroundStyle(WatchDesign.gold)
                    }
                }
            }
            if visible.isEmpty { ContentUnavailableView("No Bills", systemImage: "calendar") }
            Button("Add Bill", systemImage: "plus") { adding = true }
        }.navigationTitle("Bills").sheet(isPresented: $adding) { NavigationStack { WatchBillEditor() } }
    }
}

struct WatchBillDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var bill: Bill
    @State private var action: BillMutationKind?
    @State private var amount = 0.0
    @State private var date = Date()
    @State private var expected: BillActionState?
    @State private var operationID = UUID()
    @State private var receipt: UUID?
    @State private var error: String?
    @State private var editing = false
    var body: some View {
        List {
            WatchMetric(title: bill.name ?? "Bill", value: WatchDesign.money(bill.amount ?? 0),
                detail: bill.dueDate?.formatted(date: .abbreviated, time: .omitted), symbol: bill.category?.icon ?? "calendar", tint: WatchDesign.gold)
                .listRowInsets(EdgeInsets())
            if let balance = bill.currentCreditCardDetails?.cardBalance { Text("Balance \(WatchDesign.money(abs(balance)))").privacySensitive() }
            Text(bill.displayStatusName).font(.caption)
            if bill.lifecycleState == .active && bill.datePaid == nil {
                WatchAmountField(title: "Payment amount", amount: $amount)
                Button("Record Payment", systemImage: "checkmark.circle") { prepare(.payment) }
                DatePicker("New due date", selection: $date, displayedComponents: .date)
                Button("Delay") { prepare(.delay) }
                Button("Skip Occurrence") { prepare(.skip) }.disabled(bill.recurrenceInterval == nil)
            }
            Button("Edit Bill") { editing = true }
            if let receipt { Button("Undo Last Action") { perform { try WatchFinanceService.undo(receipt, context: context); self.receipt = nil } } }
            if let error { Text(error).font(.caption).foregroundStyle(WatchDesign.coral) }
        }.navigationTitle("Bill")
            .onAppear { amount = bill.amount ?? 0; date = bill.dueDate ?? .now }
            .confirmationDialog("Record this change?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } })) {
                Button("Confirm") {
                    guard let action, let expected else { return }
                    perform { receipt = try WatchFinanceService.billAction(bill, kind: action, amount: amount, date: date, expected: expected, operationID: operationID, context: context) }
                    self.action = nil
                }
            } message: { Text(action == .payment ? "Record \(WatchDesign.money(amount)) as paid. This does not move money." : "Update this bill’s next due date.") }
            .sheet(isPresented: $editing) { NavigationStack { WatchBillEditor(bill: bill) } }
    }
    private func prepare(_ kind: BillMutationKind) { expected = BillActionState(bill); operationID = UUID(); action = kind }
    private func perform(_ work: () throws -> Void) {
        do { try work(); error = nil; WKInterfaceDevice.current().play(.success); WatchAfterSave.update(context) }
        catch { self.error = error.localizedDescription }
    }
}

struct WatchGoalsView: View {
    @Query(sort: \Goal.createdDate) private var goals: [Goal]
    @State private var adding = false
    var body: some View {
        List {
            ForEach(goals) { goal in
                NavigationLink { WatchGoalDetailView(goal: goal) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goal.name ?? "Goal").font(.headline)
                        ProgressView(value: min(max(goal.progress(), 0), 1)).tint(WatchDesign.green)
                        Text(WatchDesign.money(goal.remainingAmount) + " to go").font(.caption).privacySensitive()
                    }
                }
            }
            if goals.isEmpty { ContentUnavailableView("Your Next Goal", systemImage: "target", description: Text("Start saving for something you love.")) }
            Button("Add Goal", systemImage: "plus") { adding = true }
        }.navigationTitle("Goals").sheet(isPresented: $adding) { NavigationStack { WatchGoalEditor() } }
    }
}

struct WatchGoalDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var goal: Goal
    @State private var amount = 0.0
    @State private var confirming = false
    @State private var editing = false
    @State private var expected = 0.0
    @State private var operationID = UUID()
    @State private var receipt: UUID?
    @State private var error: String?
    @State private var celebrate = false
    var body: some View {
        List {
            WatchMetric(title: goal.name ?? "Goal", value: goal.progress().formatted(.percent.precision(.fractionLength(0))),
                detail: "\(WatchDesign.money(goal.totalSavedAmount)) of \(WatchDesign.money(goal.targetAmount ?? 0))", symbol: "target", progress: goal.progress())
                .listRowInsets(EdgeInsets())
            if celebrate {
                if reduceMotion { Label("Goal Complete!", systemImage: "sparkles").foregroundStyle(WatchDesign.gold) }
                else { Label("Goal Complete!", systemImage: "sparkles").foregroundStyle(WatchDesign.gold).symbolEffect(.bounce, value: celebrate) }
            }
            if let deadline = goal.deadline { Text(deadline, format: .dateTime.month().day().year()).font(.caption) }
            if goal.remainingAmount > 0 {
                WatchAmountField(title: "Contribution", amount: $amount)
                Button("Add Contribution", systemImage: "plus.circle.fill") {
                    expected = goal.totalSavedAmount; operationID = UUID(); confirming = true
                }
            }
            Button("Edit Goal") { editing = true }
            if let receipt { Button("Undo Contribution") {
                do { try WatchFinanceService.undo(receipt, context: context); self.receipt = nil; celebrate = false; WatchAfterSave.update(context) }
                catch { self.error = error.localizedDescription }
            } }
            if let error { Text(error).font(.caption).foregroundStyle(WatchDesign.coral) }
        }.navigationTitle("Goal")
            .onAppear { amount = min(FinancialPlanningEngine.goalProgressInsights(goals: [goal], nextPayday: (try? context.fetch(FetchDescriptor<PaydayConfig>()).first)?.nextScheduledPayday(onOrAfter: .now)).first?.recommendedContribution ?? 10, goal.remainingAmount) }
            .confirmationDialog("Record \(WatchDesign.money(amount))?", isPresented: $confirming) {
                Button("Record Contribution") {
                    do {
                        receipt = try WatchFinanceService.contribute(amount, to: goal, expected: expected, operationID: operationID, context: context)
                        error = nil
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { celebrate = goal.remainingAmount == 0 }
                        WKInterfaceDevice.current().play(.success)
                        WatchAfterSave.update(context)
                    } catch { self.error = error.localizedDescription }
                }
            } message: { Text("This records your savings. It does not transfer money.") }
            .sheet(isPresented: $editing) { NavigationStack { WatchGoalEditor(goal: goal) } }
    }
}
