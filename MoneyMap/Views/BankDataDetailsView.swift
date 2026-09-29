import SwiftUI
import SwiftData

struct BankAccountDataView: View {
    let account: PlaidAccountValue
    @State private var selectedStream: BankRecurringDraft?

    private var data: [String: Any] { BankDataPresentation.object(account.enrichmentJSON) }
    var body: some View {
        List {
            Section {
                LabeledContent("Account", value: account.displayName)
                if data["balanceSource"] as? String == "cached" {
                    Label("Cached balance · bank update unavailable", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if account.updatedAt > Date(timeIntervalSince1970: 0) {
                    LabeledContent("Balance Updated", value: account.updatedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Balance Updated", value: "Not reported by bank")
                }
            }
            BankAccountEnrichmentSections(enrichmentJSON: account.enrichmentJSON, currency: account.currencyCode ?? "USD")
            recurringActions("recurringOutflows", income: false)
            recurringActions("recurringInflows", income: true)
        }
        .tint(MoneyMapDesign.calmGreen)
        .navigationTitle("Bank Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedStream) { draft in BankRecurringReviewView(draft: draft) }
    }
    @ViewBuilder private func recurringActions(_ key: String, income: Bool) -> some View {
        let objects = data[key] as? [[String: Any]] ?? []
        let drafts = objects.filter { $0["is_active"] as? Bool != false }.map { BankRecurringDraft(object: $0, income: income, currency: account.currencyCode ?? "USD") }
        if !drafts.isEmpty {
            Section {
                ForEach(drafts) { draft in
                    Button { selectedStream = draft } label: {
                        Label("Review \(draft.name)", systemImage: income ? "calendar.badge.clock" : "plus.circle")
                    }
                }
            } header: {
                Text(income ? "Use Recurring Income" : "Create Bills")
            } footer: {
                Text(income ? "Review the amount and schedule before updating your pay plan." : "Review suggested payments before creating bills. Existing bills are preserved.")
            }
        }
    }
}

struct BankTransactionDataSection: View {
    let enrichmentJSON: String?
    private var details: [String: Any] { BankDataPresentation.object(enrichmentJSON)["details"] as? [String: Any] ?? [:] }
    var body: some View {
        if !details.isEmpty {
            Section("Bank Details") {
                if let logo = details["logo_url"] as? String, let url = URL(string: logo), url.scheme == "https" {
                    HStack(spacing: 12) {
                        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "storefront").foregroundStyle(.secondary) }
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        Text(details["merchant_name"] as? String ?? "Merchant").font(.headline)
                    }
                }
                BankDataFields(details, currency: details["iso_currency_code"] as? String ?? "USD")
                if let website = details["website"] as? String,
                   let url = URL(string: website.contains("://") ? website : "https://" + website),
                   ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link("Merchant Website", destination: url)
                }
            }
        }
    }
}

struct BankRecurringDraft: Identifiable {
    let id: String
    let name: String
    let amount: Double
    let date: Date?
    let frequency: String
    let income: Bool
    let currency: String
    init(object: [String: Any], income: Bool, currency: String) {
        id = object["stream_id"] as? String ?? UUID().uuidString
        name = object["merchant_name"] as? String ?? object["description"] as? String ?? (income ? "Income" : "Recurring Payment")
        let average = object["average_amount"] as? [String: Any] ?? [:]
        let last = object["last_amount"] as? [String: Any] ?? [:]
        amount = abs(average["amount"] as? Double ?? last["amount"] as? Double ?? 0)
        self.currency = average["iso_currency_code"] as? String ?? last["iso_currency_code"] as? String ?? currency
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        date = (object["predicted_next_date"] as? String).flatMap { formatter.date(from: $0) }
        frequency = object["frequency"] as? String ?? "UNKNOWN"
        self.income = income
    }
}

private struct BankRecurringReviewView: View {
    let draft: BankRecurringDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var bills: [Bill]
    @Query private var payConfigs: [PaydayConfig]
    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var unit: RecurrenceUnit
    @State private var interval: Int
    @State private var payKind: PayScheduleKind
    @State private var secondMonthDay: Int
    @State private var error: String?

