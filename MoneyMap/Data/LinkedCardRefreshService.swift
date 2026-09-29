import Foundation
import SwiftData
import WidgetKit

@MainActor
enum LinkedCardRefreshService {
    static func refresh(_ bill: Bill, context: ModelContext) async throws -> Date {
        let container = try PlaidSyncContainerFactory.make()
        let snapshotContext = ModelContext(container)
        try await PlaidCloudSyncService.pull(context: snapshotContext)
        try Task.checkCancellation()
        let accounts = try snapshotContext.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        guard let account = accounts.filter({ $0.accountID == bill.plaidAccountID }).max(by: { $0.updatedAt < $1.updatedAt }) else {
            throw RefreshError.accountMissing
        }
        try apply(account, to: bill)
        try context.save()
        AppRefreshEvents.notifyBillsDidChange()
        WidgetCenter.shared.reloadAllTimelines()
        return bill.plaidUpdatedAt ?? account.updatedAt
    }

    /// Apply balances independently of transaction imports, including snapshots with no new transactions.
    @discardableResult
    static func reconcile(snapshotContext: ModelContext, context: ModelContext) throws -> Int {
        let accounts = try snapshotContext.fetch(FetchDescriptor<PlaidAccountSnapshot>())
        let bills = try context.fetch(FetchDescriptor<Bill>())
        let count = try applyLatest(accounts, to: bills)
        if count > 0 {
            try context.save()
            AppRefreshEvents.notifyBillsDidChange()
            WidgetCenter.shared.reloadAllTimelines()
        }
        return count
    }

    @discardableResult
    static func applyLatest(_ accounts: [PlaidAccountSnapshot], to bills: [Bill]) throws -> Int {
        let newest = Dictionary(accounts.map { ($0.accountID, $0) }, uniquingKeysWith: {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        })
        var count = 0
        for bill in bills {
            guard bill.category == .creditCard, !bill.plaidUnavailable,
                  let accountID = bill.plaidAccountID, !accountID.isEmpty,
                  let account = newest[accountID], account.type == "credit",
                  account.currentBalance?.isFinite == true,
                  account.currencyCode == nil || account.currencyCode?.uppercased() == "USD",
                  bill.plaidReportedCardBalance == nil || (bill.plaidUpdatedAt.map({ account.updatedAt > $0 }) ?? true)
                    || (account.enrichmentJSON != nil && account.enrichmentJSON != bill.plaidEnrichmentJSON) else { continue }
            if try apply(account, to: bill) { count += 1 }
        }
        return count
    }

    @discardableResult
    static func apply(_ account: PlaidAccountSnapshot, to bill: Bill) throws -> Bool {
        guard bill.category == .creditCard, !bill.plaidUnavailable,
              bill.plaidAccountID == account.accountID, account.type == "credit" else {
            throw RefreshError.accountMissing
        }
        guard account.currencyCode == nil || account.currencyCode?.uppercased() == "USD" else { throw RefreshError.foreignCurrency }
        guard let balance = account.currentBalance, balance.isFinite else { throw RefreshError.balanceMissing }
        let enrichment = PlaidAccountEnrichment.decode(account.enrichmentJSON)
        let previousSource = PlaidAccountEnrichment.decode(bill.plaidEnrichmentJSON)?.balanceSource
        let adoptingBankTimestamp = (previousSource == nil || previousSource == "cached")
            && ["live", "bank_reported"].contains(enrichment?.balanceSource ?? "")
        // Older versions stamped cached balances with the fetch time. On first adoption of
        // authoritative bank timestamps, replace that misleading timestamp even if it is later.
        guard adoptingBankTimestamp || (bill.plaidUpdatedAt.map({ account.updatedAt >= $0 }) ?? true) else { return false }
        let existing = bill.currentCreditCardDetails
        let credit = enrichment?.creditLiability
        let purchaseAPR = credit?["aprs"]?.array?.compactMap(\.object)
            .first(where: { $0["apr_type"]?.string == "purchase_apr" })?["apr_percentage"]?.number
        let reportedLimit = enrichment?.creditLimit.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        // Bank-owned details update without changing the user's payment schedule or amount.
        bill.currentCreditCardDetails = CreditCardDetails(
            creditLimit: reportedLimit ?? max(existing?.creditLimit ?? 0, balance + max(account.availableBalance ?? 0, 0), 0),
            cardBalance: balance,
            annualPercentageRate: purchaseAPR ?? existing?.annualPercentageRate,
            minimumPayment: credit?["minimum_payment_amount"]?.number ?? existing?.minimumPayment,
            statementBalance: credit?["last_statement_balance"]?.number ?? existing?.statementBalance,
            issuerName: account.institutionName ?? existing?.issuerName,
            lastFourDigits: account.mask ?? existing?.lastFourDigits,
            statementClosingDate: existing?.statementClosingDate,
            promoAPRExpiration: existing?.promoAPRExpiration
        )
        bill.plaidReportedCardBalance = balance
        bill.plaidUpdatedAt = account.updatedAt
        if let json = account.enrichmentJSON { bill.plaidEnrichmentJSON = json }
        bill.checkStatus()
        return true
    }

    enum RefreshError: LocalizedError {
        case accountMissing, balanceMissing, foreignCurrency

        var errorDescription: String? {
            switch self {
            case .accountMissing: "This card is missing from the latest bank update. Check its connection in Bank Sync."
            case .balanceMissing: "The bank hasn’t provided a balance for this card. Your saved details haven’t changed."
            case .foreignCurrency: "This account uses another currency. Its bank details are available in Wallet, but can’t be added to your US-dollar card totals."
            }
        }
    }
}
