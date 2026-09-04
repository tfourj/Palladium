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

    func resolveQueueStartQuality() {
        guard !isResolvingQueueQuality,
              !isRunning,
              !isPackageRunning,
              let firstPendingItem = downloadQueue.pendingItems.first else {
            return
        }

        isResolvingQueueQuality = true
        let cookiePath = useCookies ? resolvedSelectedCookieFilePath() : nil
        appendConsoleText("[palladium][queue] resolving quality options for \(firstPendingItem.url)\n")
        Task {
            let resolution = await PythonFlowRunner.resolveFormats(
                url: firstPendingItem.url,
                cookieFilePath: cookiePath
            )
            await MainActor.run {
                isResolvingQueueQuality = false
                guard !isRunning, !isPackageRunning else { return }
                if resolution.success, !resolution.formats.isEmpty {
                    queueQualityFormats = resolution.formats
                    queueQualityPickerTitle = String(localized: "queue.quality.picker.title")
                    showQueueQualityPicker = true
                } else {
                    alertMessage = resolution.errorMessage ?? String(localized: "download.formats.empty")
                    showAlert = true
                    if !resolution.outputText.isEmpty {
                        appendConsoleText(resolution.outputText)
                    }
                }
            }
        }
    }

    func applyQueueStartQuality(_ format: YTDLPFormat) {
        let selection = BatchQualitySelection(from: format)
        downloadQueue.applyBatchQualityToPending(selection)
        persistDownloadQueue()
        appendConsoleText("[palladium][queue] batch quality applied: \(selection.label)\n")
        startDownloadQueue()
    }

    func retryDownloadQueueItem(_ id: UUID) {
        guard !isRunning,
              !isPackageRunning,
              awaitingQueueItemID == nil,
              completedDownloadResult == nil,
              let item = downloadQueue.restart(id) else {
            return
        }

        if !queueConsoleInitialized {
            consoleLogStore.clearAll()
            queueConsoleInitialized = true
        }
        downloadErrorText = nil
        playlistProgress = nil
        persistDownloadQueue()
        runQueuedDownload(item, logAction: "retrying")
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
        runQueuedDownload(nextItem, logAction: "starting")
    }

    private func runQueuedDownload(_ item: DownloadQueueItem, logAction: String) {
        selectedTab = .download
        urlText = item.url
        appendConsoleText(
            "\n[palladium][queue] \(logAction) \(item.url) preset=\(item.configuration.presetRawValue)\n"
        )
        runDownloadFlow(
            urlOverride: item.url,
            presetOverride: item.configuration.preset,
            queuedItemID: item.id,
            queuedConfiguration: item.configuration,
            shouldClearConsole: false
        )
    }

    func queuedDownloadAwaitingAction(
        itemID: UUID,
        title: String?,
        partial: Bool
    ) {
        showDownloadQueueSheet = false
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
