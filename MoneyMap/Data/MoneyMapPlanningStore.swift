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

    static func snapshot() throws -> PlanningSnapshot {
        let goals = try fetchGoals()
        let bills = try MoneyMapBillStore.fetchBills()
        let paydayConfig = try fetchPrimaryPaydayConfig()

        return PlanningSnapshot(
            goals: goals,
            bills: bills,
            nextPayday: paydayConfig?.nextPayday,
            amountPerPayday: paydayConfig?.amountPerPayday ?? 0
        )
    }
}
