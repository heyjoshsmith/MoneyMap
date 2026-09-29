import XCTest
import SwiftData
@testable import MoneyMap

final class BillFundingTests: XCTestCase {
    private func charge(_ amount: Double?, _ source: BillFundingSource?) -> BillFundingCharge {
        BillFundingCharge(billID: UUID(), amount: amount, source: source)
    }
    private func cash(_ id: String, _ balance: Double?) -> BillFundingSource {
        BillFundingSource(id: "account:\(id)", name: id, available: balance, isCredit: false)
    }
    func testRentPocketCoversRentWithoutUsingChecking() {
        let coverage = BillFundingCalculator.evaluate([charge(1700, cash("Rent", 1800)), charge(50, cash("Checking", 100))])
        XCTAssertTrue(coverage.isComplete)
        XCTAssertEqual(coverage.shortfall, 0)
        XCTAssertEqual(coverage.remaining(in: "account:Checking", available: 100), 50)
    }
    func testSharedSourceReservesAllBillsOnce() {
        let checking = cash("Checking", 100)
        let coverage = BillFundingCalculator.evaluate([charge(70, checking), charge(50, checking)])
        XCTAssertEqual(coverage.groups.count, 1)
        XCTAssertEqual(coverage.shortfall, 20)
        XCTAssertEqual(coverage.remaining(in: "account:Checking", available: 100), 0)
    }
    func testSurplusInOtherPocketCannotHideShortage() {
        let coverage = BillFundingCalculator.evaluate([charge(200, cash("Checking", 100)), charge(1000, cash("Rent", 5000))])
        XCTAssertEqual(coverage.shortfall, 100)
    }
    func testCreditCapacityDoesNotInflatePlanningCash() {
        let card = BillFundingSource(id: "card:1", name: "Card", available: 2000, isCredit: true)
        let coverage = BillFundingCalculator.evaluate([charge(500, card), charge(40, cash("Checking", 100))])
        XCTAssertEqual(coverage.shortfall, 0)
        XCTAssertEqual(coverage.remaining(in: "account:Checking", available: 100), 60)
    }
    func testMissingAssignmentBalanceAndInvalidAmountStayUnconfirmed() {
        for item in [charge(50, nil), charge(50, cash("Unknown", nil)), charge(nil, cash("Checking", 100)), charge(.nan, cash("Checking", 100))] {
            let coverage = BillFundingCalculator.evaluate([item])
            XCTAssertFalse(coverage.isComplete)
            XCTAssertNil(coverage.remaining(in: "account:Checking", available: 100))
        }
    }
    func testZeroBalanceIsKnownShortfall() {
        let coverage = BillFundingCalculator.evaluate([charge(20, cash("Checking", 0))])
        XCTAssertTrue(coverage.isComplete)
        XCTAssertEqual(coverage.shortfall, 20)
    }
    func testDuplicateBillCannotDoubleReserveMoney() {
        let item = charge(50, cash("Checking", 100))
        XCTAssertEqual(BillFundingCalculator.evaluate([item, item]).groups.first?.total, 50)
    }
    func testDifferentMethodsForSameBankAccountShareBalance() {
        let account = PlaidAccountSnapshot(accountID: "checking", itemID: "login", accountName: "Checking", type: "depository", currentBalance: 100, availableBalance: 100, currencyCode: "USD")
        let first = PaymentMethod(name: "Debit Card", type: .debitCard, plaidAccountID: "checking")
        let second = PaymentMethod(name: "ACH", type: .checking, plaidAccountID: "checking")
        let bank = BillFundingBankSnapshot(accounts: [PlaidAccountValue(account)])
        let sources = bank.sources(methods: [first, second], bills: [])
        let coverage = BillFundingCalculator.evaluate([charge(60, sources[first.id]), charge(60, sources[second.id])])
        XCTAssertEqual(coverage.shortfall, 20)
        XCTAssertEqual(coverage.groups.count, 1)
    }
    func testDisconnectedOrForeignAccountDoesNotClaimCoverage() {
        let method = PaymentMethod(name: "Checking", type: .checking, plaidAccountID: "account")
        let account = PlaidAccountSnapshot(accountID: "account", itemID: "login", accountName: "Checking", type: "depository", currentBalance: 500, currencyCode: "EUR")
        var bank = BillFundingBankSnapshot(accounts: [PlaidAccountValue(account)])
        XCTAssertNil(bank.sources(methods: [method], bills: [])[method.id]?.available)
        account.currencyCode = "USD"
        bank = BillFundingBankSnapshot(accounts: [PlaidAccountValue(account)], connections: [PlaidConnectionValue(PlaidConnection(itemID: "login", status: "disconnected"))])
        XCTAssertNil(bank.sources(methods: [method], bills: [])[method.id]?.available)
    }
    func testCreditDebtIsNotUsedAsAvailableCredit() {
        let account = PlaidAccountSnapshot(accountID: "card", itemID: "login", accountName: "Card", type: "credit", currentBalance: 4000, currencyCode: "USD")
        let method = PaymentMethod(name: "Card", type: .creditCard, plaidAccountID: "card")
        let bank = BillFundingBankSnapshot(accounts: [PlaidAccountValue(account)])
        XCTAssertNil(bank.sources(methods: [method], bills: [])[method.id]?.available)
    }
    func testManualPaymentModeRetainsAssignedMethodAndPersists() throws {
        let container = SharedModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let method = PaymentMethod(name: "Rent Pocket", type: .checking, plaidAccountID: "rent")
        let bill = Bill(name: "Rent", amount: 1700, dueDate: .now, category: .other, recurrenceInterval: 1, recurrenceUnit: .month)
        context.insert(method); context.insert(bill)
        bill.updatePaymentSettings(autopayEnabled: false, paymentMethodID: method.id, autopaySource: nil, gracePeriodDays: 0, paymentMode: .manual)
        try context.save()
        let reread = try ModelContext(container).fetch(FetchDescriptor<Bill>()).first
        XCTAssertEqual(reread?.paymentMethodID, method.id)
        XCTAssertEqual(reread?.paymentMode, .manual)
    }
}
