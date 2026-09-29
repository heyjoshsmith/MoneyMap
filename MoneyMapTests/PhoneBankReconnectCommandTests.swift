import XCTest
@testable import MoneyMap

@MainActor
final class PhoneBankReconnectCommandTests: XCTestCase {
    func testOnlySecurePlaidHTTPSURLCanBeOpened() {
        var command = PhoneBankReconnectCommand(itemID: "bank")
        for address in ["http://secure.plaid.com/hl/start", "https://plaid.com/hl/start", "https://secure.plaid.com.evil.example/hl/start", "https://user@secure.plaid.com/hl/start", "https://secure.plaid.com:8443/hl/start", "moneymap://bank-complete"] {
            command.hostedURL = URL(string: address)
            XCTAssertNil(command.sanitizedHostedURL, address)
        }
        command.hostedURL = URL(string: "https://secure.plaid.com/hl/start?token=fixture")
        XCTAssertEqual(command.sanitizedHostedURL, command.hostedURL)
    }

    func testCanceledOrSupersededRequestCannotBeRevived() {
        let now = Date(timeIntervalSince1970: 1000)
        let requested = PhoneBankReconnectCommand(itemID: "bank", now: now)
        var ready = requested
        ready.state = .ready
        ready.hostedURL = URL(string: "https://secure.plaid.com/hl/fixture")
        XCTAssertTrue(ready.canReplace(requested, now: now))
        var canceled = requested
        canceled.state = .canceled
        XCTAssertFalse(ready.canReplace(canceled, now: now))
        let replacement = PhoneBankReconnectCommand(itemID: "different-bank", now: now)
        XCTAssertFalse(ready.canReplace(replacement, now: now))
        var succeeded = ready
        succeeded.state = .succeeded
        XCTAssertFalse(succeeded.canReplace(requested, now: now))
        XCTAssertTrue(succeeded.canReplace(ready, now: now))
    }

    func testExpiredRequestCannotPublishLinkOrSuccessButCanFail() {
        let requested = PhoneBankReconnectCommand(itemID: "bank", now: Date(timeIntervalSince1970: 1000))
        let expired = requested.expiresAt.addingTimeInterval(1)
        var ready = requested
        ready.state = .ready
        ready.hostedURL = URL(string: "https://secure.plaid.com/hl/fixture")
        XCTAssertFalse(ready.canReplace(requested, now: expired))
        var failed = requested
        failed.state = .failed
        XCTAssertTrue(failed.canReplace(requested, now: expired))
        var extended = ready
        extended.expiresAt = requested.expiresAt.addingTimeInterval(3600)
        XCTAssertFalse(extended.canReplace(requested, now: requested.createdAt))
    }

    func testCommandRoundTripContainsOnlyUserFacingSessionFields() throws {
        var command = PhoneBankReconnectCommand(itemID: "bank")
        command.state = .ready
        command.hostedURL = URL(string: "https://secure.plaid.com/hl/fixture")
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(PhoneBankReconnectCommand.self, from: data), command)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["accessToken"])
        XCTAssertNil(object["linkToken"])
        XCTAssertNil(object["secret"])
    }
}
