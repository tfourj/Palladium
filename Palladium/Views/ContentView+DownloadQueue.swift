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
        perLinkQualityActive = false
        pendingPerLinkQualityItemID = nil
        downloadQueue.start()
        persistDownloadQueue()
        runNextQueuedDownloadIfNeeded()
    }

    func startQueueWithPerLinkQuality() {
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
        perLinkQualityActive = true
        pendingPerLinkQualityItemID = nil
        downloadQueue.clearBatchQualityFromPending()
        downloadQueue.start()
        persistDownloadQueue()
        guard let nextItem = downloadQueue.nextPendingItem else { return }
        offerPerLinkQuality(for: nextItem)
    }

    func pauseDownloadQueue() {
        downloadQueue.pause()
        persistDownloadQueue()
    }

    func handlePickQualityAndStart() {
        guard !isResolvingQueueQuality,
              !isRunning,
              !isPackageRunning,
              downloadQueue.hasPendingItems else {
            return
        }

        if QueuedQualityPreferences.load().selectionMode == .choosePerLink {
            startQueueWithPerLinkQuality()
        } else {
            resolveQueueStartQuality()
        }
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

    func handleDownloadFormatSelection(_ format: YTDLPFormat) {
        if pendingPerLinkQualityItemID != nil {
            startQueuedDownloadWithSelectedFormat(format)
            return
        }

        if pendingBatchRepickItemID == nil {
            runDownloadFlow(formatOverride: format)
            return
        }

        pendingBatchRepickItemID = nil
        let selection = BatchQualitySelection(from: format)
        downloadQueue.applyBatchQualityToPending(selection)
        persistDownloadQueue()
        appendConsoleText("[palladium][queue] batch quality re-selected: \(selection.label)\n")
        startDownloadQueue()
    }

    func startQueuedDownloadWithSelectedFormat(_ format: YTDLPFormat) {
        guard let itemID = pendingPerLinkQualityItemID,
              let item = downloadQueue.items.first(where: { $0.id == itemID }) else {
            pendingPerLinkQualityItemID = nil
            return
        }

        pendingPerLinkQualityItemID = nil
        downloadQueue.markRunning(itemID)
        persistDownloadQueue()
        appendConsoleText(
            "[palladium][queue] quality selected for \(item.url): \(format.qualityHeading)\n"
        )
        selectedTab = .download
        urlText = item.url
        runDownloadFlow(
            urlOverride: item.url,
            presetOverride: item.configuration.preset,
            formatOverride: format,
            queuedItemID: item.id,
            queuedConfiguration: item.configuration,
            shouldClearConsole: false
        )
    }

    func offerPerLinkQuality(for item: DownloadQueueItem) {
        guard !isResolvingQueueQuality,
              !isResolvingFormats,
              pendingBatchRepickItemID == nil else {
            return
        }

        pendingPerLinkQualityItemID = item.id
        isResolvingQueueQuality = true
        progressText = String(localized: "download.formats.loading")
        let cookiePath = useCookies ? resolvedSelectedCookieFilePath() : nil
        appendConsoleText("[palladium][queue] resolving quality options for \(item.url)\n")
        Task {
            let resolution = await PythonFlowRunner.resolveFormats(url: item.url, cookieFilePath: cookiePath)
            await MainActor.run {
                isResolvingQueueQuality = false
                progressText = String(localized: "download.prompt.idle")
                guard !isRunning,
                      !isPackageRunning,
                      pendingPerLinkQualityItemID == item.id,
                      !isResolvingFormats else {
                    pendingPerLinkQualityItemID = nil
                    return
                }
                if resolution.success, !resolution.formats.isEmpty {
                    availableFormats = resolution.formats
                    formatPickerTitle = String(localized: "queue.quality.per_link.picker.title")
                    showDownloadQueueSheet = false
                    selectedTab = .download
                    urlText = item.url
                    showFormatPicker = true
                } else {
                    pendingPerLinkQualityItemID = nil
                    downloadQueue.pause()
                    persistDownloadQueue()
                    downloadErrorText = resolution.errorMessage
                        ?? String(localized: "download.formats.empty")
                    if !resolution.outputText.isEmpty {
                        appendConsoleText(resolution.outputText)
                    }
                }
            }
        }
    }

    func handleQueuedQualityUnavailable(itemID: UUID, url: String) {
        downloadQueue.requeue(itemID)
        downloadQueue.pause()
        persistDownloadQueue()
        appendConsoleText(
            "[palladium][queue] requested quality unavailable for \(url); pausing for re-selection\n"
        )
        showDownloadQueueSheet = false
        selectedTab = .download
        urlText = url
        pendingBatchRepickItemID = itemID
        resolveQueuedQualityRepick(url: url)
    }

    func resolveQueuedQualityRepick(url: String) {
        guard !isResolvingQueueQuality, !isResolvingFormats else {
            pendingBatchRepickItemID = nil
            return
        }

        isResolvingQueueQuality = true
        downloadErrorText = nil
        progressText = String(localized: "download.formats.loading")
        let cookiePath = useCookies ? resolvedSelectedCookieFilePath() : nil
        Task {
            let resolution = await PythonFlowRunner.resolveFormats(url: url, cookieFilePath: cookiePath)
            await MainActor.run {
                isResolvingQueueQuality = false
                progressText = String(localized: "download.prompt.idle")
                guard !isRunning,
                      !isPackageRunning,
                      !isResolvingFormats else {
                    pendingBatchRepickItemID = nil
                    return
                }
                if resolution.success, !resolution.formats.isEmpty {
                    availableFormats = resolution.formats
                    formatPickerTitle = String(localized: "queue.quality.repick.title")
                    showFormatPicker = true
                } else {
                    pendingBatchRepickItemID = nil
                    downloadErrorText = resolution.errorMessage
                        ?? String(localized: "download.formats.empty")
                    if !resolution.outputText.isEmpty {
                        appendConsoleText(resolution.outputText)
                    }
                }
            }
        }
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

        if perLinkQualityActive {
            offerPerLinkQuality(for: nextItem)
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
