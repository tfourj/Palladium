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

    private func makeVideoOnly(
        id: String,
        ext: String,
        codec: String,
        height: Int
    ) -> YTDLPFormat {
        makeFormat(id: id, ext: ext, videoCodec: codec, audioCodec: "none", height: height)
    }

    func testIssue54VP9HLSVideoOnlyPredictsMKVContainer() {
        let format = makeVideoOnly(id: "628", ext: "mp4", codec: "vp09.00.51.08", height: 2160)

        XCTAssertEqual(format.predictedOutputExtension, "mkv")
        XCTAssertEqual(
            format.downloadOverrideArguments(usesQualitySettings: false),
            "--format 628+bestaudio/best"
        )
    }

    func testWebMVideoOnlyPredictsWebMContainer() {
        let format = makeVideoOnly(id: "303", ext: "webm", codec: "vp09.00.51.08", height: 2160)

        XCTAssertEqual(format.predictedOutputExtension, "webm")
        XCTAssertEqual(
            format.downloadOverrideArguments(usesQualitySettings: false),
            "--format 303+bestaudio/best"
        )
    }

    func testPhotosCompatibleVideoOnlyPredictsMP4Container() {
        let format = makeVideoOnly(id: "137", ext: "mp4", codec: "avc1.640028", height: 1080)

        XCTAssertTrue(format.isPhotosCompatible)
        XCTAssertEqual(format.predictedOutputExtension, "mp4")
        XCTAssertEqual(
            format.downloadOverrideArguments(usesQualitySettings: true),
            "--format 137+bestaudio[ext=m4a]/137+bestaudio/best"
        )
    }

    func testProgressiveFormatsKeepNativeExtensionWithoutMergeArgument() {
        let mp4 = makeFormat(id: "22", ext: "mp4", videoCodec: "avc1.64001f", audioCodec: "mp4a.40.2", height: 720)
        let webm = makeFormat(id: "247", ext: "webm", videoCodec: "vp9", audioCodec: "opus", height: 1080)

        XCTAssertEqual(mp4.predictedOutputExtension, "mp4")
        XCTAssertNil(mp4.mergeOutputArgument)
        XCTAssertEqual(mp4.downloadOverrideArguments(usesQualitySettings: true), "--format 22")

        XCTAssertEqual(webm.predictedOutputExtension, "webm")
        XCTAssertNil(webm.mergeOutputArgument)
        XCTAssertEqual(webm.downloadOverrideArguments(usesQualitySettings: true), "--format 247")
    }

    func testAudioOnlyFormatsKeepNativeExtensionAndExtraction() {
        let format = makeFormat(id: "140", ext: "m4a", videoCodec: "none", audioCodec: "mp4a.40.2")

        XCTAssertEqual(format.predictedOutputExtension, "m4a")
        XCTAssertNil(format.mergeOutputArgument)
        XCTAssertEqual(format.downloadOverrideArguments(usesQualitySettings: true), "--format 140")
        XCTAssertEqual(
            format.downloadOverrideArguments(usesQualitySettings: false),
            "--format 140 --extract-audio --audio-format best"
        )
    }
}
