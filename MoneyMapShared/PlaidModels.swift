//
//  PlaidModels.swift
//  MoneyMapShared
//
//  Created by Codex on 7/5/26.
//

import Foundation
import SwiftData

@Model
public class PlaidConnection: Identifiable {
    public var id: UUID = UUID()
    public var itemID: String = ""
    public var institutionID: String?
    public var institutionName: String?
    public var status: String?
    public var lastSyncAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var errorMessage: String?

    public init(
        itemID: String,
        institutionID: String? = nil,
        institutionName: String? = nil,
        status: String? = nil,
        lastSyncAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.itemID = itemID
        self.institutionID = institutionID
        self.institutionName = institutionName
        self.status = status
        self.lastSyncAt = lastSyncAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }
}

@Model
public class PlaidAccountSnapshot: Identifiable {
    public var id: UUID = UUID()
    public var accountID: String = ""
    public var itemID: String = ""
    public var institutionName: String?
    public var accountName: String = ""
    public var officialName: String?
    public var mask: String?
    public var type: String = ""
    public var subtype: String?
    public var currentBalance: Double?
    public var availableBalance: Double?
    public var currencyCode: String?
    public var updatedAt: Date = Date()

    public init(
        accountID: String,
        itemID: String,
        institutionName: String? = nil,
        accountName: String,
        officialName: String? = nil,
        mask: String? = nil,
        type: String,
        subtype: String? = nil,
        currentBalance: Double? = nil,
        availableBalance: Double? = nil,
        currencyCode: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = UUID()
        self.accountID = accountID
        self.itemID = itemID
        self.institutionName = institutionName
        self.accountName = accountName
        self.officialName = officialName
        self.mask = mask
        self.type = type
        self.subtype = subtype
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? (officialName ?? "Plaid Account") : trimmedName
    }

    public var lastFourLabel: String? {
        guard let mask, !mask.isEmpty else { return nil }
        return "Ending \(mask)"
    }
}

public enum BankSyncFreshnessLevel: String {
    case noSync
    case current
    case stale
    case veryStale

    public var isStale: Bool {
        switch self {
        case .stale, .veryStale:
            return true
        case .noSync, .current:
            return false
        }
    }
}

public struct BankSyncFreshness: Equatable {
    public let lastSyncAt: Date?
    public let now: Date

    public init(lastSyncAt: Date?, now: Date = .now) {
        self.lastSyncAt = lastSyncAt
        self.now = now
    }

    public var daysOld: Int? {
        guard let lastSyncAt else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: lastSyncAt)
        let end = calendar.startOfDay(for: now)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    public var level: BankSyncFreshnessLevel {
        guard let daysOld else { return .noSync }
        if daysOld >= 7 {
            return .veryStale
        }
        if daysOld >= 2 {
            return .stale
        }
        return .current
    }

    public var ageLabel: String? {
        guard let daysOld else { return nil }
        if daysOld == 0 {
            return "today"
        }
        if daysOld == 1 {
            return "1 day old"
        }
        return "\(daysOld) days old"
    }
}
