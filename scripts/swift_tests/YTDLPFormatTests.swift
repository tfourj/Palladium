import XCTest
@testable import Palladium

final class YTDLPFormatTests: XCTestCase {
    private func makeFormat(
        id: String,
        ext: String,
        videoCodec: String,
        audioCodec: String,
        height: Int? = nil
    ) -> YTDLPFormat {
        YTDLPFormat(
            id: id,
            fileExtension: ext,
            resolution: height.map { "\($0)p" } ?? "audio only",
            width: height.map { $0 * 16 / 9 },
            height: height,
            framesPerSecond: nil,
            videoBitrate: nil,
            audioBitrate: nil,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            fileSize: nil,
            note: ""
        )
    }

    func testResolvedCombinationDownloadsExactVideoAndAudio() {
        let format = makeFormat(id: "628+251", ext: "webm", videoCodec: "vp09.00.51.08", audioCodec: "opus")

        XCTAssertEqual(format.downloadOverrideArguments(usesQualitySettings: false), "--format 628+251")
        XCTAssertTrue(format.hasVideo)
        XCTAssertTrue(format.hasAudio)
        XCTAssertFalse(format.isPhotosCompatible)
    }

    func testPhotosCompatibilityUsesResolvedAudio() {
        let aac = makeFormat(id: "137+140", ext: "mp4", videoCodec: "avc1.640028", audioCodec: "mp4a.40.2")
        let opus = makeFormat(id: "137+251", ext: "mkv", videoCodec: "avc1.640028", audioCodec: "opus")
        let opusMP4 = makeFormat(id: "137+251", ext: "mp4", videoCodec: "avc1.640028", audioCodec: "opus")

        XCTAssertTrue(aac.isPhotosCompatible)
        XCTAssertFalse(opus.isPhotosCompatible)
        XCTAssertFalse(opusMP4.isPhotosCompatible)
        XCTAssertEqual(aac.downloadOverrideArguments(usesQualitySettings: true), "--format 137+140")
        XCTAssertEqual(opus.downloadOverrideArguments(usesQualitySettings: false), "--format 137+251")
    }

    func testProgressiveSelectionKeepsExactFormat() {
        let format = makeFormat(id: "22", ext: "mp4", videoCodec: "avc1.64001f", audioCodec: "mp4a.40.2")

        XCTAssertEqual(format.downloadOverrideArguments(usesQualitySettings: false), "--format 22")
    }

    func testVideoWithoutAvailableAudioDoesNotChooseAnotherVideo() {
        let format = makeFormat(id: "137", ext: "mp4", videoCodec: "avc1.640028", audioCodec: "none")

        XCTAssertFalse(format.hasAudio)
        XCTAssertEqual(format.downloadOverrideArguments(usesQualitySettings: false), "--format 137")
    }

    func testAudioSelectionPreservesExistingExtractionBehavior() {
        let format = makeFormat(id: "251", ext: "webm", videoCodec: "none", audioCodec: "opus")

        XCTAssertEqual(format.downloadOverrideArguments(usesQualitySettings: true), "--format 251")
        XCTAssertEqual(
            format.downloadOverrideArguments(usesQualitySettings: false),
            "--format 251 --extract-audio --audio-format best"
        )
    }
}
