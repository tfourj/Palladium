import XCTest
@testable import Palladium

final class PackageActivityLineTests: XCTestCase {
    func testLatestReturnsLastMeaningfulLine() {
        let chunk = "Collecting yt-dlp==2026.8.19\n  Downloading yt_dlp-2026.8.19-py3-none-any.whl (3.2 MB)\n\n"
        XCTAssertEqual(
            PackageActivityLine.latest(in: chunk),
            "Downloading yt_dlp-2026.8.19-py3-none-any.whl (3.2 MB)"
        )
    }

    func testPalladiumPrefixIsRemovedAndMarkersAreSkipped() {
        let chunk = "[palladium] pip installed into target: /tmp/site\n[palladium][ffmpeg-progress] {\"time\":1}\n"
        XCTAssertEqual(PackageActivityLine.latest(in: chunk), "pip installed into target: /tmp/site")
    }

    func testCarriageReturnsAndExtraWhitespaceAreHandled() {
        XCTAssertEqual(
            PackageActivityLine.latest(in: "WARNING:   Retrying   (total=4)\r\n"),
            "WARNING: Retrying (total=4)"
        )
    }

    func testEmptyChunksHaveNoActivity() {
        XCTAssertNil(PackageActivityLine.latest(in: ""))
        XCTAssertNil(PackageActivityLine.latest(in: "  \n\r\n[palladium]\n"))
    }

    func testLongLinesAreTruncated() {
        let line = String(repeating: "a", count: PackageActivityLine.maxLength + 20)
        let text = PackageActivityLine.latest(in: line)
        XCTAssertEqual(text?.count, PackageActivityLine.maxLength)
        XCTAssertEqual(text?.last, "…")
    }
}
