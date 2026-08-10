//
//  PlaidMacRefreshRequestPolicyTests.swift
//  MoneyMapTests
//
//  Created by Codex on 7/29/26.
//

import XCTest
@testable import MoneyMapShared

final class PlaidMacRefreshRequestPolicyTests: XCTestCase {
    func testRequestsMacRefreshWhenLastSyncIsAtLeastFiveMinutesOld() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let policy = PlaidMacRefreshRequestPolicy()

        XCTAssertFalse(policy.shouldRequestMacRefresh(
            lastSyncAt: now.addingTimeInterval(-(5 * 60 - 1)),
            now: now
        ))
        XCTAssertTrue(policy.shouldRequestMacRefresh(
            lastSyncAt: now.addingTimeInterval(-5 * 60),
            now: now
        ))
        XCTAssertTrue(policy.shouldRequestMacRefresh(
            lastSyncAt: now.addingTimeInterval(-(5 * 60 + 1)),
            now: now
        ))
    }

    func testRequestsMacRefreshWhenNoMacSyncHasReachedThePhone() {
        let policy = PlaidMacRefreshRequestPolicy()

        XCTAssertTrue(policy.shouldRequestMacRefresh(
            lastSyncAt: nil,
            now: Date(timeIntervalSinceReferenceDate: 800_000_000)
        ))
    }
}
