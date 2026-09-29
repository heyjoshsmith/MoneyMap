import Foundation

public extension Bill {
    /// A bank due date is presentation data; the user's planning date remains persisted separately.
    var displayDueDate: Date? {
        if let bankStatus = bankReportedPaymentStatus {
            if case .upcoming(let date) = bankStatus { return date }
            if let text = PlaidAccountEnrichment.decode(plaidEnrichmentJSON)?.creditLiability?["next_payment_due_date"]?.string {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.isLenient = false
                if let date = formatter.date(from: text) { return date }
            }
        }
        if bankReportedOverdue == false { return nil }
        return dueDate
    }

    var displayPaymentIsPaid: Bool {
        if bankReportedOverdue != nil { return false }
        return datePaid != nil || effectiveStatus == .paid
    }
}
