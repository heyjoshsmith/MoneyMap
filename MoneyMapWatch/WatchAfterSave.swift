import Foundation
import SwiftData

@MainActor enum WatchAfterSave {
    /// A widget-cache failure must never make an already-saved transaction look failed.
    static func update(_ context: ModelContext) {
        do { try WatchSnapshotStore.publish(context: context) }
        catch { print("Watch summary refresh failed: \(error.localizedDescription)") }
        Task {
            do {
                try await WatchReminders.refresh(bills: context.fetch(FetchDescriptor<Bill>()), configs: context.fetch(FetchDescriptor<PaydayConfig>()))
            } catch { print("Watch reminders refresh failed: \(error.localizedDescription)") }
        }
    }
}
