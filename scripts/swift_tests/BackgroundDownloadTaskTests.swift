import XCTest
@testable import Palladium

final class BackgroundDownloadTaskTests: XCTestCase {
    func testHeartbeatNeverCompletesProgress() {
        XCTAssertEqual(BackgroundDownloadTask.heartbeatStep(completedUnitCount: 999_990, totalUnitCount: 1_000_000), 1)
        XCTAssertEqual(BackgroundDownloadTask.heartbeatStep(completedUnitCount: 999_999, totalUnitCount: 1_000_000), 0)
        XCTAssertEqual(
            BackgroundDownloadTask.heartbeatStep(completedUnitCount: 1_000_000, totalUnitCount: 1_000_000),
            0
        )
    }

    func testHeartbeatStaysBelowCompleteOverManySteps() {
        var completed: Int64 = 950_000
        for _ in 0..<10_000 {
            completed += BackgroundDownloadTask.heartbeatStep(completedUnitCount: completed, totalUnitCount: 1_000_000)
        }
        XCTAssertEqual(completed, 999_999)
    }
}
