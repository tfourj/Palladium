import XCTest
@testable import Palladium

final class DownloadPresetTests: XCTestCase {
    func testSponsorBlockAppliesOnlyToVideoPresets() {
        XCTAssertTrue(DownloadPreset.autoVideo.supportsSponsorBlock)
        XCTAssertTrue(DownloadPreset.mute.supportsSponsorBlock)
        XCTAssertTrue(DownloadPreset.custom.supportsSponsorBlock)
        XCTAssertFalse(DownloadPreset.audio.supportsSponsorBlock)
        XCTAssertFalse(DownloadPreset.images.supportsSponsorBlock)
    }
}
