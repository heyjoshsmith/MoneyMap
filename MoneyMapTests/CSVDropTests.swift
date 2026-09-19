import SwiftData
import XCTest
@testable import MoneyMap

@MainActor
final class CSVDropTests: XCTestCase {
    func testReviewSurvivesProviderFileRemovalWithoutImportingAndCleansUpAfterDismissal() throws {
        let source = try fixture(named: "Statement.CSV")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        var file: MoneyMapCSVFile? = try MoneyMapCSVFile.stage(source)
        let stagedURL = try XCTUnwrap(file?.url)
        let review = MoneyMapCSVReview()
        XCTAssertTrue(review.accept([try XCTUnwrap(file)]))
        file = nil
        try FileManager.default.removeItem(at: source)

        let container = SharedModelContainerFactory.makeInMemory()
        let bill = Bill(name: "Test Card", amount: 50, dueDate: .now, category: .creditCard,
                        recurrenceInterval: 1, recurrenceUnit: .month,
                        creditCardDetails: CreditCardDetails(creditLimit: 1000, cardBalance: 50))
        container.mainContext.insert(bill)
        let preview = try previewTransactionCSVFiles(from: review.urls, for: bill)
        XCTAssertEqual(preview.importableRows, 1)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Transaction>()).isEmpty)
        XCTAssertEqual(stagedURL.lastPathComponent, "Statement.CSV")

        review.isPresented = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path), "Keep the file through the dismissal animation")
        review.didDismiss()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertTrue(review.urls.isEmpty)
        XCTAssertTrue(review.canAccept)
    }

    func testSecondDropCannotReplaceAnActiveOrDismissingReviewAndWindowsAreIndependent() throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let firstFile = try MoneyMapCSVFile.stage(source)
        let secondFile = try MoneyMapCSVFile.stage(source)
        let firstWindow = MoneyMapCSVReview()
        let secondWindow = MoneyMapCSVReview()

        XCTAssertFalse(firstWindow.accept([]))
        XCTAssertTrue(firstWindow.accept([firstFile]))
        XCTAssertTrue(secondWindow.canAccept)
        XCTAssertFalse(firstWindow.accept([secondFile]))
        XCTAssertFalse(firstWindow.accept(url: source))
        XCTAssertEqual(firstWindow.urls, [firstFile.url])
        firstWindow.isPresented = false
        XCTAssertFalse(firstWindow.accept([secondFile]))
        XCTAssertTrue(secondWindow.accept([secondFile]))
        firstWindow.didDismiss()
        XCTAssertEqual(secondWindow.urls, [secondFile.url])
        XCTAssertTrue(secondWindow.isPresented)
        XCTAssertTrue(firstWindow.accept(url: source))
        firstWindow.didDismiss()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Never remove an original URL opened by the user")
    }

    func testSameNamedFilesAreStagedSeparatelyAndRemainInDropOrder() throws {
        let first = try fixture()
        let second = try fixture()
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let files = try [first, second].map(MoneyMapCSVFile.stage)
        XCTAssertNotEqual(files[0].url, files[1].url)
        XCTAssertEqual(files[0].url.lastPathComponent, files[1].url.lastPathComponent)
        let review = MoneyMapCSVReview()
        XCTAssertTrue(review.accept(files))
        XCTAssertEqual(review.urls, files.map(\.url))
    }

    func testTransferStagingRejectsRemoteURLsAndDirectories() throws {
        XCTAssertThrowsError(try MoneyMapCSVFile.stage(XCTUnwrap(URL(string: "https://example.com/statement.csv"))))
        XCTAssertThrowsError(try MoneyMapCSVFile.stage(FileManager.default.temporaryDirectory))
    }

    private func fixture(named name: String = "Statement.csv") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let csv = """
        Transaction Date,Clearing Date,Description,Merchant,Category,Type,Amount (USD),Purchased By
        04-20-2026,04-21-2026,Coffee Shop,Local Cafe,Food,Purchase,5.25,Test
        """
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
