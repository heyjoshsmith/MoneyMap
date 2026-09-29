import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MoneyMap

@MainActor
final class BillFundingRenderTests: XCTestCase {
    func testRentPocketCoverageAtPhoneWidth() async throws {
        let container = SharedModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let checking = PaymentMethod(name: "Checking", type: .checking, plaidAccountID: "checking")
        let pocket = PaymentMethod(name: "Rent Pocket", type: .checking, plaidAccountID: "rent")
        context.insert(checking); context.insert(pocket)
        let rent = Bill(name: "Rent", amount: 1700, dueDate: .now, category: .other, recurrenceInterval: 1, recurrenceUnit: .month, paymentMethodID: pocket.id)
        let internet = Bill(name: "Internet", amount: 75, dueDate: .now, category: .utilities, recurrenceInterval: 1, recurrenceUnit: .month, paymentMethodID: checking.id)
        context.insert(rent); context.insert(internet); try context.save()
        let snapshot = BillFundingBankSnapshot(accounts: [
            PlaidAccountValue(PlaidAccountSnapshot(accountID: "checking", itemID: "login", institutionName: "Example Bank", accountName: "Checking", type: "depository", availableBalance: 100, currencyCode: "USD")),
            PlaidAccountValue(PlaidAccountSnapshot(accountID: "rent", itemID: "login", institutionName: "Example Bank", accountName: "Rent Pocket", type: "depository", availableBalance: 1800, currencyCode: "USD"))
        ])
        let root = BillFundingView(planningDate: .now.addingTimeInterval(86400), previewSnapshot: snapshot).modelContainer(container)
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400))
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Bill sources - checking and rent pocket"
        attachment.lifetime = .keepAlways
        add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/MoneyMap-BillFunding-preview.png"))
        XCTAssertEqual(snapshot.coverage(bills: [rent, internet], methods: [checking, pocket], allBills: [rent, internet]).shortfall, 0)
    }
}
