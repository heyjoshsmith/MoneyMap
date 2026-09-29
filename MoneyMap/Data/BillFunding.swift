import Foundation
import SwiftData

struct BillFundingSource: Identifiable, Equatable {
    let id: String
    let name: String
    let available: Double?
    let isCredit: Bool
}

struct BillFundingCharge {
    let billID: UUID
    let amount: Double?
    let source: BillFundingSource?
}

struct BillFundingGroup: Identifiable {
    let source: BillFundingSource
    var total: Double
    var billIDs: [UUID]
    var id: String { source.id }
    var shortage: Double? {
        guard let available = source.available, available.isFinite else { return nil }
        return max(0, total - max(0, available))
    }
}

struct BillFundingCoverage {
    let groups: [BillFundingGroup]
    let unresolvedBillIDs: Set<UUID>
    var shortfall: Double { roundedToCents(groups.compactMap(\.shortage).reduce(0, +)) }
    var isComplete: Bool { unresolvedBillIDs.isEmpty }

    // A pocket surplus or available credit must never inflate discretionary cash.
    func remaining(in sourceID: String, available: Double) -> Double? {
        guard isComplete, available.isFinite else { return nil }
        let reserved = groups.first { $0.id == sourceID }?.total ?? 0
        return max(0, roundedToCents(available - reserved))
    }
}

enum BillFundingCalculator {
    static func evaluate(_ charges: [BillFundingCharge]) -> BillFundingCoverage {
        var groups: [String: BillFundingGroup] = [:]
        var unresolved = Set<UUID>()
        var seen = Set<UUID>()
        for charge in charges where seen.insert(charge.billID).inserted {
            guard let amount = charge.amount, amount.isFinite, amount >= 0,
                  let source = charge.source else {
                unresolved.insert(charge.billID)
                continue
            }
            if source.available == nil || source.available?.isFinite != true {
                unresolved.insert(charge.billID)
            }
            var group = groups[source.id] ?? BillFundingGroup(source: source, total: 0, billIDs: [])
            group.total = roundedToCents(group.total + roundedToCents(amount))
            group.billIDs.append(charge.billID)
            groups[source.id] = group
        }
        return BillFundingCoverage(groups: groups.values.sorted { $0.source.name < $1.source.name }, unresolvedBillIDs: unresolved)
    }
}

struct BillFundingBankSnapshot {
    var accounts: [PlaidAccountValue] = []
    var connections: [PlaidConnectionValue] = []

    static func load() throws -> Self {
        let context = ModelContext(try PlaidSyncContainerFactory.make())
        return Self(accounts: try context.fetch(FetchDescriptor<PlaidAccountSnapshot>()).map(PlaidAccountValue.init),
                    connections: try context.fetch(FetchDescriptor<PlaidConnection>()).map(PlaidConnectionValue.init))
    }

    var activeAccounts: [PlaidAccountValue] {
        let activeIDs = Set(connections.filter { !$0.isDisconnected }.map(\.itemID))
        let newest = Dictionary(accounts.map { ($0.accountID, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        return newest.values.filter { account in
            (connections.isEmpty || activeIDs.contains(account.itemID)) && ["credit", "depository"].contains(account.type.lowercased())
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func sources(methods: [PaymentMethod], bills: [Bill]) -> [UUID: BillFundingSource] {
        let accountsByID = Dictionary(activeAccounts.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(methods.map { method in
            let card = bills.first { $0.id == method.linkedBillID }
            let accountID = method.plaidAccountID ?? card?.plaidAccountID
            let isCredit = method.type == .creditCard
            if let accountID, !accountID.isEmpty {
                let account = accountsByID[accountID]
                let isUSD = account?.currencyCode?.uppercased() == "USD"
                var balance: Double?
                if let account, isUSD {
                    // A credit balance is debt, not spending capacity.
                    balance = account.availableBalance ?? (account.type.lowercased() == "credit" ? nil : account.currentBalance)
                    if balance == nil, account.type.lowercased() == "credit",
                       let limit = PlaidAccountEnrichment.decode(account.enrichmentJSON)?.creditLimit,
                       let debt = account.currentBalance { balance = limit - debt }
                }
                return (method.id, BillFundingSource(id: "account:\(accountID)", name: account?.displayName ?? method.displayName,
                    available: balance.flatMap { $0.isFinite ? max(0, $0) : nil }, isCredit: account.map { $0.type.lowercased() == "credit" } ?? isCredit))
            }
            let details = isCredit ? card?.currentCreditCardDetails : nil
            let capacity = details.map { $0.creditLimit - $0.cardBalance }
            return (method.id, BillFundingSource(id: card.map { "card:\($0.id)" } ?? "method:\(method.id)", name: method.displayName,
                available: capacity.flatMap { $0.isFinite ? max(0, $0) : nil }, isCredit: isCredit))
        }, uniquingKeysWith: { first, _ in first })
    }

    func coverage(bills: [Bill], methods: [PaymentMethod], allBills: [Bill]) -> BillFundingCoverage {
        let sources = sources(methods: methods, bills: allBills)
        return BillFundingCalculator.evaluate(bills.map { bill in
            BillFundingCharge(billID: bill.id, amount: bill.amount, source: bill.paymentMethodID.flatMap { sources[$0] })
        })
    }
}

private func roundedToCents(_ amount: Double) -> Double { (amount * 100).rounded() / 100 }
