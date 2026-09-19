import SwiftUI
import SwiftData

struct WatchBillEditor: View {
    var bill: Bill? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = 0.0
    @State private var date = Date()
    @State private var repeats = true
    @State private var recurrenceUnit = RecurrenceUnit.month
    @State private var interval = 1
    @State private var cardBalance = 0.0
    @State private var creditLimit = 0.0
    @State private var category = BillCategory.other
    @State private var original: BillActionState?
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Name", text: $name)
            WatchAmountField(title: "Amount (USD)", amount: $amount)
            DatePicker("Due", selection: $date, displayedComponents: .date)
            Picker("Category", selection: $category) { ForEach(BillCategory.allCases, id: \.self) { Text($0.name).tag($0) } }
            if category == .creditCard {
                WatchAmountField(title: "Card balance (USD)", amount: $cardBalance)
                WatchAmountField(title: "Credit limit (USD)", amount: $creditLimit)
            }
            Toggle("Repeats", isOn: $repeats)
            if repeats {
                Picker("Unit", selection: $recurrenceUnit) { ForEach(RecurrenceUnit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Stepper("Every \(interval)", value: $interval, in: 1...12)
            }
            Button("Save") {
                do {
                    try WatchFinanceService.validAmount(amount)
                    if category == .creditCard {
                        try WatchFinanceService.validAmount(creditLimit)
                        guard cardBalance.isFinite, cardBalance >= 0 else { throw FinanceActionError.invalidAmount }
                    }
                    if let bill, BillActionState(bill) != original { throw FinanceActionError.changed }
                    let value = bill ?? Bill(name: name, amount: amount, dueDate: date, category: category, recurrenceInterval: repeats ? interval : nil, recurrenceUnit: repeats ? recurrenceUnit : nil)
                    if bill == nil { context.insert(value) }
                    value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.amount = amount; value.dueDate = date
                    value.category = category; value.recurrenceInterval = repeats ? interval : nil; value.recurrenceUnit = repeats ? recurrenceUnit : nil
                    if category == .creditCard {
                        var details = value.currentCreditCardDetails ?? CreditCardDetails(creditLimit: creditLimit, cardBalance: cardBalance)
                        details.creditLimit = creditLimit; details.cardBalance = cardBalance; value.currentCreditCardDetails = details
                    }
                    try context.save(); WatchAfterSave.update(context); dismiss()
                } catch { context.rollback(); self.error = error.localizedDescription }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error { Text(error).font(.caption) }
        }.navigationTitle(bill == nil ? "New Bill" : "Edit Bill")
            .onAppear { if let bill { original = BillActionState(bill); name = bill.name ?? ""; amount = bill.amount ?? 0; date = bill.dueDate ?? .now; category = bill.category ?? .other; repeats = bill.recurrenceInterval != nil; interval = bill.recurrenceInterval ?? 1; recurrenceUnit = bill.recurrenceUnit ?? .month; cardBalance = abs(bill.currentCreditCardDetails?.cardBalance ?? 0); creditLimit = bill.currentCreditCardDetails?.creditLimit ?? 0 } }
    }
}

struct WatchGoalEditor: View {
    var goal: Goal? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target = 0.0
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Name", text: $name)
            WatchAmountField(title: "Target (USD)", amount: $target)
            DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
            Button("Save") {
                do {
                    try WatchFinanceService.validAmount(target)
                    let config = try context.fetch(FetchDescriptor<PaydayConfig>()).first
                    let count = config?.schedule.dates(from: .now, through: deadline).count ?? 1
                    let value = goal ?? Goal(name, targetAmount: target, deadline: deadline, weight: 1, paydaysUntil: max(count, 1))
                    if goal == nil { context.insert(value) }
                    value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.targetAmount = target; value.deadline = deadline
                    value.amountPerPaycheck = value.remainingAmount / Double(max(count, 1))
                    try context.save(); WatchAfterSave.update(context); dismiss()
                } catch { context.rollback(); self.error = error.localizedDescription }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error { Text(error).font(.caption) }
        }.navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .onAppear { if let goal { name = goal.name ?? ""; target = goal.targetAmount ?? 0; deadline = goal.deadline ?? .now } }
    }
}

