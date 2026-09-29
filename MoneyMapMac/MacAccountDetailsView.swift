import SwiftUI

struct MacAccountDetailsCard: View {
    let account: PlaidAccountSnapshot
    let connection: PlaidConnection
    let transactions: [PlaidTransactionReviewItem]
    let canUpgrade: Bool
    let upgrade: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var selectedCapability: MacAccountCapability?
    @State private var wantsUpgrade = false
    private var capabilities: [MacAccountCapability] {
        MacAccountCapability.make(type: account.type, balance: account.currentBalance, accountJSON: account.enrichmentJSON, connectionJSON: connection.enrichmentJSON, transactionCount: transactions.count)
    }
    private var data: [String: Any] { BankDataPresentation.object(account.enrichmentJSON) }
    private var tint: Color { account.type == "investment" ? .purple : account.type == "loan" ? .orange : .accentColor }
    private var accountTitle: String { (account.subtype ?? account.type).replacingOccurrences(of: "_", with: " ").capitalized }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: account.type == "investment" ? "chart.pie.fill" : account.type == "loan" ? "house.fill" : "creditcard.fill")
                    .font(.title2).foregroundStyle(tint).frame(width: 44, height: 44).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName).font(.headline)
                    Text(accountTitle + (account.mask.map { " · Ending \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(account.type == "investment" ? "Account value" : "Current balance").font(.caption).foregroundStyle(.secondary)
                Text(account.currentBalance.map { $0.formatted(.currency(code: account.currencyCode ?? "USD")) } ?? "Not shared")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                if data["balanceSource"] as? String == "cached" {
                    Label("Saved balance · update delayed", systemImage: "clock").font(.caption).foregroundStyle(.orange)
                }
            }
            if let limit = data["creditLimit"] as? Double {
                LabeledContent("Credit limit", value: limit.formatted(.currency(code: account.currencyCode ?? "USD"))).font(.callout)
            } else if let available = account.availableBalance {
                LabeledContent("Available", value: available.formatted(.currency(code: account.currencyCode ?? "USD"))).font(.callout)
            }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(scheme == .dark ? 0.19 : 0.10))
            VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Account capabilities").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(capabilities.filter { [.available, .empty].contains($0.availability) }.count) of \(capabilities.count) available").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                ForEach(capabilities) { capability in
                    Button { selectedCapability = capability } label: {
                        HStack(spacing: 10) {
                            Image(systemName: capability.kind.symbol).foregroundStyle(tint).frame(width: 20)
                            Text(capability.kind.title).font(.callout)
                            Spacer(minLength: 8)
                            Label(capability.availability.rawValue, systemImage: capability.availability.symbol)
                                .font(.caption).foregroundStyle(capability.availability.color)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }

            }.padding(22)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .macWorkspaceSurface(radius: 18)
            .sheet(item: $selectedCapability, onDismiss: { if wantsUpgrade { wantsUpgrade = false; upgrade() } }) { capability in
                MacAccountCapabilitySheet(account: account, capability: capability, transactions: transactions, upgrade: canUpgrade ? {
                    wantsUpgrade = true
                    selectedCapability = nil
                } : nil)
            }
    }
}

private extension MacAccountCapability.Availability {
    var color: Color {
        switch self { case .available: .green; case .upgrade: .purple; case .delayed: .orange; default: .secondary }
    }
    var symbol: String {
        switch self { case .available: "checkmark.circle.fill"; case .upgrade: "sparkles"; case .delayed: "clock"; case .empty: "minus.circle"; default: "info.circle" }
    }
}

