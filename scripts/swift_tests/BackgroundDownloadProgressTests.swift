import XCTest
@testable import Palladium

final class BackgroundDownloadProgressTests: XCTestCase {
    func testCombinesMergedStreamsIntoOneFraction() {
        var progress = BackgroundDownloadProgress()
        progress.handleLine("[info] abc123: Downloading 1 format(s): 137+140")
        progress.handleLine("[download] Destination: /tmp/Video [abc123].f137.mp4")
        progress.handleLine("[download]  50.0% of 10.00MiB at 1.00MiB/s ETA 00:05")

        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)

        progress.handleLine("[download] 100% of 10.00MiB in 00:00:10")
        progress.handleLine("[download] Destination: /tmp/Video [abc123].f140.m4a")
        progress.handleLine("[download]   2.0% of 1.00MiB at 1.00MiB/s ETA 00:01")

        XCTAssertEqual(progress.fraction, 0.51, accuracy: 0.0001)
    }

    func testOrdersStreamsByStartWhenAudioDownloadsFirst() {
        var progress = BackgroundDownloadProgress()
        progress.handleLine("[info] abc123: Downloading 1 format(s): 137+140")
        progress.handleLine("[download] Destination: /tmp/Video.f140.m4a")
        progress.handleLine("[download] 100% of 1.00MiB in 00:00:01")

        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)

        progress.handleLine("[download] Destination: /tmp/Video.f137.mp4")

        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
    }

    func testRetriedStreamKeepsItsPosition() {
        var progress = BackgroundDownloadProgress()
        progress.handleLine("[info] abc123: Downloading 1 format(s): 137+140")
        progress.handleLine("[download] Destination: /tmp/Video.f137.mp4")
        progress.handleLine("[download]  40.0% of 10.00MiB at 1.00MiB/s ETA 00:06")
        progress.handleLine("[download] Destination: /tmp/Video.f137.mp4")

        XCTAssertEqual(progress.streamIndex, 0)
        XCTAssertEqual(progress.fraction, 0, accuracy: 0.0001)
    }

    func testIgnoresSubtitleDownloads() {
        var progress = BackgroundDownloadProgress()
        progress.handleLine("[info] abc123: Downloading 1 format(s): 22")
        progress.handleLine("[download] Destination: /tmp/Video.en.vtt")
        progress.handleLine("[download] 100% of 40.00KiB in 00:00:00")

        XCTAssertEqual(progress.fraction, 0, accuracy: 0.0001)

        progress.handleLine("[download] Destination: /tmp/Video.mp4")
        progress.handleLine("[download]  30.0% of 10.00MiB at 1.00MiB/s ETA 00:07")

        XCTAssertEqual(progress.fraction, 0.3, accuracy: 0.0001)
    }

    func testProcessingReplacesDownloadFraction() {
        var progress = BackgroundDownloadProgress()
        progress.handleLine("[info] abc123: Downloading 1 format(s): 22")
        progress.handleLine("[download] Destination: /tmp/Video.mp4")
        progress.handleLine("[download] 100% of 10.00MiB in 00:00:10")
        progress.updateProcessing(percent: 40)

        XCTAssertTrue(progress.isProcessing)
        XCTAssertEqual(progress.fraction, 0.4, accuracy: 0.0001)
    }

    func testNextPlaylistItemResetsProgress() {
        var progress = BackgroundDownloadProgress()
        progress.handleLine("[info] first: Downloading 1 format(s): 22")
        progress.handleLine("[download] Destination: /tmp/First.mp4")
        progress.handleLine("[download] 100% of 10.00MiB in 00:00:10")
        progress.updateProcessing(percent: 100)
        progress.handleLine("[info] second: Downloading 1 format(s): 18")

        XCTAssertFalse(progress.isProcessing)
        XCTAssertEqual(progress.formatIDs, ["18"])
        XCTAssertEqual(progress.fraction, 0, accuracy: 0.0001)
    }
}
