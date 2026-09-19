import SwiftData
import XCTest
@testable import MoneyMap

final class ShareExtensionStorageTests: XCTestCase {
    func testExtensionOpensPersistentSharedStoreWithoutCloudKit() throws {
        let container = try MoneyMapSharedContainerFactory.makeForAppExtension()
        let report = MoneyMapSharedContainerFactory.lastReport
        XCTAssertEqual(report.mode, .localOnly)
        XCTAssertEqual(report.storeURL?.lastPathComponent, "shared.sqlite")
        XCTAssertEqual(container.configurations.count, 1)
        let configuration = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)
        XCTAssertEqual(configuration.url, report.storeURL)
        XCTAssertEqual(report.fallbackReason, "The app extension uses shared local storage. MoneyMap handles iCloud sync.")
    }
}
