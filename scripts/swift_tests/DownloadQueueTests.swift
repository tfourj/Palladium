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

    private func makeVideoFormat(
        id: String,
        height: Int,
        codec: String,
        extension ext: String
    ) -> YTDLPFormat {
        YTDLPFormat(
            id: id,
            fileExtension: ext,
            resolution: "\(height)p",
            width: height * 16 / 9,
            height: height,
            framesPerSecond: nil,
            videoBitrate: nil,
            audioBitrate: nil,
            videoCodec: codec,
            audioCodec: "none",
            fileSize: nil,
            note: ""
        )
    }

    private func makeAudioFormat(bitrate: Double?) -> YTDLPFormat {
        YTDLPFormat(
            id: "140",
            fileExtension: "m4a",
            resolution: "audio only",
            width: nil,
            height: nil,
            framesPerSecond: nil,
            videoBitrate: nil,
            audioBitrate: bitrate,
            videoCodec: "none",
            audioCodec: "mp4a.40.2",
            fileSize: nil,
            note: ""
        )
    }

    func testVideoQualitySelectorArgumentsMatchHeight() {
        let selection = BatchQualitySelection(
            kind: .video,
            height: 1080,
            photosCompatible: false,
            label: "1080p"
        )

        XCTAssertEqual(
            selection.formatArguments(usesQualitySettings: true),
            "--format bv*[height=1080]+bestaudio/b[height=1080]"
        )
        XCTAssertEqual(
            selection.formatArguments(usesQualitySettings: false),
            "--format bv*[height=1080]+bestaudio/b[height=1080]"
        )
    }

    func testPhotosCompatibleQualityPrefersM4AAudio() {
        let selection = BatchQualitySelection(
            kind: .video,
            height: 720,
            photosCompatible: true,
            label: "720p"
        )

        XCTAssertEqual(
            selection.formatArguments(usesQualitySettings: true),
            "--format bv*[height=720]+bestaudio[ext=m4a]/bv*[height=720]+bestaudio/b[height=720]"
        )
    }

    func testAudioQualityAddsExtractionOnlyWithoutQualitySettings() {
        let selection = BatchQualitySelection(
            kind: .audio,
            height: nil,
            photosCompatible: false,
            label: "192 kbps"
        )

        XCTAssertEqual(selection.formatArguments(usesQualitySettings: true), "--format ba/b")
        XCTAssertEqual(
            selection.formatArguments(usesQualitySettings: false),
            "--format ba/b --extract-audio --audio-format best"
        )
    }

    func testQualitySelectionDerivedFromVideoFormat() {
        let format = makeVideoFormat(
            id: "137",
            height: 1080,
            codec: "avc1.640028",
            extension: "mp4"
        )

        let selection = BatchQualitySelection(from: format)

        XCTAssertEqual(selection.kind, .video)
        XCTAssertEqual(selection.height, 1080)
        XCTAssertTrue(selection.photosCompatible)
        XCTAssertEqual(selection.label, "1080p")
    }

    func testQualitySelectionDerivedFromAudioFormat() {
        let format = makeAudioFormat(bitrate: 128)

        let selection = BatchQualitySelection(from: format)

        XCTAssertEqual(selection.kind, .audio)
        XCTAssertNil(selection.height)
        XCTAssertFalse(selection.photosCompatible)
        XCTAssertEqual(selection.label, "128 kbps")
    }

    func testUnavailableFormatOutputDetection() {
        XCTAssertTrue(
            BatchQualitySelection.outputIndicatesUnavailableFormat(
                "ERROR: Requested format is not available. Use --list-formats for a list of available formats"
            )
        )
        XCTAssertFalse(
            BatchQualitySelection.outputIndicatesUnavailableFormat(
                "ERROR: [youtube] jNQXAC9IVRw: Private video. Sign in if you've been granted access"
            )
        )
    }

    func testApplyBatchQualityUpdatesOnlyPendingItems() throws {
        var queue = makeQueue()
        queue.start()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)
        let selection = BatchQualitySelection(
            kind: .video,
            height: 1080,
            photosCompatible: false,
            label: "1080p"
        )

        let updatedCount = queue.applyBatchQualityToPending(selection)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(
            queue.pendingItems.compactMap(\.configuration.batchQuality),
            [selection]
        )
        XCTAssertNil(
            queue.items.first(where: { $0.id == first.id })?.configuration.batchQuality
        )
    }

    func testRequeueRestoresRunningItemToPending() throws {
        var queue = makeQueue()
        queue.start()
        let first = try XCTUnwrap(queue.nextPendingItem)
        queue.markRunning(first.id)

        queue.requeue(first.id)

        let requeued = try XCTUnwrap(queue.items.first(where: { $0.id == first.id }))
        XCTAssertEqual(requeued.status, .pending)
        XCTAssertNil(queue.currentItem)
        XCTAssertEqual(queue.nextPendingItem?.id, first.id)
    }

    func testBatchQualitySurvivesPersistenceRoundTrip() throws {
        var queue = makeQueue()
        let selection = BatchQualitySelection(
            kind: .video,
            height: 1080,
            photosCompatible: false,
            label: "1080p"
        )
        queue.applyBatchQualityToPending(selection)

        let data = try JSONEncoder().encode(queue.persistableState())
        let decoded = try JSONDecoder().decode(DownloadQueue.self, from: data)

        XCTAssertEqual(
            decoded.items.compactMap(\.configuration.batchQuality),
            [selection, selection]
        )
    }

    func testLegacyQueueJSONWithoutBatchQualityDecodes() throws {
        let legacyJSON = """
        {
          "items" : [
            {
              "id" : "11111111-1111-1111-1111-111111111111",
              "url" : "https://example.com/one",
              "configuration" : {
                "presetRawValue" : "audio",
                "presetArgumentsJSON" : "{}",
                "extraArguments" : "",
                "downloadPlaylist" : false,
                "downloadSubtitles" : false,
                "embedThumbnail" : false,
                "autoRetryFailedDownloads" : false,
                "subtitleLanguagePattern" : "en",
                "useCookies" : false,
                "cookieFileName" : "",
                "afterDownloadBehaviorRawValue" : "ask"
              },
              "createdAt" : 0,
              "status" : "pending"
            }
          ],
          "isActive" : false
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))

        let decoded = try JSONDecoder().decode(DownloadQueue.self, from: data)

        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items.first?.url, "https://example.com/one")
        XCTAssertNil(decoded.items.first?.configuration.batchQuality)
    }
}
