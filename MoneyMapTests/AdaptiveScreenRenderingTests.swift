import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import MoneyMap

/// Captures real screens with synthetic, in-memory data for visual review. These
/// attachments complement state tests; they are not a claim of Duo pose validation.
@MainActor
final class AdaptiveScreenRenderingTests: XCTestCase {
    func testPlanAndSelectedGoalAtCompactAndRegularWidths() async throws {
        let preferenceKeys = ["recommendation_card_strategy", "recommendation_paycheck_strategy", "recommendation_paycheck_cash_source", "recommendation_paycheck_cash_account_id"]
        let savedPreferences = preferenceKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in savedPreferences {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let container = SharedModelContainerFactory.makeInMemory()
        let payday = Date().addingTimeInterval(7 * 86_400)
        let goal = Goal("Travel", targetAmount: 2000, deadline: payday.addingTimeInterval(90 * 86_400), weight: 1, paydaysUntil: 7)
        goal.totalSavedAmount = 350
        let secondGoal = Goal("Emergency Fund", targetAmount: 3000, deadline: payday.addingTimeInterval(180 * 86_400), weight: 1, paydaysUntil: 13)
        let card = Bill(name: "Everyday Card", amount: 60, dueDate: payday, category: .creditCard,
                        recurrenceInterval: 1, recurrenceUnit: .month,
                        creditCardDetails: CreditCardDetails(creditLimit: 5000, cardBalance: 1200))
        container.mainContext.insert(goal)
        container.mainContext.insert(secondGoal)
        container.mainContext.insert(card)
        container.mainContext.insert(PaydayConfig(nextPayday: payday))
        try container.mainContext.save()
        let manager = PaydayManager(context: container.mainContext)

        let plan = NavigationStack {
            AllocationGuidedPlanView(
                initialManualAvailableCash: 1750,
                initialPaycheckCashSource: .manual,
                initialSelectedPaycheckAccountID: "",
                initialPayoffStrategy: .balanced,
                initialAllocationStrategy: .balanced,
                orderedPaycheckAccounts: [], paycheckAccountLoadError: nil,
                activeAllocatedCash: 0, matchingActivePlanCount: 0,
                goals: [goal], bills: [card], creditAccounts: [], nextPayday: payday,
                onClose: { _ in }, onSave: { _ in }
            )
        }

        await capture(plan, width: 390, name: "Plan compact", sizeClass: .compact)
        await capture(plan, width: 1024, name: "Plan expanded", sizeClass: .regular)
        await capture(plan, width: 1024, name: "Plan accessibility", sizeClass: .regular, typeSize: .accessibility3)

        let routes = DeepLinkManager()
        let goals = GoalsView()
            .modelContainer(container)
            .environmentObject(manager)
            .environmentObject(routes)
        routes.requestedGoalID = goal.id
        await capture(goals, width: 1024, name: "Goals expanded", sizeClass: .regular)
        routes.requestedGoalID = goal.id
        await capture(goals, width: 390, name: "Goals compact detail", sizeClass: .compact) {
            XCTAssertNil(routes.requestedGoalID)
            // The list column is hidden. A second route must still reach the detail.
            routes.requestedGoalID = secondGoal.id
            try? await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(routes.requestedGoalID)
        }

        let wallet = WalletView()
            .modelContainer(container)
            .environmentObject(manager)
            .environmentObject(routes)
            .environmentObject(NotificationManager())
        routes.requestedBillID = card.id
        await capture(wallet, width: 1024, name: "Wallet expanded", sizeClass: .regular)
        routes.requestedBillID = card.id
        await capture(wallet, width: 390, name: "Wallet compact detail", sizeClass: .compact) {
            XCTAssertNil(routes.requestedBillID)
            routes.requestedBillsDestination = .cardUtilization
            try? await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(routes.requestedBillsDestination)
        }
    }

    func testTransactionFilterInspectorAtCompactAndRegularWidths() async throws {
        let container = SharedModelContainerFactory.makeInMemory()
        let presentation = InspectorPresentationProbe()
        let content = TransactionInspectorRender(presentation: presentation)
            .modelContainer(container)
        await capture(content, width: 1024, name: "Transaction inspector expanded", sizeClass: .regular, includePresentations: true) {
            presentation.isPresented = true
        }
        presentation.isPresented = false
        await capture(content, width: 390, name: "Transaction inspector compact", sizeClass: .compact, includePresentations: true) {
            presentation.isPresented = true
        }
    }

    private func capture<Content: View>(
        _ content: Content, width: CGFloat, name: String,
        sizeClass: UserInterfaceSizeClass, typeSize: DynamicTypeSize = .large,
        includePresentations: Bool = false,
        afterMount: (() async -> Void)? = nil
    ) async {
        let controller = UIHostingController(rootView: content
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.dynamicTypeSize, typeSize))
        let parent = UIViewController()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("The app-hosted render requires a window scene")
            return
        }
        let window = UIWindow(windowScene: scene)
        if includePresentations {
            controller.traitOverrides.horizontalSizeClass = sizeClass == .compact ? .compact : .regular
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try? await Task.sleep(for: .milliseconds(250))
            await afterMount?()
            try? await Task.sleep(for: .milliseconds(750))
            window.layoutIfNeeded()
            if sizeClass == .compact {
                XCTAssertNotNil(controller.presentedViewController, "Compact filters should present a sheet")
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
            return
        }
        window.rootViewController = parent
        window.isHidden = false
        parent.addChild(controller)
        parent.view.addSubview(controller.view)
        controller.view.autoresizingMask = []
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 850)
        controller.didMove(toParent: parent)
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(450))
        await afterMount?()
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size.width, width)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        window.isHidden = true
    }
}

@MainActor
private final class InspectorPresentationProbe: ObservableObject {
    @Published var isPresented = false
}

private struct TransactionInspectorRender: View {
    @ObservedObject var presentation: InspectorPresentationProbe

    var body: some View {
        WalletTransactionsView(plaidAccounts: [], filterPresentation: $presentation.isPresented)
    }
}
