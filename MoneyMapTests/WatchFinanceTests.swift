import XCTest
import SwiftData
@testable import MoneyMap

final class PayScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testLegacyDefaultsToBiweeklyAndIncludesToday() {
        let config = PaydayConfig(nextPayday: day(2026, 1, 2))
        XCTAssertEqual(config.schedule.kind, .biweekly)
        XCTAssertEqual(config.schedule.next(onOrAfter: day(2026, 1, 16), calendar: calendar), day(2026, 1, 16))
    }
    func testUnconfiguredPaydayDoesNotInventADate() {
        XCTAssertNil(PaydayConfig(nextPayday: nil).nextScheduledPayday(onOrAfter: day(2026, 1, 1), calendar: calendar))
    }
    func testWeeklyCrossesDaylightSavingWithoutChangingCalendarDay() {
        let schedule = PaySchedule(kind: .weekly, anchor: day(2026, 3, 1))
        XCTAssertEqual(schedule.dates(from: day(2026, 3, 1), through: day(2026, 3, 15), calendar: calendar), [day(2026, 3, 1), day(2026, 3, 8), day(2026, 3, 15)])
    }
    func testMonthlyClampsThenReturnsToOriginalDay() {
        let schedule = PaySchedule(kind: .monthly, anchor: day(2026, 1, 31), firstDay: 31)
        XCTAssertEqual(schedule.dates(from: day(2026, 1, 31), through: day(2026, 3, 31), calendar: calendar), [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31)])
    }
    func testTwiceMonthlyDeduplicatesFebruaryAndHandlesLeapYear() {
        let schedule = PaySchedule(kind: .twiceMonthly, anchor: day(2028, 1, 1), firstDay: 30, secondDay: 0)
        XCTAssertEqual(schedule.dates(from: day(2028, 2, 1), through: day(2028, 2, 29), calendar: calendar), [day(2028, 2, 29)])
    }
    func testPreviousCycleUsesScheduleAndEmptyRangeTerminates() {
        let schedule = PaySchedule(kind: .twiceMonthly, anchor: day(2026, 1, 1), firstDay: 1, secondDay: 15)
        XCTAssertEqual(schedule.previous(before: day(2026, 3, 1), calendar: calendar), day(2026, 2, 15))
        XCTAssertTrue(schedule.dates(from: day(2026, 3, 1), through: day(2026, 2, 1), calendar: calendar).isEmpty)
    }
}

@MainActor final class WatchFinanceTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Goal.self, GoalContribution.self, Bill.self, BillPaymentEntry.self, FinanceActionReceipt.self, AuditEvent.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    func testContributionRetryIsIdempotentAndUndoRestoresTotal() throws {
        let container = try container(); let context = container.mainContext
        let goal = Goal("Trip", targetAmount: 500, deadline: nil, weight: 1, paydaysUntil: 5)
        goal.totalSavedAmount = 50; context.insert(goal); try context.save()
        let id = UUID()
        try WatchFinanceService.contribute(25, to: goal, expected: 50, operationID: id, context: context)
        try WatchFinanceService.contribute(25, to: goal, expected: 50, operationID: id, context: context)
        XCTAssertEqual(goal.totalSavedAmount, 75)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinanceActionReceipt>()), 1)
        try WatchFinanceService.undo(id, context: context)
        XCTAssertEqual(goal.totalSavedAmount, 50)
    }
    func testStaleContributionAndUndoAreRejected() throws {
        let container = try container(); let context = container.mainContext
        let goal = Goal("Trip", targetAmount: 500, deadline: nil, weight: 1, paydaysUntil: 5)
        context.insert(goal); try context.save()
        let id = UUID()
        try WatchFinanceService.contribute(25, to: goal, expected: 0, operationID: id, context: context)
        XCTAssertThrowsError(try WatchFinanceService.contribute(10, to: goal, expected: 0, operationID: UUID(), context: context))
        goal.addContribution(10); try context.save()
        XCTAssertThrowsError(try WatchFinanceService.undo(id, context: context))
        XCTAssertEqual(goal.totalSavedAmount, 35)
    }
    func testContributionDeduplicatesMergedOperationIDs() {
        let goal = Goal("Trip", targetAmount: 500, deadline: nil, weight: 1, paydaysUntil: 5)
        let id = UUID()
        goal.contributions = [GoalContribution(id: id, amount: 20, goal: goal), GoalContribution(id: id, amount: 20, goal: goal), GoalContribution(amount: 30, goal: goal)]
        XCTAssertEqual(goal.totalSavedAmount, 50)
    }
    func testInvalidAmountsDoNotMutateData() throws {
        let container = try container(); let context = container.mainContext
        let goal = Goal("Trip", targetAmount: 500, deadline: nil, weight: 1, paydaysUntil: 5)
        context.insert(goal); try context.save()
        for amount in [Double.nan, .infinity, -1, 0, 0.001, 501] {
            XCTAssertThrowsError(try WatchFinanceService.contribute(amount, to: goal, expected: 0, operationID: UUID(), context: context))
        }
        XCTAssertEqual(goal.totalSavedAmount, 0)
    }
    func testPaymentRetryAndStaleUndo() throws {
        let container = try container(); let context = container.mainContext
        let bill = Bill(name: "Power", amount: 75, dueDate: .now, category: .other, recurrenceInterval: nil, recurrenceUnit: nil)
        context.insert(bill); try context.save()
        let state = BillActionState(bill); let id = UUID()
        try WatchFinanceService.billAction(bill, kind: .payment, amount: 75, expected: state, operationID: id, context: context)
        try WatchFinanceService.billAction(bill, kind: .payment, amount: 75, expected: state, operationID: id, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinanceActionReceipt>()), 1)
        bill.amount = 90
        XCTAssertThrowsError(try WatchFinanceService.undo(id, context: context))
    }
    func testSavedContributionSurvivesFreshContext() throws {
        let container = try container(); let context = ModelContext(container)
        let goal = Goal("Trip", targetAmount: 500, deadline: nil, weight: 1, paydaysUntil: 5)
        goal.totalSavedAmount = 40; context.insert(goal); try context.save()
        try WatchFinanceService.contribute(25, to: goal, expected: 40, operationID: UUID(), context: context)
        let other = ModelContext(container)
        XCTAssertEqual(try other.fetch(FetchDescriptor<Goal>()).first?.totalSavedAmount, 65)
    }
}

