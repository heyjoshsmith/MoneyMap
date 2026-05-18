//
//  AuditEvent.swift
//  MoneyMapShared
//
//  Created by Codex on 5/6/26.
//

import Foundation
import SwiftData

public enum AuditEntityType: String, Codable, CaseIterable {
    case bill
    case creditCard
    case goal
    case payday
    case recommendations
    case settings
}

public enum AuditEventType: String, Codable, CaseIterable {
    case billCreated
    case billPaymentApplied
    case goalCreated
    case goalContributionApplied
    case goalTotalAdjusted
    case paydayUpdated
    case recommendationBatchApplied
    case undoPerformed
}

public enum AuditSource: String, Codable, CaseIterable {
    case app
    case recommendations
    case settings
    case siri
    case shortcut
    case widget
    case notification
    case shareExtension
}

public enum AuditUndoKind: String, Codable, CaseIterable {
    case deleteBill
    case deleteGoal
    case revertBillPayment
    case revertGoalAmountSaved
}

@Model
public final class AuditEvent {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var eventTypeRaw: String = AuditEventType.billCreated.rawValue
    public var entityTypeRaw: String = AuditEntityType.bill.rawValue
    public var sourceRaw: String = AuditSource.app.rawValue
    public var entityIDString: String?
    public var groupIDString: String?
    public var titleText: String = ""
    public var summaryText: String = ""
    public var amountValue: Double?
    public var undoKindRaw: String?
    public var oldDoubleValue: Double?
    public var oldDateValue: Date?
    public var oldAuxDateValue: Date?
    public var oldStatusRaw: String?
    public var oldStatusDateValue: Date?
    public var undoneAt: Date?

    public init(
        timestamp: Date = Date(),
        eventType: AuditEventType,
        entityType: AuditEntityType,
        source: AuditSource,
        entityID: UUID? = nil,
        groupID: UUID? = nil,
        title: String,
        summary: String,
        amount: Double? = nil,
        undoKind: AuditUndoKind? = nil,
        oldDoubleValue: Double? = nil,
        oldDateValue: Date? = nil,
        oldAuxDateValue: Date? = nil,
        oldStatusRaw: String? = nil,
        oldStatusDateValue: Date? = nil,
        undoneAt: Date? = nil
    ) {
        self.timestamp = timestamp
        self.eventTypeRaw = eventType.rawValue
        self.entityTypeRaw = entityType.rawValue
        self.sourceRaw = source.rawValue
        self.entityIDString = entityID?.uuidString
        self.groupIDString = groupID?.uuidString
        self.titleText = title
        self.summaryText = summary
        self.amountValue = amount
        self.undoKindRaw = undoKind?.rawValue
        self.oldDoubleValue = oldDoubleValue
        self.oldDateValue = oldDateValue
        self.oldAuxDateValue = oldAuxDateValue
        self.oldStatusRaw = oldStatusRaw
        self.oldStatusDateValue = oldStatusDateValue
        self.undoneAt = undoneAt
    }

    public var eventType: AuditEventType {
        get { AuditEventType(rawValue: eventTypeRaw) ?? .billCreated }
        set { eventTypeRaw = newValue.rawValue }
    }

    public var entityType: AuditEntityType {
        get { AuditEntityType(rawValue: entityTypeRaw) ?? .bill }
        set { entityTypeRaw = newValue.rawValue }
    }

    public var source: AuditSource {
        get { AuditSource(rawValue: sourceRaw) ?? .app }
        set { sourceRaw = newValue.rawValue }
    }

    public var undoKind: AuditUndoKind? {
        get { undoKindRaw.flatMap(AuditUndoKind.init(rawValue:)) }
        set { undoKindRaw = newValue?.rawValue }
    }

    public var entityID: UUID? {
        get { entityIDString.flatMap(UUID.init(uuidString:)) }
        set { entityIDString = newValue?.uuidString }
    }

    public var groupID: UUID? {
        get { groupIDString.flatMap(UUID.init(uuidString:)) }
        set { groupIDString = newValue?.uuidString }
    }

    public var canUndo: Bool {
        undoKind != nil && undoneAt == nil
    }
}
