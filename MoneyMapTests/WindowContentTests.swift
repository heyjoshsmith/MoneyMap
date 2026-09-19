import XCTest
@testable import MoneyMap

@MainActor
final class WindowContentTests: XCTestCase {
    func testWindowIdentitySurvivesEncodingForRestoration() throws {
        let billID = UUID()
        let goalID = UUID()
        let contents: [MoneyMapWindowContent] = [
            .wallet(nil), .wallet(.bill(billID)), .wallet(.account("test-account")),
            .wallet(.transactions), .goal(goalID), .plan
        ]
        for content in contents {
            let data = try JSONEncoder().encode(content)
            XCTAssertEqual(try JSONDecoder().decode(MoneyMapWindowContent.self, from: data), content)
        }
        XCTAssertEqual(Set(contents).count, contents.count)
        XCTAssertNotEqual(MoneyMapWindowContent.goal(goalID), .goal(UUID()))
    }

    func testOpeningContentOnlyPreparesTheReceivingWindow() {
        let first = DeepLinkManager()
        let second = DeepLinkManager()
        let goalID = UUID()
        MoneyMapWindowContent.goal(goalID).prepareNavigation(in: first)
        MoneyMapWindowContent.wallet(.transactions).prepareNavigation(in: second)

        XCTAssertEqual(first.requestedGoalID, goalID)
        XCTAssertNil(first.requestedWalletDestination)
        XCTAssertEqual(second.requestedWalletDestination, .transactions)
        XCTAssertNil(second.requestedGoalID)
        XCTAssertEqual(MoneyMapWindowContent.goal(goalID).tab, .goals)
        XCTAssertEqual(MoneyMapWindowContent.wallet(.accounts).tab, .wallet)
        XCTAssertEqual(MoneyMapWindowContent.plan.tab, .plan)
    }

    func testDeletedItemIdentifiersCanStillBeRestoredToAnUnavailableState() throws {
        // Restoring identifiers does not require fetching (or recreating) models.
        let destination = WalletDestination.bill(UUID())
        let data = try JSONEncoder().encode(destination)
        XCTAssertEqual(try JSONDecoder().decode(WalletDestination.self, from: data), destination)
        XCTAssertThrowsError(try JSONDecoder().decode(WalletDestination.self, from: Data("invalid".utf8)))
    }
}
