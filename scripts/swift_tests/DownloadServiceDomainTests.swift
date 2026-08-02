import Foundation
import XCTest
@testable import Palladium

final class DownloadServiceDomainTests: XCTestCase {
    func testMissingURLHasNoCanonicalHost() {
        XCTAssertNil(DownloadServiceDomain.canonicalHost(for: nil))
    }

    func testTikTokSubdomainsUseTikTokCanonicalHost() {
        assertCanonicalHost(
            "tiktok.com",
            for: [
                "https://tiktok.com/@creator/video/1",
                "https://www.tiktok.com/@creator/video/1",
                "https://vm.tiktok.com/example",
                "https://vt.tiktok.com/example",
            ]
        )
    }

    func testYouTubeAliasesAndSubdomainsUseYouTubeCanonicalHost() {
        assertCanonicalHost(
            "youtube.com",
            for: [
                "https://youtube.com/watch?v=example",
                "https://m.youtube.com/watch?v=example",
                "https://music.youtube.com/watch?v=example",
                "https://youtu.be/example",
                "https://www.youtube-nocookie.com/embed/example",
            ]
        )
    }

    func testCanonicalHostUsesRegistrableDomain() {
        assertCanonicalHost(
            "example.com",
            for: ["https://media.example.com/video"]
        )
        assertCanonicalHost(
            "bbc.co.uk",
            for: ["https://news.bbc.co.uk/video"]
        )
    }

    func testIPAddressIsPreserved() {
        assertCanonicalHost(
            "127.0.0.1",
            for: ["https://127.0.0.1/video"]
        )
        assertCanonicalHost(
            "2001:db8::1",
            for: ["https://[2001:db8::1]/video"]
        )
    }

    private func assertCanonicalHost(
        _ expectedHost: String,
        for sources: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for source in sources {
            XCTAssertEqual(
                DownloadServiceDomain.canonicalHost(for: URL(string: source)),
                expectedHost,
                "Unexpected canonical host for \(source)",
                file: file,
                line: line
            )
        }
    }
}
