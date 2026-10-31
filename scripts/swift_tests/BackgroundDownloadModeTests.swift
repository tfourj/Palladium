import XCTest
@testable import Palladium

final class BackgroundDownloadModeTests: XCTestCase {
    func testDefaultsToSystemTaskOutsideLiveContainer() {
        XCTAssertEqual(BackgroundDownloadMode.defaultMode(isRunningInLiveContainer: false), .systemTask)
    }

    func testDefaultsToSilentAudioInLiveContainer() {
        XCTAssertEqual(BackgroundDownloadMode.defaultMode(isRunningInLiveContainer: true), .silentAudio)
    }

    func testSilentAudioIsSupportedOnEverySystem() {
        XCTAssertTrue(BackgroundDownloadTask.isSupported(in: .silentAudio))
        XCTAssertEqual(BackgroundDownloadTask.isSupported(in: .systemTask), BackgroundDownloadTask.isSupported)
    }
}
