import Foundation
import XCTest
@testable import Palladium

final class AutoPastePolicyTests: XCTestCase {
    private let link = "https://www.youtube.com/watch?v=example"

    func testSuccessfulDownloadClearsMatchingLink() {
        XCTAssertTrue(
            AutoPastePolicy.shouldClearLinkField(linkText: " \(link)\n", finishedURL: link, resultKind: "success")
        )
    }

    func testFailedOrPartialDownloadKeepsLink() {
        XCTAssertFalse(AutoPastePolicy.shouldClearLinkField(linkText: link, finishedURL: link, resultKind: "partial"))
        XCTAssertFalse(AutoPastePolicy.shouldClearLinkField(linkText: link, finishedURL: link, resultKind: "error"))
        XCTAssertFalse(
            AutoPastePolicy.shouldClearLinkField(linkText: link, finishedURL: link, resultKind: "cancelled")
        )
    }

    func testEditedLinkIsKept() {
        XCTAssertFalse(
            AutoPastePolicy.shouldClearLinkField(
                linkText: "https://youtu.be/other",
                finishedURL: link,
                resultKind: "success"
            )
        )
    }
}
