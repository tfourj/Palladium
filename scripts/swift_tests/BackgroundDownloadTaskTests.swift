import XCTest
@testable import Palladium

final class BackgroundDownloadTaskTests: XCTestCase {
    func testKeepsFinishedResultAfterStop() {
        XCTAssertTrue(BackgroundDownloadTask.keepsResult(afterStopWithResultKind: "success", downloadedPathCount: 1))
        XCTAssertTrue(BackgroundDownloadTask.keepsResult(afterStopWithResultKind: "partial", downloadedPathCount: 2))
    }

    func testDiscardsUnfinishedResultAfterStop() {
        XCTAssertFalse(BackgroundDownloadTask.keepsResult(afterStopWithResultKind: "success", downloadedPathCount: 0))
        XCTAssertFalse(BackgroundDownloadTask.keepsResult(afterStopWithResultKind: "failed", downloadedPathCount: 1))
        XCTAssertFalse(BackgroundDownloadTask.keepsResult(afterStopWithResultKind: "cancelled", downloadedPathCount: 1))
    }

    func testHeartbeatStepsByOneUnitWhileDownloading() {
        XCTAssertEqual(BackgroundDownloadTask.heartbeatStep(completedUnitCount: 500_000, totalUnitCount: 1_000_000), 1)
    }

    func testHeartbeatStepsByShareOfRemainingDuringPostProcessing() {
        XCTAssertEqual(
            BackgroundDownloadTask.heartbeatStep(completedUnitCount: 950_000, totalUnitCount: 1_000_000),
            1_000
        )
        XCTAssertEqual(
            BackgroundDownloadTask.heartbeatStep(completedUnitCount: 990_000, totalUnitCount: 1_000_000),
            200
        )
    }

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
