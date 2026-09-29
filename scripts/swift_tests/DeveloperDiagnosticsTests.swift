import XCTest
@testable import Palladium

final class DeveloperDiagnosticsTests: XCTestCase {
    func testParsesFFmpegVersionAndConfiguration() {
        let output = """
        ffmpeg version n8.0.1 Copyright (c) 2000-2025 the FFmpeg developers
        configuration: --enable-gpl --enable-libopus
        """
        XCTAssertEqual(DeveloperDiagnostics.ffmpegVersion(from: output), "n8.0.1")
        XCTAssertEqual(DeveloperDiagnostics.ffmpegVersion(from: "ffprobe version 8.1 Copyright"), "8.1")
        XCTAssertNil(DeveloperDiagnostics.ffmpegVersion(from: "configuration: --enable-gpl"))
        XCTAssertEqual(DeveloperDiagnostics.ffmpegConfiguration(from: output), "--enable-gpl --enable-libopus")
    }

    func testDecodesPythonDiagnosticPayload() {
        let payload = """
        {"ok": true, "output": "ready", "error": null, "duration_ms": 12,
         "details": {"version": "3.14.0", "packages": {"yt-dlp": "2026.8.19"}}}
        """
        let result = DeveloperDiagnostics.decodePythonResult(payload)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.output, "ready")
        XCTAssertEqual(result.durationMS, 12)
        XCTAssertEqual(result.details.map(\.key), ["packages", "version"])
        XCTAssertTrue(result.details[0].value.contains("\"yt-dlp\" : \"2026.8.19\""))
    }

    func testInvalidPythonPayloadIsAFailure() {
        let result = DeveloperDiagnostics.decodePythonResult("not json")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.output, "not json")
    }

    func testNativeQuickJSChecksUseTheEmbeddedEngine() async {
        let info = await DeveloperDiagnostics.quickJS(["operation": "info"])
        XCTAssertTrue(info.ok)
        XCTAssertEqual(info.details.first { $0.key == "name" }?.value, "quickjs-ng")

        let failure = await DeveloperDiagnostics.quickJS(["operation": "evaluate", "source": "throw new Error('x')"])
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.details.first { $0.key == "status" }?.value, "exception")
    }

    func testNativeFFmpegReportsVersion() async {
        let result = await DeveloperDiagnostics.ffmpeg(tool: .ffmpeg, arguments: ["-hide_banner", "-version"])
        XCTAssertTrue(result.ok, result.report)
        XCTAssertNotNil(result.details.first { $0.key == "version" })
    }

    func testNativeFFmpegEncodesAndProbesTestMedia() async {
        let result = await DeveloperDiagnostics.ffmpegEncodeTest()
        XCTAssertTrue(result.ok, result.report)
        XCTAssertEqual(result.details.first { $0.key == "streams" }?.value, "mpeg4, aac")
    }

    func testStandardChecksCoverEveryFramework() {
        let frameworks = Set(DeveloperDiagnostics.standardChecks.map(\.framework))
        XCTAssertEqual(frameworks, [.python, .ffmpeg, .curlCffi, .quickJS])
        let ids = DeveloperDiagnostics.standardChecks.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
