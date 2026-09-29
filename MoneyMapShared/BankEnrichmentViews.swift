import Foundation
import CoreFoundation
import SwiftUI

/// Presentation of bank-provided fields. Identifiers and unsupported null fields stay out of the UI.
public enum BankDataPresentation {
    public static func object(_ json: String?) -> [String: Any] {
        guard let data = json?.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    public static func title(_ key: String) -> String {
        let names = ["aprs": "Interest Rates", "apr_percentage": "APR", "apr_type": "Rate Type", "is_overdue": "Overdue", "is_active": "Active", "last_statement_balance": "Statement Balance", "last_statement_issue_date": "Statement Date", "next_payment_due_date": "Payment Due", "minimum_payment_amount": "Minimum Payment", "institution_value": "Market Value", "institution_price": "Price", "iso_currency_code": "Currency", "personal_finance_category": "Category", "pfc_v2": "Category", "updatedAt": "Last Checked", "state": "Status", "authorized_date": "Authorized", "payment_channel": "Payment Channel"]
        return names[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    public static func rows(_ object: [String: Any], currency: String = "USD", prefix: String = "") -> [(String, String)] {
        let priority = ["merchant_name", "name", "last_statement_balance", "minimum_payment_amount", "next_payment_due_date", "is_overdue", "last_payment_amount", "last_payment_date", "aprs", "institution_value", "quantity", "institution_price", "cost_basis", "description", "average_amount", "last_amount", "frequency", "predicted_next_date", "product", "state", "message", "updatedAt"]
        let orderedKeys = object.keys.sorted {
            let left = priority.firstIndex(of: $0) ?? priority.count
            let right = priority.firstIndex(of: $1) ?? priority.count
            return left == right ? $0 < $1 : left < right
        }
        return orderedKeys.flatMap { key -> [(String, String)] in
            guard !key.hasSuffix("_id"), !key.hasSuffix("_ids"), !["account_id", "logo_url", "website", "iso_currency_code", "unofficial_currency_code", "institution_security_id", "cusip", "isin", "sedol"].contains(key), let value = object[key], !(value is NSNull) else { return [] }
            let label = prefix.isEmpty ? title(key) : "\(prefix) · \(title(key))"
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return [(label, number.boolValue ? "Yes" : "No")] }
                if key == "updatedAt" { return [(label, Date(timeIntervalSinceReferenceDate: number.doubleValue).formatted(date: .abbreviated, time: .shortened))] }
                let isMoney = ["amount", "balance", "payment", "cost_basis", "institution_value", "institution_price", "principal", "interest_paid", "interest_charge", "disbursement"].contains { key.contains($0) } && !key.contains("percentage") && !key.contains("number")
                let formatted = isMoney ? number.doubleValue.formatted(.currency(code: currency)) : number.doubleValue.formatted(.number.precision(.fractionLength(0...6)))
                return [(label, key.contains("percentage") ? formatted + "%" : formatted)]
            }
            if let text = value as? String, !text.isEmpty {
                let dateFormatter = DateFormatter(); dateFormatter.locale = Locale(identifier: "en_US_POSIX"); dateFormatter.dateFormat = "yyyy-MM-dd"
                if text.count == 10, let date = dateFormatter.date(from: text) { return [(label, date.formatted(date: .abbreviated, time: .omitted))] }
                let display = text.contains("_") ? text.replacingOccurrences(of: "_", with: " ").capitalized : text
                return [(label, display)]
            }
            if let nested = value as? [String: Any] { return rows(nested, currency: nested["iso_currency_code"] as? String ?? currency, prefix: label) }
            if let entries = value as? [[String: Any]] {
                return entries.enumerated().flatMap { index, entry in rows(entry, currency: currency, prefix: "\(label) \(index + 1)") }
            }
            if let strings = value as? [String], !strings.isEmpty { return [(label, strings.map { title($0) }.joined(separator: ", "))] }
            return []
        }
    }
}

#if !os(watchOS)
public struct BankDataFields: View {
    private let fields: [(String, String)]
    public init(_ object: [String: Any], currency: String = "USD") { fields = BankDataPresentation.rows(object, currency: currency) }
    public var body: some View {
        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
            LabeledContent(field.0) {
                Text(field.1).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }
    }
}

public struct BankAccountEnrichmentSections: View {
    let data: [String: Any]
    let currency: String
    public init(enrichmentJSON: String?, currency: String = "USD") { data = BankDataPresentation.object(enrichmentJSON); self.currency = currency }
    public var body: some View {
        if let limit = data["creditLimit"] as? Double {
            Section("Credit") { LabeledContent("Credit Limit", value: limit.formatted(.currency(code: currency))) }
        }
        liability("creditLiability", title: "Card Statement")
        liability("mortgageLiability", title: "Mortgage")
        liability("studentLoanLiability", title: "Student Loan")
        records("recurringInflows", title: "Recurring Income")
        records("recurringOutflows", title: "Recurring Payments")
        records("holdings", title: "Holdings")
        records("investmentTransactions", title: "Investment Activity")
        Section {
            Text("Details reflect the latest bank snapshot. Some banks do not supply every field or product. Check Bank Sync for availability and errors.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func liability(_ key: String, title: String) -> some View {
        if let object = data[key] as? [String: Any], !object.isEmpty {
            Section(title) {
                BankDataFields(object, currency: currency)
                freshness("liabilities")
            }
        }
    }
    @ViewBuilder private func records(_ key: String, title: String) -> some View {
        if let objects = data[key] as? [[String: Any]], !objects.isEmpty {
            Section(title) {
                ForEach(Array(objects.enumerated()), id: \.offset) { _, object in
                    DisclosureGroup(recordTitle(object)) {
                        BankDataFields(object, currency: currency)
                        if let security = security(for: object) {
                            DisclosureGroup("Security") { BankDataFields(security, currency: currency) }
                        }
                    }
                }
                freshness(key == "holdings" ? "holdings" : key == "investmentTransactions" ? "investment_transactions" : "recurring")
            }
        }
    }
    @ViewBuilder private func freshness(_ product: String) -> some View {
        if let dates = data["productUpdatedAt"] as? [String: Double], let value = dates[product] {
            Text("Updated \(Date(timeIntervalSinceReferenceDate: value).formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func security(for object: [String: Any]) -> [String: Any]? {
        guard let id = object["security_id"] as? String else { return nil }
        return (data["securities"] as? [[String: Any]])?.first { $0["security_id"] as? String == id }
    }
    private func recordTitle(_ object: [String: Any]) -> String {
        let securities = data["securities"] as? [[String: Any]] ?? []
        if let id = object["security_id"] as? String, let security = securities.first(where: { $0["security_id"] as? String == id }) {
            let name = security["name"] as? String ?? security["ticker_symbol"] as? String ?? "Security"
            return [name, object["date"] as? String].compactMap { $0 }.joined(separator: " · ")
        }
        return object["merchant_name"] as? String ?? object["description"] as? String ?? object["name"] as? String ?? "Bank Details"
    }
}

public struct BankConnectionProductDetails: View {
    let data: [String: Any]
    public init(enrichmentJSON: String?) { data = BankDataPresentation.object(enrichmentJSON) }
    public var body: some View {
        if !data.isEmpty {
            DisclosureGroup("Data Availability") {
                if let item = data["item"] as? [String: Any] {
                    BankDataFields(item.filter { ["available_products", "billed_products", "consented_products", "products", "consent_expiration_time", "update_type"].contains($0.key) })
                }
                if let statuses = data["productStatuses"] as? [[String: Any]] {
                    ForEach(Array(statuses.enumerated()), id: \.offset) { _, status in
                        VStack(alignment: .leading, spacing: 4) {
                            BankDataFields(status.filter { $0.key != "diagnosticMessage" })
                            if let diagnostic = status["diagnosticMessage"] as? String {
                                DisclosureGroup("Technical Details") { Text(diagnostic).font(.caption).textSelection(.enabled) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

#endif
