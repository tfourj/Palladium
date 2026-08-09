import XCTest
@testable import Palladium

@MainActor
final class DownloadQueueTests: XCTestCase {
    private var configuration: QueuedDownloadConfiguration {
        QueuedDownloadConfiguration(
            presetRawValue: DownloadPreset.audio.rawValue,
            presetArgumentsJSON: #"{"audio":"-x"}"#,
            extraArguments: "--no-mtime",
            downloadPlaylist: false,
            downloadSubtitles: true,
            embedThumbnail: true,
            autoRetryFailedDownloads: true,
            subtitleLanguagePattern: "en",
            useCookies: true,
            cookieFileName: "example.txt",
            afterDownloadBehaviorRawValue: AfterDownloadBehavior.saveToApplicationFolder.rawValue
        )
    }

    func testParsingPreservesOrderAndDuplicates() {
        let links = DownloadQueue.parsedLinks(
            from: " https://example.com/one \n\nhttps://example.com/two\nhttps://example.com/one "
        )

        XCTAssertEqual(
            links,
            [
                "https://example.com/one",
                "https://example.com/two",
                "https://example.com/one"
            ]
        )
    }

    func testBatchUsesConfigurationSnapshotForEveryItem() {
        var queue = DownloadQueue()

        let added = queue.append(
            linksText: "https://example.com/one\nhttps://example.com/two",
            configuration: configuration
        )

        XCTAssertEqual(added.count, 2)
        XCTAssertTrue(added.allSatisfy { $0.configuration == configuration })
        XCTAssertEqual(queue.outstandingCount, 2)
    }

    func testQueueAdvancesInFIFOOrderAndStopsWhenFinished() throws {
        var queue = makeQueue()
        queue.start()

        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)
        queue.markCompleted(first.id, partial: false)

        let second = try XCTUnwrap(queue.nextPendingItem)
        XCTAssertEqual(second.url, "https://example.com/two")
        queue.markRunning(second.id)
        queue.markFailed(second.id, errorMessage: "failed")

        XCTAssertFalse(queue.isActive)
        XCTAssertNil(queue.nextPendingItem)
    }

    func testCancelPausesRemainingQueueAndRestartRunsItemImmediately() throws {
        var queue = makeQueue()
        queue.start()

        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)
        queue.markCancelled(first.id)

        XCTAssertFalse(queue.isActive)
        XCTAssertEqual(queue.items.first?.status, .cancelled)
        XCTAssertEqual(queue.items.last?.status, .pending)

        let restarted = try XCTUnwrap(queue.restart(first.id))

        XCTAssertEqual(restarted.id, first.id)
        XCTAssertEqual(queue.items.first?.status, .running)
        XCTAssertEqual(queue.nextPendingItem?.url, "https://example.com/two")
        XCTAssertEqual(queue.outstandingCount, 2)
    }

    func testRestartDoesNothingWhileAnotherItemIsRunning() throws {
        var queue = makeQueue()
        queue.start()

        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)
        queue.markFailed(first.id, errorMessage: "failed")

        let second = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(second.id)

        XCTAssertNil(queue.restart(first.id))
        XCTAssertEqual(queue.items.first?.status, .failed)
        XCTAssertEqual(queue.currentItem?.id, second.id)
    }

    func testFailureKeepsQueueActiveWhenAnotherItemIsPending() throws {
        var queue = makeQueue()
        queue.start()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)

        queue.markFailed(first.id, errorMessage: "failed")

        XCTAssertTrue(queue.isActive)
        XCTAssertEqual(queue.nextPendingItem?.url, "https://example.com/two")
    }

    func testPauseLetsCurrentItemFinishWithoutStartingAnother() throws {
        var queue = makeQueue()
        queue.start()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)

        queue.pause()
        queue.markAwaitingAction(first.id)
        queue.markCompleted(first.id, partial: false)

        XCTAssertFalse(queue.isActive)
        XCTAssertEqual(queue.nextPendingItem?.url, "https://example.com/two")
    }

    func testPendingItemsCanMoveWithoutChangingTerminalRows() throws {
        var queue = makeQueue()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.start()
        queue.markRunning(first.id)
        queue.markFailed(first.id, errorMessage: "failed")

        _ = queue.append(
            linksText: "https://example.com/three",
            configuration: configuration
        )
        queue.movePending(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(queue.items.first?.status, .failed)
        XCTAssertEqual(
            queue.pendingItems.map(\.url),
            [
                "https://example.com/three",
                "https://example.com/two"
            ]
        )
    }

    func testPersistenceRestoresUnfinishedItemsPaused() throws {
        let suiteName = "DownloadQueueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var queue = makeQueue()
        queue.start()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)
        DownloadQueuePersistence.save(queue, to: defaults)

        let restored = DownloadQueuePersistence.load(from: defaults)

        XCTAssertFalse(restored.isActive)
        XCTAssertEqual(restored.items.count, 2)
        XCTAssertEqual(restored.items.first?.status, .pending)
    }

    func testPersistenceDropsCompletedItemsButKeepsRetryableItems() throws {
        let suiteName = "DownloadQueueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var queue = makeQueue()
        queue.start()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)
        queue.markCompleted(first.id, partial: false)
        let second = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(second.id)
        queue.markFailed(second.id, errorMessage: "failed")
        DownloadQueuePersistence.save(queue, to: defaults)

        let restored = DownloadQueuePersistence.load(from: defaults)

        XCTAssertEqual(restored.items.count, 1)
        XCTAssertEqual(restored.items.first?.status, .failed)
    }

    private func makeQueue() -> DownloadQueue {
        var queue = DownloadQueue()
        queue.append(
            linksText: "https://example.com/one\nhttps://example.com/two",
            configuration: configuration
        )
        return queue
    }
}
