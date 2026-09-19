import Foundation
import SwiftData

/// Append-only contributions merge independently when devices save while offline.
@Model public final class GoalContribution {
    public var id: UUID = UUID()
    public var amount: Double = 0
    public var createdAt: Date = Date()
    public var goal: Goal?
    public init(id: UUID = UUID(), amount: Double, goal: Goal) {
        self.id = id; self.amount = amount; self.goal = goal
    }
}
