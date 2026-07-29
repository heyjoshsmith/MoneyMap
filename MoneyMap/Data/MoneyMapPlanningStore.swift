//
//  MoneyMapPlanningStore.swift
//  MoneyMap
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SwiftData

struct PlanningSnapshot {
    let goals: [Goal]
    let bills: [Bill]
    let nextPayday: Date?
    let amountPerPayday: Double
    let manualAmountPerPayday: Double
}

enum MoneyMapPlanningStore {
    static func makeContext() throws -> ModelContext {
        let container = try SharedModelContainerFactory.make()
        return ModelContext(container)
    }

    static func fetchGoals() throws -> [Goal] {
        let context = try makeContext()
        return try context.fetch(FetchDescriptor<Goal>())
    }

    static func fetchPrimaryPaydayConfig() throws -> PaydayConfig? {
        let context = try makeContext()
        return try context.fetch(FetchDescriptor<PaydayConfig>()).first
    }

    static func fetchPaycheckCashAccounts() throws -> [PaycheckCashAccount] {
        let container = try PlaidSyncContainerFactory.make()
        let context = ModelContext(container)
        let connections = try context.fetch(FetchDescriptor<PlaidConnection>())
        let activeItemIDs = Set(connections.compactMap { connection -> String? in
            let isDisconnected = connection.status?.localizedCaseInsensitiveContains("disconnect") == true
                || connection.errorMessage?.localizedCaseInsensitiveContains("disconnected") == true
            return isDisconnected ? nil : connection.itemID
        })
        let accounts = try context.fetch(
            FetchDescriptor<PlaidAccountSnapshot>(
                sortBy: [
                    SortDescriptor(\.institutionName),
                    SortDescriptor(\.accountName)
                ]
            )
        )
        return accounts
            .filter { account in
                activeItemIDs.isEmpty || activeItemIDs.contains(account.itemID)
            }
            .map(PaycheckCashAccount.init)
    }

    static func resolvedPaycheckAmount(manualAmount: Double) -> Double {
        let accounts = (try? fetchPaycheckCashAccounts()) ?? []
        return PaycheckCashResolver.availableCash(
            source: RecommendationPreferencesStore.paycheckCashSource,
            manualAmount: manualAmount,
            selectedAccountID: RecommendationPreferencesStore.paycheckCashAccountID,
            accounts: accounts
        )
    }

    static func snapshot() throws -> PlanningSnapshot {
        let goals = try fetchGoals()
        let bills = try MoneyMapBillStore.fetchBills()
        let paydayConfig = try fetchPrimaryPaydayConfig()
        let manualAmount = paydayConfig?.amountPerPayday ?? 0

        return PlanningSnapshot(
            goals: goals,
            bills: bills,
            nextPayday: paydayConfig?.nextPayday,
            amountPerPayday: resolvedPaycheckAmount(manualAmount: manualAmount),
            manualAmountPerPayday: manualAmount
        )
    }
}
