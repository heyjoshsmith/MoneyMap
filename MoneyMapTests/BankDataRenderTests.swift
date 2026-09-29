import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import MoneyMap

/// Sample-only native renders for human layout review; these do not assert live-bank correctness.
@MainActor
final class BankDataRenderTests: XCTestCase {
    func testCompactBankRowsRender() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MoneyMapBankRenderQA", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enrichment = PlaidConnectionEnrichment()
        enrichment.productStatuses = [.init(product: "liabilities", state: "unavailable", diagnosticMessage: "ADDITIONAL_CONSENT_REQUIRED")]
        let payload = try enrichment.encoded()
        let connections = ["OnePay", "Chase", "Capital One", "American Express", "E*TRADE from Morgan Stanley"].map { name in
            let connection = PlaidConnection(itemID: name, institutionName: name, status: "connected", lastSyncAt: .now)
            connection.enrichmentJSON = payload
            return PlaidConnectionValue(connection)
        }
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = NavigationStack {
                List {
                    Section("Connected Banks") {
                        ForEach(connections) { connection in
                            NavigationLink { Text("Bank details") } label: {
                                BankConnectionDataRow(connection: connection, accountCount: 2)
                            }
                        }
                    }
                    .moneyMapListSectionBackground()
                }
                .navigationTitle("Bank Sync")
                .navigationBarTitleDisplayMode(.inline)
                .moneyMapGroupedListBackground()
            }.environment(\.dynamicTypeSize, size)
            let host = UIHostingController(rootView: view)
            let originalWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
            let window = originalWindow?.windowScene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            try capture(host.view, name: "compact-banks-\(size)", directory: directory)
            window.isHidden = true
            window.rootViewController = nil
            originalWindow?.makeKey()
        }
    }

    func testBankDetailsRenderInLightDarkAndLargeType() async throws {
        let container = try ModelContainer(for: Bill.self, Transaction.self, PaymentMethod.self, PaydayConfig.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let styles: [(String, ColorScheme, DynamicTypeSize)] = [
            ("light", .light, .large), ("dark", .dark, .large),
            ("large-type", .light, .accessibility3)
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MoneyMapBankRenderQA", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for fixture in try fixtures() {
            for (style, scheme, textSize) in styles {
                let view = NavigationStack { BankAccountDataView(account: fixture.1) }
                    .modelContainer(container)
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, textSize)
                let host = UIHostingController(rootView: view)
                let originalKeyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows).first(where: \.isKeyWindow)
                let window: UIWindow
                if let scene = originalKeyWindow?.windowScene { window = UIWindow(windowScene: scene) }
                else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    originalKeyWindow?.makeKey()
                }
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(250))
                host.view.layoutIfNeeded()
                try capture(host.view, name: "\(fixture.0)-\(style)-top", directory: directory)

                if let scroll = scrollViews(in: host.view).max(by: { $0.contentSize.height < $1.contentSize.height }),
                   scroll.contentSize.height > scroll.bounds.height + 30 {
                    let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                    scroll.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    try capture(host.view, name: "\(fixture.0)-\(style)-bottom", directory: directory)
                }
            }
        }
        print("BANK_RENDER_QA_DIRECTORY=\(directory.path)")
    }

    private func capture(_ view: UIView, name: String, directory: URL) throws {
        XCTAssertEqual(view.bounds.size.width, 390, accuracy: 1)
        XCTAssertEqual(view.bounds.size.height, 844, accuracy: 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        var rendered = false
        let image = renderer.image { _ in rendered = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        XCTAssertTrue(rendered, "Native hierarchy failed to render: \(name)")
        let png = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(png.count, 10_000, "Render may be empty: \(name)")
        let url = directory.appendingPathComponent(name + ".png")
        try png.write(to: url)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("BANK_RENDER_QA_IMAGE=\(url.path)")
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func fixtures() throws -> [(String, PlaidAccountValue)] {
        let now = Date(timeIntervalSince1970: 1_789_862_400)
        var credit = PlaidAccountEnrichment()
        credit.creditLimit = 12_500
        credit.creditLiability = [
            "last_statement_balance": .number(2456.78), "minimum_payment_amount": .number(55),
            "next_payment_due_date": .string("2026-10-05"), "is_overdue": .bool(false),
            "last_payment_amount": .number(300), "last_payment_date": .string("2026-09-05"),
            "aprs": .array([.object(["apr_percentage": .number(19.99), "apr_type": .string("purchase_apr"), "balance_subject_to_apr": .number(2456.78)])])
        ]
        credit.productUpdatedAt = ["liabilities": now]
        var recurring = PlaidAccountEnrichment()
        recurring.recurringOutflows = [[
            "stream_id": .string("sample-bill"), "merchant_name": .string("Sample Internet Service"),
            "average_amount": .object(["amount": .number(79.99), "iso_currency_code": .string("USD")]),
            "frequency": .string("MONTHLY"), "predicted_next_date": .string("2026-10-01"), "is_active": .bool(true)
        ]]
        recurring.recurringInflows = [[
            "stream_id": .string("sample-pay"), "description": .string("Sample Employer Payroll"),
            "average_amount": .object(["amount": .number(-2345.67), "iso_currency_code": .string("USD")]),
            "frequency": .string("BIWEEKLY"), "predicted_next_date": .string("2026-09-25"), "is_active": .bool(true)
        ]]
        recurring.productUpdatedAt = ["recurring": now]
        var investments = PlaidAccountEnrichment()
        investments.securities = [["security_id": .string("sample-security"), "name": .string("Sample Total Market Index Fund"), "ticker_symbol": .string("SAMPLE"), "type": .string("etf")]]
        investments.holdings = [["security_id": .string("sample-security"), "quantity": .number(123.456), "institution_price": .number(101.25), "institution_value": .number(12499.92), "cost_basis": .number(10000)]]
        investments.investmentTransactions = [["security_id": .string("sample-security"), "date": .string("2026-09-18"), "type": .string("cash"), "subtype": .string("dividend"), "amount": .number(45.67)]]
        investments.productUpdatedAt = ["holdings": now, "investment_transactions": now]
        return try [("credit", "Sample Rewards Card", "credit", credit), ("recurring", "Sample Checking", "depository", recurring), ("investments", "Sample Brokerage", "investment", investments)].map { key, title, type, enrichment in
            let snapshot = PlaidAccountSnapshot(accountID: "sample-\(key)", itemID: "sample-bank", accountName: title, type: type, currentBalance: 2456.78, availableBalance: 10043.22, currencyCode: "USD", updatedAt: now)
            snapshot.enrichmentJSON = try enrichment.encoded()
            return (key, PlaidAccountValue(snapshot))
        }
    }
}
