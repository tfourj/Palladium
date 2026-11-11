import XCTest
@testable import Palladium

final class DeveloperDiagnosticsTests: XCTestCase {
    func testNativeFFmpegEncodesAndProbesTestMedia() async {
        let result = await DeveloperDiagnostics.ffmpegEncodeTest()
        XCTAssertTrue(result.ok, result.report)
        XCTAssertEqual(result.details.first { $0.key == "streams" }?.value, "mpeg4, aac")
    }
}
