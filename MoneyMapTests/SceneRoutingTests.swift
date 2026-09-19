import XCTest
@testable import MoneyMap

@MainActor
final class SceneRoutingTests: XCTestCase {
    func testNotificationOnlyNavigatesMostRecentlyActiveWindow() {
        let router = MoneyMapSceneRouter(consumePending: { nil }, savePending: { _ in
            XCTFail("A foreground window should receive the route")
        })
        let first = DeepLinkManager()
        let second = DeepLinkManager()
        first.requestedGoalID = UUID()
        let firstGoal = first.requestedGoalID
        router.activate(first)
        router.activate(second)

        let route = MoneyMapRoute.openBill(UUID())
        router.deliver(route)

        XCTAssertEqual(second.pendingRoute, route)
        XCTAssertNil(first.pendingRoute)
        XCTAssertEqual(first.requestedGoalID, firstGoal)

        router.deactivate(second)
        first.clearPendingRoute()
        router.deliver(.showRecommendations)
        XCTAssertEqual(first.pendingRoute, .showRecommendations)
        XCTAssertEqual(second.pendingRoute, route)
    }

    func testInactiveWindowsDoNotConsumePendingNavigation() {
        var pending: MoneyMapRoute?
        let router = MoneyMapSceneRouter(consumePending: {
            defer { pending = nil }
            return pending
        }, savePending: { pending = $0 })
        let first = DeepLinkManager()
        let second = DeepLinkManager()
        router.activate(first)
        router.deactivate(first)
        let route = MoneyMapRoute.openGoal(UUID())
        router.deliver(route)
        XCTAssertNil(first.pendingRoute)
        XCTAssertEqual(pending, route)

        router.activate(second)
        XCTAssertEqual(second.pendingRoute, route)
        XCTAssertNil(pending)
        router.activate(first)
        XCTAssertNil(first.pendingRoute)
    }

    func testClosedWindowsAreNotRetainedOrSentRoutes() {
        var saved: MoneyMapRoute?
        let router = MoneyMapSceneRouter(consumePending: { nil }, savePending: { saved = $0 })
        var window: DeepLinkManager? = DeepLinkManager()
        weak var weakWindow = window
        router.activate(window!)
        window = nil
        XCTAssertNil(weakWindow)

        router.deliver(.showUpcomingBills)
        XCTAssertEqual(saved, .showUpcomingBills)
    }

    func testColdLaunchEventQueuedAfterActivationIsDeliveredWhenServicesAttach() {
        var pending: MoneyMapRoute?
        let router = MoneyMapSceneRouter(consumePending: {
            defer { pending = nil }
            return pending
        }, savePending: { pending = $0 })
        let window = DeepLinkManager()
        router.activate(window)
        pending = .openBill(UUID())
        let expected = pending

        router.deliverPendingIfActive()
        XCTAssertEqual(window.pendingRoute, expected)
        XCTAssertNil(pending)
        window.clearPendingRoute()
        router.deliverPendingIfActive()
        XCTAssertNil(window.pendingRoute)
    }

    func testURLIsDeliveredOnlyToItsReceivingWindow() throws {
        let first = DeepLinkManager()
        let second = DeepLinkManager()
        let route = MoneyMapRoute.openBill(UUID())
        first.handle(url: try XCTUnwrap(MoneyMapDeepLink.url(for: route)))

        XCTAssertEqual(first.pendingRoute, route)
        XCTAssertNil(second.pendingRoute)
        // The root resolves child navigation once, after selecting the destination tab.
        XCTAssertNil(first.requestedBillID)
    }
}
