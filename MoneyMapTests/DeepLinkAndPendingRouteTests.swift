//
//  DeepLinkAndPendingRouteTests.swift
//  MoneyMapTests
//
//  Created by Codex on 4/27/26.
//

import XCTest
@testable import MoneyMap

final class DeepLinkAndPendingRouteTests: XCTestCase {
    func testOpenBillURLRoundTrips() throws {
        let billID = UUID()
        let route = MoneyMapRoute.openBill(billID)

        let url = try XCTUnwrap(MoneyMapDeepLink.url(for: route))
        let parsed = MoneyMapDeepLink.route(from: url)

        XCTAssertEqual(parsed, route)
    }

    func testActionRoutesParseFromDeepLinks() {
        XCTAssertEqual(
            MoneyMapDeepLink.route(from: URL(string: "moneymap://action?id=show_upcoming_bills")!),
            .showUpcomingBills
        )
        XCTAssertEqual(
            MoneyMapDeepLink.route(from: URL(string: "moneymap://action?id=show_card_utilization")!),
            .showCardUtilization
        )
        XCTAssertEqual(
            MoneyMapDeepLink.route(from: URL(string: "moneymap://action?id=show_recommendations")!),
            .showRecommendations
        )
    }

    func testCSVFileURLsMapToImportRoute() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")

        try "header\nvalue".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(MoneyMapDeepLink.route(from: url), .importCSV(url))
    }

    func testPendingRouteStorePersistsAndConsumesOpenBillRoute() {
        let suiteName = "MoneyMapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let billID = UUID()
        PendingRouteStore.set(.openBill(billID), defaults: defaults)

        XCTAssertEqual(PendingRouteStore.consume(defaults: defaults), .openBill(billID))
        XCTAssertNil(PendingRouteStore.consume(defaults: defaults))
    }

    func testPendingRouteStoreClearRemovesStoredRoute() {
        let suiteName = "MoneyMapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        PendingRouteStore.set(.showUpcomingBills, defaults: defaults)
        PendingRouteStore.clear(defaults: defaults)

        XCTAssertNil(PendingRouteStore.consume(defaults: defaults))
    }

    func testGoalRouteRoundTrips() throws {
        let goalID = UUID()
        let route = MoneyMapRoute.openGoal(goalID)

        let url = try XCTUnwrap(MoneyMapDeepLink.url(for: route))
        let parsed = MoneyMapDeepLink.route(from: url)

        XCTAssertEqual(parsed, route)
    }
}