private enum LegacyWatchSchema {
    @Model final class Goal {
        var id: UUID = UUID()
        var name: String?
        var targetAmount: Double?
        var deadline: Date?
        var amountPerPaycheck: Double?
        var createdDate: Date = Date()
        var urls: [URL]?
        var imageData: Data?
        var imageFileName: String?
        var priorityWeight: Double?
        var amountSaved: Double = 0
        init() { name = "Existing Goal"; targetAmount = 500; amountSaved = 125 }
    }
    @Model final class Bill {
        var id: UUID = UUID()
        var name: String?
        var amount: Double?
        var dueDate: Date?
        var datePaid: Date?
        var category: BillCategory?
        var recurrenceInterval: Int?
        var recurrenceUnit: RecurrenceUnit?
        var creditCardDetails: CreditCardDetails?
        init() { name = "Existing Card"; category = .creditCard; creditCardDetails = CreditCardDetails(creditLimit: 2000, cardBalance: 500) }
    }
}

@MainActor final class WatchMigrationTests: XCTestCase {
    func testCloudKitFieldsKeepTheirOriginalPersistedNames() throws {
        let schema = Schema([Goal.self, GoalContribution.self, Bill.self, BillPaymentEntry.self, Transaction.self])
        let goal = try XCTUnwrap(schema.entities.first { $0.name == "Goal" })
        let bill = try XCTUnwrap(schema.entities.first { $0.name == "Bill" })
        XCTAssertTrue(goal.properties.contains { $0.name == "amountSaved" })
        XCTAssertFalse(goal.properties.contains { $0.name == "openingSavedAmount" || $0.name == "totalSavedAmount" })
        XCTAssertTrue(bill.properties.contains { $0.name == "creditCardDetails" })
        XCTAssertFalse(bill.properties.contains { $0.name == "openingCreditCardDetails" || $0.name == "currentCreditCardDetails" })
    }

    func testLegacyGoalAndCreditBalanceSurviveMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.sqlite")
        try createLegacyStore(url)
        let schema = Schema([Goal.self, GoalContribution.self, Bill.self, BillPaymentEntry.self, Transaction.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let goal = try XCTUnwrap(context.fetch(FetchDescriptor<Goal>()).first)
        let bill = try XCTUnwrap(context.fetch(FetchDescriptor<Bill>()).first)
        XCTAssertEqual(goal.totalSavedAmount, 125)
        XCTAssertEqual(bill.currentCreditCardDetails?.cardBalance, 500)
        goal.addContribution(25)
        bill.makePayment(of: 50)
        try context.save()
        XCTAssertEqual(goal.totalSavedAmount, 150)
        XCTAssertEqual(bill.currentCreditCardDetails?.cardBalance, 450)
    }
    private func createLegacyStore(_ url: URL) throws {
        let schema = Schema([LegacyWatchSchema.Goal.self, LegacyWatchSchema.Bill.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.insert(LegacyWatchSchema.Goal()); context.insert(LegacyWatchSchema.Bill())
        try context.save()
    }
    func testConcurrentCardEntriesCombineAndDeduplicate() {
        let bill = Bill(name: "Card", amount: 50, dueDate: .now, category: .creditCard, recurrenceInterval: 1, recurrenceUnit: .month,
                        creditCardDetails: CreditCardDetails(creditLimit: 2000, cardBalance: 500))
        let id = UUID()
        bill.paymentEntries = [BillPaymentEntry(id: id, amount: 50, bill: bill), BillPaymentEntry(id: id, amount: 50, bill: bill), BillPaymentEntry(amount: 25, bill: bill)]
        XCTAssertEqual(bill.currentCreditCardDetails?.cardBalance, 425)
        bill.currentCreditCardDetails?.cardBalance = 350
        XCTAssertEqual(bill.currentCreditCardDetails?.cardBalance, 350)
        bill.makePayment(of: 25)
        XCTAssertEqual(bill.currentCreditCardDetails?.cardBalance, 325)
    }
}
