#if os(watchOS)
import Foundation
import SwiftData
import WidgetKit

struct WatchSnapshotItem: Codable, Identifiable {
    var id: String
    var kind: String
    var title: String
    var amount: Double?
    var date: Date?
    var progress: Double?
    var count: Int?
    var currency: String = "USD"
    var status: String? = nil
    var route: String
}
struct WatchSnapshot: Codable {
    var updatedAt: Date
    var items: [WatchSnapshotItem]
}

enum WatchSnapshotStore {
    static let suite = "group.com.heyjoshsmith.MoneyMap"
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite)?.appendingPathComponent("watch-summary.json")
    }
    static func read() -> WatchSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
    @MainActor static func publish(context: ModelContext, reloadWidgets: Bool = true) throws {
        let allBills = try context.fetch(FetchDescriptor<Bill>()).sorted(by: Bill.byDate)
        let bills = allBills.filter { $0.lifecycleState == .active && $0.datePaid == nil }
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let accounts = try context.fetch(FetchDescriptor<ManualSavingsAccount>())
        let config = try context.fetch(FetchDescriptor<PaydayConfig>()).first
        let next = config?.nextScheduledPayday(onOrAfter: .now)
        var items: [WatchSnapshotItem] = []
        if let next {
            let previous = config?.schedule.previous(before: next) ?? .now
            let total = next.timeIntervalSince(previous)
            items.append(.init(id: "payday", kind: "payday", title: "Payday", amount: config?.amountPerPayday, date: next,
                progress: total > 0 ? min(max(Date().timeIntervalSince(previous) / total, 0), 1) : 0, route: "plan"))
        }
        let upcoming = bills.filter { ($0.dueDate ?? .distantFuture) <= (next ?? Calendar.current.date(byAdding: .day, value: 7, to: .now)!) }
        items.append(.init(id: "today", kind: "today", title: "Bills before payday", amount: upcoming.reduce(0) { $0 + ($1.amount ?? 0) }, count: upcoming.count, route: "bills"))
        let unpaidIDs = Set(bills.map(\.id))
        for bill in bills + allBills.filter({ !unpaidIDs.contains($0.id) }) {
            items.append(.init(id: bill.id.uuidString, kind: "bill", title: bill.name ?? "Bill", amount: bill.amount, date: bill.dueDate, status: bill.datePaid != nil ? "Paid" : bill.lifecycleState.title, route: "bill/\(bill.id)"))
            if let details = bill.currentCreditCardDetails {
                items.append(.init(id: "card/\(bill.id)", kind: "card", title: bill.name ?? "Card", amount: abs(details.cardBalance),
                    progress: abs(details.cardBalance) / max(details.creditLimit, 1), route: "bill/\(bill.id)"))
            }
        }
        for goal in goals {
            items.append(.init(id: goal.id.uuidString, kind: "goal", title: goal.name ?? "Goal", amount: goal.remainingAmount, date: goal.deadline, progress: goal.progress(), route: "goal/\(goal.id)"))
        }
        for account in accounts {
            items.append(.init(id: account.id.uuidString, kind: "account", title: account.nameText, amount: account.balanceAmount, date: account.updatedAt, route: "wallet"))
        }
        if let container = try? PlaidSyncContainerFactory.make() {
            let bank = ModelContext(container)
            for account in try bank.fetch(FetchDescriptor<PlaidAccountSnapshot>()) {
                items.append(.init(id: account.accountID, kind: "account", title: account.displayName,
                    amount: account.availableBalance ?? account.currentBalance, date: account.updatedAt, currency: account.currencyCode ?? "USD", route: "wallet"))
            }
        }
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let week = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let cycle = next.flatMap { config?.schedule.previous(before: $0) } ?? month
        let start = min(month, min(week, cycle))
        let periods = [("today", calendar.startOfDay(for: .now)), ("week", week), ("month", month), ("cycle", cycle)]
        var totals: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var importedIDs = Set<String>()
        func add(amount: Double, date: Date?) {
            guard amount.isFinite, amount > 0, let date, date <= .now else { return }
            for (period, beginning) in periods where date >= beginning {
                totals[period, default: 0] += amount; counts[period, default: 0] += 1
            }
        }
        let fallback = Date.distantPast
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { ($0.transactionDate ?? fallback) >= start }, sortBy: [SortDescriptor(\.transactionDate)])
        descriptor.fetchLimit = 500
        while true {
            let batch = try context.fetch(descriptor)
            for transaction in batch {
                if let id = transaction.plaidTransactionID { importedIDs.insert(id) }
                add(amount: transaction.amountUSD ?? 0, date: transaction.transactionDate)
            }
            if batch.count < 500 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
        if let container = try? PlaidSyncContainerFactory.make() {
            let bank = ModelContext(container)
            var descriptor = FetchDescriptor<PlaidTransactionReviewItem>(predicate: #Predicate { ($0.date ?? fallback) >= start }, sortBy: [SortDescriptor(\.date)])
            descriptor.fetchLimit = 500
            while true {
                let batch = try bank.fetch(descriptor)
                for transaction in batch where !importedIDs.contains(transaction.plaidTransactionID) && (transaction.currencyCode ?? "USD") == "USD" {
                    add(amount: transaction.amount, date: transaction.date)
                }
                if batch.count < 500 { break }
                descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
            }
        }
        for (period, _) in periods {
            items.append(.init(id: "spending/\(period)", kind: "spending", title: "Spending · USD", amount: totals[period] ?? 0, count: counts[period] ?? 0, route: "transactions"))
        }
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let snapshot = WatchSnapshot(updatedAt: .now, items: items)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }
}
#endif
