import SwiftUI
import SwiftData

struct WatchWalletView: View {
    @Query(sort: \ManualSavingsAccount.nameText) private var manual: [ManualSavingsAccount]
    @Query private var bills: [Bill]
    @State private var accounts: [PlaidAccountSnapshot] = []
    @State private var error: String?
    @State private var adding = false
    var body: some View {
        List {
            NavigationLink { WatchTransactionsView() } label: { Label("Transactions", systemImage: "list.bullet.rectangle") }
            NavigationLink { WatchSpendingEditor() } label: { Label("Record Spending", systemImage: "plus.circle") }
            Section("Manual accounts") {
                ForEach(manual) { account in
                    NavigationLink { WatchAccountEditor(account: account) } label: {
                        VStack(alignment: .leading) { Text(account.nameText); Text(WatchDesign.money(account.balanceAmount)).font(.title3).privacySensitive() }
                    }
                }
                Button("Add Account", systemImage: "plus") { adding = true }
            }
            Section("Linked accounts") {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName).font(.headline)
                        if let balance = account.availableBalance ?? account.currentBalance {
                            Text(WatchDesign.money(balance, code: account.currencyCode ?? "USD")).font(.title3).privacySensitive()
                        } else { Text("Balance unavailable") }
                        Text(account.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if accounts.isEmpty { Text("No linked accounts").foregroundStyle(.secondary) }
            }
            Section("Credit cards") {
                ForEach(bills.filter { $0.category == .creditCard }) { bill in
                    NavigationLink { WatchBillDetailView(bill: bill) } label: {
                        VStack(alignment: .leading) {
                            Text(bill.name ?? "Card")
                            if let details = bill.currentCreditCardDetails {
                                let utilization = abs(details.cardBalance) / max(details.creditLimit, 1)
                                ProgressView(value: min(utilization, 1)).tint(utilization > 0.3 ? WatchDesign.gold : WatchDesign.green)
                                Text(utilization.formatted(.percent.precision(.fractionLength(0)))).font(.caption)
                            }
                        }
                    }
                }
            }
            NavigationLink("Bank Connections") { WatchBankConnectionsView() }
            if let error { Text(error).font(.caption) }
        }.navigationTitle("Wallet")
            .sheet(isPresented: $adding) { NavigationStack { WatchAccountEditor() } }
            .task {
                do {
                    let context = ModelContext(try PlaidSyncContainerFactory.make())
                    accounts = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>())
                    do { try await PlaidCloudSyncService.pull(context: context); accounts = try context.fetch(FetchDescriptor<PlaidAccountSnapshot>()) }
                    catch { self.error = "Showing saved bank data. \(error.localizedDescription)" }
                } catch { self.error = error.localizedDescription }
            }
    }
}

struct WatchAccountEditor: View {
    var account: ManualSavingsAccount? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var balance = 0.0
    @State private var error: String?
    @State private var confirm = false
    var body: some View {
        Form {
            TextField("Name", text: $name)
            WatchAmountField(title: "Balance (USD)", amount: $balance)
            Button("Save") { confirm = true }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error { Text(error).font(.caption) }
        }.navigationTitle(account == nil ? "New Account" : "Account")
            .onAppear { name = account?.nameText ?? ""; balance = account?.balanceAmount ?? 0 }
            .confirmationDialog("Save balance?", isPresented: $confirm) {
                Button("Save \(WatchDesign.money(balance))") {
                    do {
                        guard balance.isFinite, balance >= 0 else { throw FinanceActionError.invalidAmount }
                        let value = account ?? ManualSavingsAccount(name: name, balance: balance)
                        if account == nil { context.insert(value) }
                        value.nameText = name; value.balanceAmount = balance; value.updatedAt = .now
                        try context.save(); WatchAfterSave.update(context); dismiss()
                    } catch { context.rollback(); self.error = error.localizedDescription }
                }
            }
    }
}

