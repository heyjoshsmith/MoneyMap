import Foundation

struct BillNextStepPolicy {
    let openPaymentLink: Bool
    let setUpPaymentLink: Bool
    let recordCardPayment: Bool
    let markPaid: Bool

    var hasActions: Bool {
        openPaymentLink || setUpPaymentLink || recordCardPayment || markPaid
    }

    init(bill: Bill) {
        let active = bill.lifecycleState == .active
        let isCard = bill.category == .creditCard
        let paymentNeeded = isCard
            ? (bill.currentCreditCardDetails?.cardBalance ?? 0) > 0
            : bill.status != .paid
        let manualPayment = bill.paymentMode == .manual || bill.paymentMode == .payLink
        openPaymentLink = active && paymentNeeded && manualPayment && bill.paymentURL != nil
        setUpPaymentLink = active && paymentNeeded && bill.paymentMode == .payLink && bill.paymentURL == nil
        recordCardPayment = active && isCard && paymentNeeded
        markPaid = active && !isCard && paymentNeeded && manualPayment
    }
}
