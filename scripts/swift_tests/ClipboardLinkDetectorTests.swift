import Foundation
import XCTest
@testable import Palladium

final class ClipboardLinkDetectorTests: XCTestCase {
    func testEmptyOrMissingTextHasNoLink() {
        XCTAssertNil(ClipboardLinkDetector.firstLink(in: nil))
        XCTAssertNil(ClipboardLinkDetector.firstLink(in: ""))
        XCTAssertNil(ClipboardLinkDetector.firstLink(in: "   \n"))
    }

    func testPlainLinkIsReturned() {
        XCTAssertEqual(
            ClipboardLinkDetector.firstLink(in: "  https://www.youtube.com/watch?v=example \n"),
            "https://www.youtube.com/watch?v=example"
        )
    }

    func testLinkInsideSharedTextIsReturned() {
        XCTAssertEqual(
            ClipboardLinkDetector.firstLink(in: "Check this out https://vm.tiktok.com/example/ and more"),
            "https://vm.tiktok.com/example/"
        )
    }

    func testFirstWebLinkIsPreferred() {
        XCTAssertEqual(
            ClipboardLinkDetector.firstLink(in: "https://youtu.be/first https://youtu.be/second"),
            "https://youtu.be/first"
        )
    }

    func testTextWithoutLinkIsIgnored() {
        XCTAssertNil(ClipboardLinkDetector.firstLink(in: "just some copied text"))
    }

    func testNonWebLinksAreIgnored() {
        XCTAssertNil(ClipboardLinkDetector.firstLink(in: "mailto:someone@example.com"))
        XCTAssertNil(ClipboardLinkDetector.firstLink(in: "ftp://example.com/file"))
        XCTAssertEqual(
            ClipboardLinkDetector.firstLink(in: "ftp://example.com/file https://example.com/video"),
            "https://example.com/video"
        )
    }
}
