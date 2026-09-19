import Foundation
import SwiftData

@Model public final class BillPaymentEntry {
    public var id: UUID = UUID()
    public var amount: Double = 0
    public var createdAt: Date = Date()
    public var bill: Bill?
    public init(id: UUID = UUID(), amount: Double, bill: Bill) {
        self.id = id; self.amount = amount; self.bill = bill
    }
}