struct WatchTransactionsView: View {
    @Environment(\.modelContext) private var context
    @State private var manual: [Transaction] = []
    @State private var imported: [PlaidTransactionReviewItem] = []
    @State private var error: String?
    @State private var limit = 50
    var body: some View {
        List {
            NavigationLink { WatchSpendingEditor() } label: { Label("Record Spending", systemImage: "plus") }
            Section("Recorded") {
                ForEach(manual) { entry in
                    NavigationLink { WatchSpendingEditor(transaction: entry) } label: {
                        VStack(alignment: .leading) {
                            Text(entry.merchant ?? entry.transactionDescription ?? "Spending")
                            Text(WatchDesign.money(entry.amountUSD ?? 0)).privacySensitive()
                            if let date = entry.transactionDate { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("Bank transactions") {
                ForEach(imported) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.merchantName ?? entry.name)
                        Text(WatchDesign.money(entry.amount, code: entry.currencyCode ?? "USD")).privacySensitive()
                        Text(entry.pending ? "Pending" : entry.date?.formatted(date: .abbreviated, time: .omitted) ?? "").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if manual.isEmpty && imported.isEmpty { ContentUnavailableView("No Transactions", systemImage: "list.bullet") }
            if manual.count == limit || imported.count == limit { Button("Load More") { limit += 50; load() } }
            if let error { Text(error).font(.caption) }
        }.navigationTitle("Transactions").onAppear(perform: load)
    }
    private func load() {
        do {
            var fetch = FetchDescriptor<Transaction>(predicate: #Predicate { $0.plaidTransactionID == nil }, sortBy: [SortDescriptor(\.transactionDate, order: .reverse)])
            fetch.fetchLimit = limit
            manual = try context.fetch(fetch)
            let bank = ModelContext(try PlaidSyncContainerFactory.make())
            var bankFetch = FetchDescriptor<PlaidTransactionReviewItem>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            bankFetch.fetchLimit = limit
            imported = try bank.fetch(bankFetch)
        } catch { self.error = error.localizedDescription }
    }
}

struct WatchSpendingEditor: View {
    var transaction: Transaction? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [ManualSavingsAccount]
    @State private var merchant = ""
    @State private var category = ""
    @State private var amount = 0.0
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var operationID = UUID()
    @State private var confirm = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Merchant", text: $merchant)
            WatchAmountField(title: "Amount (USD)", amount: $amount)
            TextField("Category", text: $category)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Picker("Account", selection: $accountID) {
                Text("None").tag(nil as UUID?)
                ForEach(accounts) { Text($0.nameText).tag(Optional($0.id)) }
            }
            Button("Save") { confirm = true }.disabled(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || transaction?.plaidTransactionID != nil)
            if let error { Text(error).font(.caption) }
        }.navigationTitle("Spending")
            .onAppear { if let entry = transaction { merchant = entry.merchant ?? ""; category = entry.category ?? ""; amount = entry.amountUSD ?? 0; date = entry.transactionDate ?? .now; accountID = entry.manualAccountID } }
            .confirmationDialog("Record \(WatchDesign.money(amount))?", isPresented: $confirm) {
                Button("Save") {
                    do {
                        try WatchFinanceService.validAmount(amount)
                        guard transaction?.plaidTransactionID == nil else { throw FinanceActionError.unavailable }
                        let id = operationID
                        if transaction == nil, try !context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.operationID == id })).isEmpty { dismiss(); return }
                        let entry = transaction ?? Transaction(transactionDate: date, clearingDate: nil as Date?, transactionDescription: merchant, merchant: merchant, category: category, type: "Debit", amountUSD: amount, purchasedBy: nil)
                        if transaction == nil { context.insert(entry); entry.operationID = operationID }
                        entry.merchant = merchant; entry.transactionDescription = merchant; entry.category = category; entry.amountUSD = amount; entry.transactionDate = date; entry.manualAccountID = accountID
                        try context.save(); WatchAfterSave.update(context); dismiss()
                    } catch { context.rollback(); self.error = error.localizedDescription }
                }
            } message: { Text("Account balances are updated separately.") }
    }
}
