import Foundation
import XCTest
@testable import Palladium

final class LinkPreviewTests: XCTestCase {
    private func makePreview(
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil,
        approximate: Bool = false
    ) -> LinkPreview {
        LinkPreview(
            title: "Example",
            uploader: "Channel",
            site: "Youtube",
            duration: duration,
            thumbnailURL: nil,
            fileSize: fileSize,
            fileSizeIsApproximate: approximate,
            isPlaylist: false,
            entryCount: nil
        )
    }

    func testSingleWebLinkIsPreviewed() {
        XCTAssertEqual(
            LinkPreviewPolicy.previewURL(for: "  https://youtu.be/example \n"),
            "https://youtu.be/example"
        )
    }

    func testEmptyTextAndNonWebLinksAreNotPreviewed() {
        XCTAssertNil(LinkPreviewPolicy.previewURL(for: ""))
        XCTAssertNil(LinkPreviewPolicy.previewURL(for: "not a link"))
        XCTAssertNil(LinkPreviewPolicy.previewURL(for: "ftp://example.com/file"))
        XCTAssertNil(LinkPreviewPolicy.previewURL(for: "https://"))
    }

    func testMultipleLinksAreNotPreviewed() {
        XCTAssertNil(LinkPreviewPolicy.previewURL(for: "https://youtu.be/first\nhttps://youtu.be/second"))
    }

    func testTypingIsDebouncedButPastesAreNot() {
        XCTAssertTrue(LinkPreviewPolicy.shouldDebounce(from: "https://youtu.be/ab", to: "https://youtu.be/abc"))
        XCTAssertTrue(LinkPreviewPolicy.shouldDebounce(from: "https://youtu.be/abc", to: "https://youtu.be/ab"))
        XCTAssertFalse(LinkPreviewPolicy.shouldDebounce(from: "", to: "https://youtu.be/abc"))
        XCTAssertFalse(LinkPreviewPolicy.shouldDebounce(from: "https://youtu.be/abc", to: "https://youtu.be/abc"))
    }

    func testHistoryMatchUsesTrimmedLink() {
        let entry = LinkHistoryEntry(
            id: UUID(),
            url: "https://youtu.be/example",
            presetRawValue: DownloadPreset.autoVideo.rawValue,
            title: nil,
            timestamp: Date()
        )

        XCTAssertTrue(LinkPreviewPolicy.isInHistory(" https://youtu.be/example ", entries: [entry]))
        XCTAssertFalse(LinkPreviewPolicy.isInHistory("https://youtu.be/other", entries: [entry]))
        XCTAssertFalse(LinkPreviewPolicy.isInHistory("", entries: [entry]))
    }

    func testDurationUsesMinutesOrHours() {
        XCTAssertEqual(makePreview(duration: 65).durationText, "1:05")
        XCTAssertEqual(makePreview(duration: 3725).durationText, "1:02:05")
        XCTAssertNil(makePreview(duration: 0).durationText)
        XCTAssertNil(makePreview().durationText)
    }

    func testDecoderReadsPythonPayload() {
        let payload = """
        {"success": true, "title": "Video", "uploader": "Channel", "site": "Youtube", "duration": 212.0,
         "thumbnail": "https://example.com/thumb.jpg", "filesize": 4000, "filesize_is_approximate": true,
         "is_playlist": false, "entry_count": null, "output": "", "error_message": null}
        """
        let preview = PythonFlowRunner.decodeLinkPreview(payload).preview

        XCTAssertEqual(preview?.title, "Video")
        XCTAssertEqual(preview?.duration, 212)
        XCTAssertEqual(preview?.thumbnailURL, URL(string: "https://example.com/thumb.jpg"))
        XCTAssertEqual(preview?.fileSize, 4000)
        XCTAssertEqual(preview?.fileSizeIsApproximate, true)
        XCTAssertNil(preview?.entryCount)
    }

    func testDecoderReportsFailure() {
        let resolution = PythonFlowRunner.decodeLinkPreview(
            #"{"success": false, "output": "trace", "error_message": "Unavailable"}"#
        )

        XCTAssertNil(resolution.preview)
        XCTAssertEqual(resolution.errorMessage, "Unavailable")
        XCTAssertEqual(resolution.outputText, "trace")
    }
}
