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
        guard let account = accounts.first(where: { $0.accountID == bill.plaidAccountID }) else {
            throw RefreshError.accountMissing
        }
        try apply(account, to: bill)
        try context.save()
        AppRefreshEvents.notifyBillsDidChange()
        WidgetCenter.shared.reloadAllTimelines()
        return account.updatedAt
    }

    static func apply(_ account: PlaidAccountSnapshot, to bill: Bill) throws {
        guard bill.category == .creditCard, !bill.plaidUnavailable,
              bill.plaidAccountID == account.accountID, account.type == "credit" else {
            throw RefreshError.accountMissing
        }
        guard let balance = account.currentBalance else { throw RefreshError.balanceMissing }
        let existing = bill.currentCreditCardDetails
        // Update only bank-owned fields. Keep the card's schedule and manual settings.
        bill.currentCreditCardDetails = CreditCardDetails(
            creditLimit: max(existing?.creditLimit ?? 0, balance + max(account.availableBalance ?? 0, 0), 0),
            cardBalance: balance,
            annualPercentageRate: existing?.annualPercentageRate,
            minimumPayment: existing?.minimumPayment,
            statementBalance: existing?.statementBalance,
            issuerName: account.institutionName ?? existing?.issuerName,
            lastFourDigits: account.mask ?? existing?.lastFourDigits,
            statementClosingDate: existing?.statementClosingDate,
            promoAPRExpiration: existing?.promoAPRExpiration
        )
        bill.plaidUpdatedAt = account.updatedAt
    }

    enum RefreshError: LocalizedError {
        case accountMissing, balanceMissing

        var errorDescription: String? {
            switch self {
            case .accountMissing: "This card is missing from the latest bank update. Check its connection in Bank Sync."
            case .balanceMissing: "The bank hasn’t provided a balance for this card. Your saved details haven’t changed."
            }
        }
    }
}
