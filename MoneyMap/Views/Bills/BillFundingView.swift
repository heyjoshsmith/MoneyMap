import SwiftUI
import SwiftData

struct BillFundingView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var bills: [Bill]
    @Query private var methods: [PaymentMethod]
    @State private var bank = BillFundingBankSnapshot()
    @State private var loadError: String?
    let planningDate: Date?
    private let previewSnapshot: BillFundingBankSnapshot?

    init(planningDate: Date?, previewSnapshot: BillFundingBankSnapshot? = nil) {
        self.planningDate = planningDate
        self.previewSnapshot = previewSnapshot
        _bank = State(initialValue: previewSnapshot ?? BillFundingBankSnapshot())
    }

    private var upcoming: [Bill] {
        bills.filter { $0.category != .creditCard && $0.lifecycleState == .active && $0.status != .paid
            && ($0.dueDate.map { $0 <= (planningDate ?? .distantFuture) } ?? false) }.sorted(by: Bill.byDate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the account or card each bill actually charges. Accounts and pockets under the same bank login are checked separately.")
                    Text("These choices update MoneyMap. They don’t change payment instructions at your bank or biller.")
                        .foregroundStyle(.secondary)
                }
                if let loadError { Section { Text(loadError).foregroundStyle(.secondary) } }
                let coverage = bank.coverage(bills: upcoming, methods: methods, allBills: bills)
                if !coverage.groups.isEmpty {
                    Section("This Planning Window") {
                        ForEach(coverage.groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.source.name).font(.headline)
                                Text("\(MoneyMapFormatters.currencyString(for: group.total)) assigned · \(group.billIDs.count) bill\(group.billIDs.count == 1 ? "" : "s")")
                                if let available = group.source.available, let shortage = group.shortage {
                                    Text("\(MoneyMapFormatters.currencyString(for: available)) \(group.source.isCredit ? "available credit" : "available") · \(shortage > 0 ? MoneyMapFormatters.currencyString(for: shortage) + " short" : "Covered")")
                                        .foregroundStyle(shortage > 0 ? Color.orange : Color.secondary)
                                } else { Text("Balance unavailable — review this source.").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section("Bills") {
                    ForEach(bills.filter { $0.category != .creditCard && $0.lifecycleState == .active }.sorted(by: Bill.byDate)) { bill in
                        NavigationLink {
                            BillFundingAssignmentView(bill: bill)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bill.name ?? "Bill")
                                Text(bill.paymentMethod(in: methods)?.displayName ?? "Choose account or card")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .moneyMapGroupedListBackground()
            .navigationTitle("Bill Payment Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { reload() }
            .onReceive(NotificationCenter.default.publisher(for: AppRefreshEvents.billsDidChange)) { _ in reload() }
        }
    }

    private func reload() {
        if let previewSnapshot { bank = previewSnapshot; return }
        do { bank = try .load(); loadError = nil }
        catch { loadError = "Bank balances couldn’t be loaded. Your saved payment sources are still available." }
    }
}

struct BillFundingAssignmentView: View {
    @Environment(\.modelContext) private var context
    let bill: Bill
    @State private var saveError: String?
    @State private var suggestedAccountIDs = Set<String>()
    var body: some View {
        BillPaymentSourcePicker(selection: Binding(get: { bill.paymentMethodID }, set: { id in
            let previous = bill.paymentMethodID
            bill.paymentMethodID = id
            do { try context.save(); AppRefreshEvents.notifyBillsDidChange() }
            catch { bill.paymentMethodID = previous; saveError = "Couldn’t save the payment source. Try again." }
        }), excludedBillID: bill.id, suggestedAccountIDs: suggestedAccountIDs)
        .task {
            let billID = bill.id
            let linked = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkedBillID == billID }))) ?? []
            let cutoff = Calendar.current.date(byAdding: .month, value: -18, to: .now) ?? .distantPast
            suggestedAccountIDs = Set((linked + (bill.transactions ?? [])).compactMap { transaction in
                guard transaction.plaidBankRemovedAt == nil, transaction.plaidIsPending != true,
                      (transaction.amountUSD ?? 0) > 0,
                      (transaction.transactionDate ?? transaction.clearingDate ?? .distantPast) >= cutoff else { return nil }
                return transaction.plaidAccountID ?? transaction.creditCard?.plaidAccountID
            })
        }
        .alert("Payment Source", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }
}

struct BillPaymentSourcePicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PaymentMethod.name) private var methods: [PaymentMethod]
    @Query private var bills: [Bill]
    @Binding var selection: UUID?
    var excludedBillID: UUID?
    var suggestedAccountIDs = Set<String>()
    @State private var bank = BillFundingBankSnapshot()
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button { selection = nil } label: { choice("Not assigned", detail: "Coverage stays unconfirmed", selected: selection == nil) }
            }
            if !suggestedAccountIDs.isEmpty {
                Section {
                    ForEach(bank.activeAccounts.filter { suggestedAccountIDs.contains($0.accountID) }) { account in
                        accountButton(account)
                    }
                } header: { Text("From Linked Payment History") }
                footer: { Text("These accounts appear on this bill’s linked transactions. Confirm the source with your biller before choosing it.") }
            }
            Section("Bank Accounts & Pockets") {
                ForEach(bank.activeAccounts.filter { $0.type.lowercased() != "credit" }) { account in
                    accountButton(account)
                }
                if bank.activeAccounts.allSatisfy({ $0.type.lowercased() == "credit" }) {
                    Text("No synced bank accounts are available.").foregroundStyle(.secondary)
                }
            }
            Section("Credit Cards") {
                ForEach(bills.filter { $0.category == .creditCard && $0.id != excludedBillID && $0.lifecycleState == .active }) { card in
                    Button { choose(card) } label: {
                        choice(card.name ?? "Credit Card", detail: card.currentCreditCardDetails?.lastFourDigits.map { "Ending \($0)" } ?? "Credit card",
                               selected: methods.first { $0.id == selection }?.linkedBillID == card.id)
                    }
                }
                ForEach(bank.activeAccounts.filter { account in
                    account.type.lowercased() == "credit" && !bills.contains { $0.plaidAccountID == account.accountID }
                }) { account in accountButton(account) }
            }
            Section("Other Saved Methods") {
                ForEach(methods.filter { $0.linkedBillID == nil && $0.plaidAccountID == nil }) { method in
                    Button { selection = method.id } label: {
                        choice(method.displayName, detail: method.detailText + " · Balance not linked", selected: selection == method.id)
                    }
                }
            }
            Section {
                Text("Select the exact account or card shown by your biller. If a pocket isn’t listed, your bank may not share it as a separate account. MoneyMap won’t guess from the bank login.")
                    .foregroundStyle(.secondary)
                if let message { Text(message).foregroundStyle(.orange) }
            }
        }
        .moneyMapGroupedListBackground()
        .navigationTitle("Pay From")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { bank = try .load() }
            catch { message = "Couldn’t load bank accounts. Try reopening this screen." }
        }
    }

    private func choice(_ title: String, detail: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").accessibilityLabel("Selected") }
        }.contentShape(Rectangle())
    }

    private func accountButton(_ account: PlaidAccountValue) -> some View {
        Button { choose(account) } label: {
            choice(account.displayName,
                   detail: [account.institutionName, account.lastFourLabel, account.availableBalance.flatMap { balance in account.currencyCode.map { balance.formatted(.currency(code: $0)) + " available" } }].compactMap { $0 }.joined(separator: " · "),
                   selected: methods.first { $0.id == selection }?.plaidAccountID == account.accountID)
        }
    }

    private func choose(_ account: PlaidAccountValue) {
        if let method = methods.first(where: { $0.plaidAccountID == account.accountID }) { selection = method.id; return }
        let type: PaymentMethodType = account.type.lowercased() == "credit" ? .creditCard : (account.subtype == "savings" ? .savings : .checking)
        persist(PaymentMethod(name: account.displayName, type: type, institutionName: account.institutionName,
                              lastFourDigits: account.mask, plaidAccountID: account.accountID, plaidItemID: account.itemID))
    }

    private func choose(_ card: Bill) {
        if let method = methods.first(where: { $0.linkedBillID == card.id }) { selection = method.id; return }
        let method = PaymentMethod(name: card.name ?? "Credit Card", type: .creditCard)
        method.updateCreditCardMirror(from: card)
        persist(method)
    }

    private func persist(_ method: PaymentMethod) {
        context.insert(method)
        do { try context.save(); selection = method.id }
        catch { context.delete(method); message = "Couldn’t save this payment method. Try again." }
    }
}