    init(draft: BankRecurringDraft) {
        self.draft = draft
        _name = State(initialValue: draft.name)
        _amount = State(initialValue: draft.amount)
        _date = State(initialValue: draft.date ?? .now)
        _unit = State(initialValue: ["WEEKLY", "BIWEEKLY"].contains(draft.frequency) ? .week : draft.frequency == "ANNUALLY" ? .year : .month)
        _interval = State(initialValue: draft.frequency == "BIWEEKLY" ? 2 : 1)
        _secondMonthDay = State(initialValue: 15)
        _payKind = State(initialValue: draft.frequency == "WEEKLY" ? .weekly : draft.frequency == "BIWEEKLY" ? .biweekly : draft.frequency == "SEMI_MONTHLY" ? .twiceMonthly : .monthly)
    }
    private var existingBill: Bill? {
        bills.first { $0.notes?.contains("Bank recurring stream: \(draft.id)") == true || $0.name?.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Review Bank Suggestion") {
                    TextField("Name", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: draft.currency)).keyboardType(.decimalPad)
                    DatePicker(draft.income ? "Next Payday" : "Next Due Date", selection: $date, displayedComponents: .date)
                    LabeledContent("Bank Frequency", value: BankDataPresentation.title(draft.frequency))
                    if draft.income {
                        Picker("Schedule", selection: $payKind) { ForEach(PayScheduleKind.allCases) { Text($0.title).tag($0) } }
                        if payKind == .twiceMonthly {
                            LabeledContent("First Day", value: "\(Calendar.current.component(.day, from: date))")
                            Stepper("Second Day: \(secondMonthDay)", value: $secondMonthDay, in: 1...28)
                        }
                    } else {
                        Stepper("Every \(interval)", value: $interval, in: 1...12)
                        Picker("Period", selection: $unit) {
                            Text("Days").tag(RecurrenceUnit.day)
                            Text("Weeks").tag(RecurrenceUnit.week)
                            Text("Months").tag(RecurrenceUnit.month)
                            Text("Years").tag(RecurrenceUnit.year)
                        }
                    }
                }
                if !draft.income && !["WEEKLY", "BIWEEKLY", "MONTHLY", "ANNUALLY"].contains(draft.frequency) {
                    Text("Choose a repeat interval for this bill. The bank’s frequency does not map to a standard interval automatically.").foregroundStyle(.secondary)
                }
                if draft.date == nil { Text("Your bank has not predicted a next date. Confirm the date above.").foregroundStyle(.secondary) }
                if draft.currency != "USD" { Text("This suggestion uses \(draft.currency). MoneyMap planning uses USD, so this suggestion cannot be added to the plan.").foregroundStyle(.orange) }
                if draft.income {
                    Section { Text("Saving updates your pay plan’s amount and schedule. Savings preferences are preserved. Confirm the dates match your expected deposits.") }
                } else if let existingBill {
                    Section { Text("A bill named \(existingBill.name ?? name) already exists. Review that bill before adding another payment.").foregroundStyle(.secondary) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(draft.income ? "Review Income" : "Review Bill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.income ? "Update Pay Plan" : "Create Bill", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !amount.isFinite || amount <= 0 || (!draft.income && existingBill != nil) || draft.currency != "USD" || (draft.income && payKind == .twiceMonthly && Calendar.current.component(.day, from: date) == secondMonthDay))
                }
            }
        }
    }
    private func save() {
        let saveContext = ModelContext(context.container)
        saveContext.autosaveEnabled = false
        do {
            if draft.income {
                let configs = try saveContext.fetch(FetchDescriptor<PaydayConfig>())
                let config = configs.first ?? PaydayConfig(nextPayday: date)
                if configs.isEmpty { saveContext.insert(config) }
                config.nextPayday = date
                config.amountPerPayday = amount
                config.scheduleKindRaw = payKind.rawValue
                let day = Calendar.current.component(.day, from: date)
                config.firstMonthDay = day
                if payKind == .twiceMonthly { config.secondMonthDay = secondMonthDay }
            } else {
                let existing = try saveContext.fetch(FetchDescriptor<Bill>())
                guard !existing.contains(where: { $0.notes?.contains("Bank recurring stream: \(draft.id)") == true || $0.name?.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) else {
                    error = "This bill has already been added."
                    return
                }
                saveContext.insert(Bill(name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount, dueDate: date, category: .other, recurrenceInterval: interval, recurrenceUnit: unit, notes: "Bank recurring stream: \(draft.id)"))
            }
            try saveContext.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