struct WatchPaydayEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind = PayScheduleKind.biweekly
    @State private var anchor = Date()
    @State private var first = 1
    @State private var second = 15
    @State private var income = 0.0
    @State private var error: String?
    @AppStorage("watchOnboarded") private var onboarded = false
    var body: some View {
        Form {
            Picker("Schedule", selection: $kind) { ForEach(PayScheduleKind.allCases) { Text($0.title).tag($0) } }
            DatePicker("Payday", selection: $anchor, displayedComponents: .date)
            if kind == .monthly || kind == .twiceMonthly {
                monthPicker("Day", value: $first)
                if kind == .twiceMonthly { monthPicker("Second day", value: $second) }
            }
            WatchAmountField(title: "Paycheck (USD)", amount: $income)
            Button("Save") {
                do {
                    guard income.isFinite, income >= 0 else { throw FinanceActionError.invalidAmount }
                    let config = try context.fetch(FetchDescriptor<PaydayConfig>()).first ?? PaydayConfig(nextPayday: anchor)
                    if config.modelContext == nil { context.insert(config) }
                    config.nextPayday = anchor; config.amountPerPayday = income; config.scheduleKindRaw = kind.rawValue
                    config.firstMonthDay = first; config.secondMonthDay = second
                    try context.save(); onboarded = true; WatchAfterSave.update(context); dismiss()
                } catch { context.rollback(); self.error = error.localizedDescription }
            }.disabled(kind == .twiceMonthly && first == second)
            if let error { Text(error).font(.caption) }
        }.navigationTitle("Payday")
            .onAppear {
                if let config = try? context.fetch(FetchDescriptor<PaydayConfig>()).first {
                    kind = config.schedule.kind; anchor = config.nextPayday ?? .now; income = config.amountPerPayday ?? 0
                    first = config.firstMonthDay ?? Calendar.current.component(.day, from: anchor); second = config.secondMonthDay ?? 15
                }
            }
    }
    private func monthPicker(_ title: String, value: Binding<Int>) -> some View {
        Picker(title, selection: value) { Text("Last day").tag(0); ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
    }
}

struct WatchPlanView: View {
    @Query private var bills: [Bill]
    @Query private var goals: [Goal]
    @Query private var configs: [PaydayConfig]
    private var config: PaydayConfig? { configs.first }
    private var next: Date? { config?.nextScheduledPayday(onOrAfter: .now) }
    private var obligations: Double { bills.filter { $0.category != .creditCard && $0.lifecycleState == .active && $0.datePaid == nil && ($0.dueDate ?? .distantFuture) <= (next ?? .now) }.reduce(0) { $0 + ($1.amount ?? 0) } }
    var body: some View {
        let cash = max((config?.amountPerPayday ?? 0) - obligations, 0)
        let plan = FinancialPlanningEngine.recommendPaycheckPlan(availableCash: cash, goals: goals, bills: bills.filter { $0.lifecycleState == .active }, nextPayday: next)
        List {
            WatchMetric(title: "Paycheck", value: WatchDesign.money(config?.amountPerPayday ?? 0), detail: next?.daysUntil, symbol: "banknote").listRowInsets(EdgeInsets())
            LabeledContent("Bills", value: WatchDesign.money(obligations))
            if obligations > (config?.amountPerPayday ?? 0) {
                Label("\(WatchDesign.money(obligations - (config?.amountPerPayday ?? 0))) shortfall", systemImage: "exclamationmark.circle").foregroundStyle(WatchDesign.coral)
            }
            LabeledContent("Remaining allocation", value: WatchDesign.money(plan.unallocatedCash))
            ForEach(plan.creditCardPayments, id: \.billID) { item in
                NavigationLink { if let bill = bills.first(where: { $0.id == item.billID }) { WatchBillDetailView(bill: bill) } } label: {
                    VStack(alignment: .leading) { Text(item.billName); Text(WatchDesign.money(item.recommendedPayment)).font(.headline); Text(item.rationale).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            ForEach(plan.goalContributions, id: \.goalID) { item in
                NavigationLink { if let goal = goals.first(where: { $0.id == item.goalID }) { WatchGoalDetailView(goal: goal) } } label: {
                    VStack(alignment: .leading) { Text(item.goalName); Text(WatchDesign.money(item.recommendedContribution)).foregroundStyle(WatchDesign.green) }
                }
            }
            NavigationLink("Payday Settings") { WatchPaydayEditor() }
        }.navigationTitle("Plan")
    }
}
