import Foundation

extension ContentView {
    func makeQueuedDownloadConfiguration() -> QueuedDownloadConfiguration {
        QueuedDownloadConfiguration(
            presetRawValue: selectedPreset.rawValue,
            presetArgumentsJSON: buildPresetArgumentsJSON(),
            extraArguments: extraArgsText.trimmingCharacters(in: .whitespacesAndNewlines),
            downloadPlaylist: downloadPlaylist,
            downloadSubtitles: downloadSubtitles,
            embedThumbnail: embedThumbnail,
            autoRetryFailedDownloads: autoRetryFailedDownloads,
            subtitleLanguagePattern: resolvedSubtitleLanguagePattern,
            useCookies: useCookies,
            cookieFileName: selectedCookieFileName,
            afterDownloadBehaviorRawValue: afterDownloadBehavior.rawValue
        )
    }

    @discardableResult
    func addLinksToDownloadQueue(_ linksText: String) -> Int {
        guard selectedPreset != .images else { return 0 }
        let added = downloadQueue.append(
            linksText: linksText,
            configuration: makeQueuedDownloadConfiguration()
        )
        persistDownloadQueue()
        return added.count
    }

    func startDownloadQueue() {
        guard !isRunning,
              !isPackageRunning,
              completedDownloadResult == nil,
              downloadQueue.hasPendingItems else {
            return
        }

        if !queueConsoleInitialized {
            consoleLogStore.clearAll()
            queueConsoleInitialized = true
        }
        downloadErrorText = nil
        playlistProgress = nil
        downloadQueue.start()
        persistDownloadQueue()
        runNextQueuedDownloadIfNeeded()
    }

    func pauseDownloadQueue() {
        downloadQueue.pause()
        persistDownloadQueue()
    }

    func retryDownloadQueueItem(_ id: UUID) {
        downloadQueue.retry(id)
        persistDownloadQueue()
        if downloadQueue.isActive {
            runNextQueuedDownloadIfNeeded()
        }
    }

    func removeDownloadQueueItem(_ id: UUID) {
        downloadQueue.remove(id)
        persistDownloadQueue()
        if downloadQueue.items.isEmpty {
            queueConsoleInitialized = false
        }
    }

    func clearFinishedDownloadQueueItems() {
        downloadQueue.clearTerminalItems()
        persistDownloadQueue()
        if downloadQueue.items.isEmpty {
            queueConsoleInitialized = false
        }
    }

    func movePendingDownloadQueueItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        downloadQueue.movePending(fromOffsets: source, toOffset: destination)
        persistDownloadQueue()
    }

    func runNextQueuedDownloadIfNeeded() {
        guard downloadQueue.isActive,
              !isRunning,
              !isPackageRunning,
              awaitingQueueItemID == nil,
              completedDownloadResult == nil,
              let nextItem = downloadQueue.nextPendingItem else {
            return
        }

        downloadQueue.markRunning(nextItem.id)
        persistDownloadQueue()
        selectedTab = .download
        urlText = nextItem.url
        appendConsoleText(
            "\n[palladium][queue] starting \(nextItem.url) preset=\(nextItem.configuration.presetRawValue)\n"
        )
        runDownloadFlow(
            urlOverride: nextItem.url,
            presetOverride: nextItem.configuration.preset,
            queuedItemID: nextItem.id,
            queuedConfiguration: nextItem.configuration,
            shouldClearConsole: false
        )
    }

    func queuedDownloadAwaitingAction(
        itemID: UUID,
        title: String?,
        partial: Bool
    ) {
        downloadQueue.markAwaitingAction(itemID, title: title)
        awaitingQueueItemID = itemID
        awaitingQueueItemWasPartial = partial
        persistDownloadQueue()
    }

    func queuedDownloadFailed(itemID: UUID, errorMessage: String?) {
        downloadQueue.markFailed(itemID, errorMessage: errorMessage)
        persistDownloadQueue()
        appendConsoleText("[palladium][queue] item failed\n")
        scheduleNextQueuedDownload()
    }

    func queuedDownloadCancelled(itemID: UUID) {
        downloadQueue.markCancelled(itemID)
        persistDownloadQueue()
        appendConsoleText("[palladium][queue] item cancelled; queue paused\n")
    }

    func handleQueuePostDownloadActionCompletion(_ succeeded: Bool) {
        guard awaitingQueueItemID != nil else { return }

        guard succeeded else {
            downloadQueue.pause()
            persistDownloadQueue()
            reopenDownloadActionAfterAlert = true
            if !showAlert {
                showDownloadActionSheet = true
            }
            return
        }

        completeAwaitingDownloadQueueItem()
    }

    func completeAwaitingDownloadQueueItem() {
        guard let itemID = awaitingQueueItemID else { return }

        downloadQueue.markCompleted(
            itemID,
            partial: awaitingQueueItemWasPartial,
            title: completedResultDisplayTitle
        )
        awaitingQueueItemID = nil
        awaitingQueueItemWasPartial = false
        completedDownloadResult = nil
        completedDownloadAllowsSaveToApplicationFolder = true
        completedPhotosCompatibility = .checking
        persistDownloadQueue()
        appendConsoleText("[palladium][queue] item completed\n")
        scheduleNextQueuedDownload()
    }

    func handleShareSheetDismissal() {
        let completion = shareSheetCompletion
        shareSheetCompletion = nil
        completion?()
        guard advancePostDownloadAfterSharing else { return }
        advancePostDownloadAfterSharing = false
        advancePostDownloadPromptSequence()
    }

    func persistDownloadQueue() {
        DownloadQueuePersistence.save(downloadQueue)
    }

    private func scheduleNextQueuedDownload() {
        DispatchQueue.main.async {
            runNextQueuedDownloadIfNeeded()
        }
    }
}
