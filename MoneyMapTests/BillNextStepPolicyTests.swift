import XCTest
@testable import MoneyMap

final class BillNextStepPolicyTests: XCTestCase {
    func testManualCardUsesExistingPaymentLink() {
        let card = makeCard()
        card.paymentURLString = "https://card.apple.com"
        card.paymentMode = .manual
        let policy = BillNextStepPolicy(bill: card)
        XCTAssertTrue(policy.openPaymentLink)
        XCTAssertFalse(policy.setUpPaymentLink)
        XCTAssertTrue(policy.recordCardPayment)
    }

    func testOnlyPayLinkModeRequestsMissingLink() {
        let card = makeCard()
        for mode in [BillPaymentMode.manual, .autopay, .inPerson] {
            card.paymentMode = mode
            XCTAssertFalse(BillNextStepPolicy(bill: card).setUpPaymentLink)
        }
        card.paymentMode = .payLink
        XCTAssertTrue(BillNextStepPolicy(bill: card).setUpPaymentLink)
        card.paymentURLString = "shoebox://"
        XCTAssertTrue(BillNextStepPolicy(bill: card).openPaymentLink)
        XCTAssertFalse(BillNextStepPolicy(bill: card).setUpPaymentLink)
    }

    func testInactiveAndZeroBalanceCardsHaveNoPaymentActions() {
        let card = makeCard()
        card.paymentMode = .payLink
        for state in [BillLifecycleState.paused, .canceled] {
            card.lifecycleState = state
            XCTAssertFalse(BillNextStepPolicy(bill: card).hasActions)
        }
        card.lifecycleState = .active
        card.currentCreditCardDetails?.cardBalance = 0
        XCTAssertFalse(BillNextStepPolicy(bill: card).hasActions)
        card.currentCreditCardDetails?.cardBalance = -50
        XCTAssertFalse(BillNextStepPolicy(bill: card).hasActions)
    }

    func testPaidBillHasNoPaymentOrSetupActions() {
        let bill = makeCard()
        bill.category = .streaming
        bill.status = .paid
        bill.paymentMode = .payLink
        XCTAssertFalse(BillNextStepPolicy(bill: bill).hasActions)
    }

    private func makeCard() -> Bill {
        Bill(name: "Apple Card", amount: 100, dueDate: nil, category: .creditCard,
             recurrenceInterval: 1, recurrenceUnit: .month,
             creditCardDetails: CreditCardDetails(creditLimit: 1000, cardBalance: 100))
    }
}