private struct MacAccountCapabilitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: PlaidAccountSnapshot
    let capability: MacAccountCapability
    let transactions: [PlaidTransactionReviewItem]
    let upgrade: (() -> Void)?
    private var data: [String: Any] { BankDataPresentation.object(account.enrichmentJSON) }
    private var currency: String { account.currencyCode ?? "USD" }
    private var liability: [String: Any] {
        for key in ["creditLiability", "mortgageLiability", "studentLoanLiability"] { if let value = data[key] as? [String: Any], !value.isEmpty { return value } }
        return [:]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(capability.kind.title).font(.title2.weight(.semibold))
                    Text(account.displayName).foregroundStyle(.secondary)
                }
                Spacer()
                Label(capability.availability.rawValue, systemImage: capability.availability.symbol)
                    .font(.callout).foregroundStyle(capability.availability.color)
            }
            Text(capability.detail).foregroundStyle(.secondary)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .macWorkspaceSurface(tint: capability.availability.color, radius: 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                    if let date = capability.dataAt { Text("Data received \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    if let date = capability.checkedAt { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    if let diagnostic = capability.diagnostic {
                        DisclosureGroup("Technical details") { Text(diagnostic).font(.caption).textSelection(.enabled) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if capability.availability == .upgrade, let upgrade { Button("Upgrade Data Access", action: upgrade).buttonStyle(.borderedProminent) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540, height: 520).background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var content: some View {
        switch capability.kind {
        case .balance:
            field("Current balance", value: money(account.currentBalance))
            field(account.type == "credit" ? "Available credit" : "Available balance", value: money(account.availableBalance))
            if account.type == "credit" { field("Credit limit", value: money(data["creditLimit"] as? Double)) }
        case .payments:
            field("Payment due", value: formattedField("next_payment_due_date"))
            field(data["mortgageLiability"] != nil ? "Monthly payment" : "Minimum payment", value: formattedField(data["mortgageLiability"] != nil ? "next_monthly_payment" : "minimum_payment_amount"))
            if account.type == "credit" { field("Statement balance", value: formattedField("last_statement_balance")) }
            else { field("Interest rate", value: formattedField("interest_rate_percentage")) }
            field("Last payment", value: formattedField("last_payment_amount"))
            if let overdue = liability["is_overdue"] as? Bool { field("Payment status", value: overdue ? "Overdue" : "On time") }
            else { field("Payment status", value: nil) }
            if let rates = liability["aprs"] as? [[String: Any]], !rates.isEmpty {
                DisclosureGroup("Interest rates") { BankDataFields(["aprs": rates], currency: currency) }
            }
            if !liability.isEmpty { DisclosureGroup("All payment details") { BankDataFields(liability, currency: currency) } }
            Text("Not shared means the bank did not include this field. It is never treated as zero or a missed payment.").font(.caption).foregroundStyle(.secondary)
        case .transactions:
            ForEach(Array(transactions.prefix(30))) { item in
                HStack { VStack(alignment: .leading) { Text(item.merchantName ?? item.name); if let date = item.date { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Text(item.amount.formatted(.currency(code: item.currencyCode ?? currency))).monospacedDigit() }
                Divider()
            }
            if transactions.count > 30 { Text("Showing 30 recent transactions.").font(.caption).foregroundStyle(.secondary) }
        case .recurring:
            records("recurringInflows", title: "Income")
            records("recurringOutflows", title: "Payments")
        case .holdings: records("holdings", title: "Holdings")
        case .investmentActivity: records("investmentTransactions", title: "Activity")
        }
    }
    private func field(_ title: String, value: String?) -> some View {
        LabeledContent(title) { Text(value ?? "Not shared").foregroundStyle(value == nil ? .secondary : .primary).textSelection(.enabled) }
            .padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    private func money(_ value: Double?) -> String? { value.map { $0.formatted(.currency(code: currency)) } }
    private func formattedField(_ key: String) -> String? {
        if key == "interest_rate_percentage", let rate = (liability["interest_rate"] as? [String: Any])?["percentage"] as? Double {
            return rate.formatted(.number.precision(.fractionLength(0...3))) + "%"
        }
        guard let value = liability[key], !(value is NSNull) else { return nil }
        return BankDataPresentation.rows([key: value], currency: currency).first?.1
    }
    @ViewBuilder private func records(_ key: String, title: String) -> some View {
        let entries = data[key] as? [[String: Any]] ?? []
        if !entries.isEmpty {
            Text(title).font(.headline)
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                let security = (data["securities"] as? [[String: Any]])?.first { ($0["security_id"] as? String) == (entry["security_id"] as? String) }
                DisclosureGroup(entry["merchant_name"] as? String ?? entry["description"] as? String ?? security?["name"] as? String ?? entry["name"] as? String ?? title) {
                    BankDataFields(entry, currency: currency)
                    if let security { DisclosureGroup("Security details") { BankDataFields(security, currency: currency) } }
                }
            }
        }
    }
}
