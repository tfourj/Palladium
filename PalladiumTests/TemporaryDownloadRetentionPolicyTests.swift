import XCTest
@testable import Palladium

final class TemporaryDownloadRetentionPolicyTests: XCTestCase {
    func testRemovesSourceWhenCleanupIsAllowedAndTemporaryDownloadsAreHidden() {
        XCTAssertTrue(
            TemporaryDownloadRetentionPolicy.shouldRemoveSource(
                showsTemporaryDownloads: false,
                resultAllowsCleanup: true
            )
        )
    }

    func testKeepsSourceWhenTemporaryDownloadsAreVisible() {
        XCTAssertFalse(
            TemporaryDownloadRetentionPolicy.shouldRemoveSource(
                showsTemporaryDownloads: true,
                resultAllowsCleanup: true
            )
        )
    }

    func testKeepsHiddenSourceWhenResultDisallowsCleanup() {
        XCTAssertFalse(
            TemporaryDownloadRetentionPolicy.shouldRemoveSource(
                showsTemporaryDownloads: false,
                resultAllowsCleanup: false
            )
        )
    }

    func testKeepsVisibleSourceWhenResultDisallowsCleanup() {
        XCTAssertFalse(
            TemporaryDownloadRetentionPolicy.shouldRemoveSource(
                showsTemporaryDownloads: true,
                resultAllowsCleanup: false
            )
        )
    }
}
