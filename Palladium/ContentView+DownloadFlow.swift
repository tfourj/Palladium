//
//  ContentView+DownloadFlow.swift
//  Palladium
//

import SwiftUI
import Foundation
import OSLog

extension ContentView {
    var shareSheetDefaultPreset: DownloadPreset {
        shareSheetDownloadMode.preset ?? .autoVideo
    }

    var shareSheetModePickerSheet: some View {
        VStack(spacing: 20) {
            Text("Choose Download Mode")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)

            Text("How would you like to download this content?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 14) {
                shareSheetModeButton(
                    title: "Video",
                    subtitle: "Best quality available",
                    icon: "wand.and.stars",
                    color: .blue,
                    preset: .autoVideo
                )
                shareSheetModeButton(
                    title: "Audio Only",
                    subtitle: "Extract audio track",
                    icon: "music.note",
                    color: .green,
                    preset: .audio
                )
                shareSheetModeButton(
                    title: "Video (Muted)",
                    subtitle: "Video without audio",
                    icon: "speaker.slash",
                    color: .orange,
                    preset: .mute
                )
                shareSheetModeButton(
                    title: "Custom",
                    subtitle: "Use custom preset arguments",
                    icon: "slider.horizontal.3",
                    color: .indigo,
                    preset: .custom
                )
            }
            .padding(.horizontal)

            Button(action: {
                showShareSheetDownloadPicker = false
                shareSheetURL = ""
            }) {
                Text("Cancel")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }

    func shareSheetModeButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        preset: DownloadPreset
    ) -> some View {
        Button(action: {
            handleShareSheetModeSelection(preset)
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(shareSheetDefaultPreset == preset ? color.opacity(0.55) : .clear, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }

    func handleShareSheetModeSelection(_ preset: DownloadPreset) {
        let sharedLink = shareSheetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        showShareSheetDownloadPicker = false
        shareSheetURL = ""
        guard !sharedLink.isEmpty else { return }
        startDownloadFromSharedURL(sharedLink, preset: preset)
    }

    func startDownloadFromSharedURL(_ sharedLink: String, preset: DownloadPreset) {
        selectedTab = .download
        urlText = sharedLink
        appendConsoleText("[palladium] starting shared-link download preset=\(preset.rawValue)\n")
        runDownloadFlow(urlOverride: sharedLink, presetOverride: preset)
    }

    func handlePastedURL(_ pastedURL: String) {
        guard autoDownloadOnPaste else { return }
        if isRunning {
            appendConsoleText("[palladium] paste detected while download is already running\n")
            return
        }
        appendConsoleText("[palladium] auto download started from pasted url\n")
        runDownloadFlow(urlOverride: pastedURL, presetOverride: selectedPreset)
    }

    func runDownloadFlow(urlOverride: String? = nil, presetOverride: DownloadPreset? = nil) {
        guard !isRunning, !isPackageRunning else { return }
        let targetURL = (urlOverride ?? urlText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else { return }

        consoleLogStore.clearAll()
        downloadErrorText = nil
        completedDownloadResult = nil

        do {
            let removedCount = try clearDownloadsDirectoryContents()
            appendConsoleText("[palladium] cleared downloads folder entries: \(removedCount)\n")
        } catch {
            appendConsoleText("[palladium] failed to clear downloads folder: \(error.localizedDescription)\n")
        }

        let runOutputURL: URL
        do {
            runOutputURL = try makeDownloadRunDirectory()
            appendConsoleText("[palladium] run output folder: \(runOutputURL.lastPathComponent)\n")
        } catch {
            appendConsoleText("[palladium] failed to create run output folder: \(error.localizedDescription)\n")
            downloadErrorText = "Failed to prepare download folder."
            progressText = "download failed"
            return
        }

        isRunning = true
        statusText = "running"
        progressText = "Downloading..."
        lastDownloadProgressPercent = nil
        ffmpegProgressDurationSeconds = nil
        pendingDownloadProgressLine = ""

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        let presetAtStart = (presetOverride ?? selectedPreset).pythonValue
        let extraArgsAtStart = extraArgsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetArgsJSONAtStart = buildPresetArgumentsJSON()
        let afterDownloadBehaviorAtStart = afterDownloadBehavior
        let linkHistoryEnabledAtStart = linkHistoryEnabled
        let downloadPlaylistAtStart = downloadPlaylist
        let downloadSubtitlesAtStart = downloadSubtitles
        let embedThumbnailAtStart = embedThumbnail
        let subtitleLanguagePatternAtStart = resolvedSubtitleLanguagePattern
        var receivedPythonLiveOutput = false
        let liveLogDecoder = StreamingUTF8Decoder()
        let cancelMarker = makeCancelMarkerURL()
        cancelMarkerURL = cancelMarker
        setenv("PALLADIUM_LOG_FD", "\(writeFD)", 1)
        if let cancelMarker {
            setenv("PALLADIUM_CANCEL_FILE", cancelMarker.path, 1)
            try? FileManager.default.removeItem(at: cancelMarker)
        } else {
            unsetenv("PALLADIUM_CANCEL_FILE")
        }

        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = liveLogDecoder.append(data)
            guard !chunk.isEmpty else { return }
            receivedPythonLiveOutput = true
            Task { @MainActor in
                enqueueConsoleChunk(chunk, trackProgress: true)
            }
        }

        let task = Task {
            let outcome = await PythonFlowRunner.executeDownloadFlow(
                url: targetURL,
                preset: presetAtStart,
                presetArgsJSON: presetArgsJSONAtStart,
                extraArgs: extraArgsAtStart,
                downloadPlaylist: downloadPlaylistAtStart,
                downloadSubtitles: downloadSubtitlesAtStart,
                embedThumbnail: embedThumbnailAtStart,
                subtitleLanguagePattern: subtitleLanguagePatternAtStart,
                runOutputDir: runOutputURL.path
            )

            unsetenv("PALLADIUM_LOG_FD")
            unsetenv("PALLADIUM_CANCEL_FILE")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()
            let trailingChunk = liveLogDecoder.finish()
            await MainActor.run {
                if !trailingChunk.isEmpty {
                    receivedPythonLiveOutput = true
                    enqueueConsoleChunk(trailingChunk, trackProgress: true)
                }
                flushConsoleChunks()
            }
            if let cancelMarkerURL {
                try? FileManager.default.removeItem(at: cancelMarkerURL)
            }
            self.cancelMarkerURL = nil
            self.currentDownloadTask = nil

            isRunning = false
            lastDownloadProgressPercent = nil
            ffmpegProgressDurationSeconds = nil
            pendingDownloadProgressLine = ""
            statusText = outcome.statusText
            if outcome.statusText == "cancelled" {
                progressText = "download cancelled"
            } else {
                progressText = outcome.statusText == "success" ? "download complete" : "download failed"
            }
            if outcome.statusText == "error" {
                downloadErrorText = downloadErrorDetails(from: outcome)
            }
            appendConsoleText("\n\(outcome.summaryText)\n")
            if !receivedPythonLiveOutput {
                appendConsoleText(
                    "[palladium] live python log stream produced no decodable chunks; using buffered output fallback\n",
                    source: .app
                )
            }
            if !receivedPythonLiveOutput, !outcome.outputText.isEmpty {
                appendConsoleText("\n\(outcome.outputText)\n")
            }
            Self.logger.info("yt-dlp flow finished with status: \(outcome.statusText, privacy: .public)")

            if outcome.statusText == "success", !outcome.downloadedPaths.isEmpty {
                let resultTitle = extractHistoryTitle(
                    downloadedPaths: outcome.downloadedPaths,
                    primaryDownloadedPath: outcome.primaryDownloadedPath,
                    outputText: outcome.outputText
                )
                let result = CompletedDownloadResult(
                    items: outcome.downloadedPaths.map { URL(fileURLWithPath: $0) },
                    primaryMediaURL: outcome.primaryDownloadedPath.map { URL(fileURLWithPath: $0) },
                    folderURL: runOutputURL,
                    titleHint: resultTitle
                )
                if linkHistoryEnabledAtStart {
                    addLinkHistoryEntry(
                        url: targetURL,
                        presetRawValue: presetAtStart,
                        downloadedPaths: outcome.downloadedPaths,
                        primaryDownloadedPath: outcome.primaryDownloadedPath,
                        outputText: outcome.outputText
                    )
                }
                completedDownloadResult = result
                downloadErrorText = nil
                if let notificationTarget = result.notificationTargetURL {
                    notifyDownloadCompletionIfNeeded(fileURL: notificationTarget)
                }

                let needsPhotosCompatibilityCheck = afterDownloadBehaviorAtStart == .ask
                    || afterDownloadBehaviorAtStart.postDownloadAction == .saveToPhotos
                if needsPhotosCompatibilityCheck, let photosCandidateURL = result.photosCandidateURL {
                    completedPhotosCompatibility = .checking
                    completedPhotosCompatibility = await evaluatePhotosCompatibility(for: photosCandidateURL)
                } else {
                    completedPhotosCompatibility = .incompatible("Photos is only available for a single media file.")
                }

                if afterDownloadBehaviorAtStart == .ask {
                    showDownloadActionSheet = true
                } else if afterDownloadBehaviorAtStart.postDownloadAction == .saveToPhotos {
                    if completedPhotosCompatibility.isCompatible {
                        handlePostDownloadAction(.saveToPhotos, for: result)
                    } else {
                        showDownloadActionSheet = true
                    }
                } else if let action = afterDownloadBehaviorAtStart.postDownloadAction {
                    handlePostDownloadAction(action, for: result)
                }
            } else if outcome.statusText == "success" {
                downloadErrorText = "Download finished but no files were found."
            }
        }
        currentDownloadTask = task
    }

    func handleIncomingDownloadURL(_ incomingURL: URL) {
        guard incomingURL.scheme?.lowercased() == "palladium",
              incomingURL.host?.lowercased() == "download" else {
            return
        }

        guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let linkItem = queryItems.first(where: { $0.name == "url" }),
              let sharedLink = linkItem.value,
              !sharedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendConsoleText("[palladium] url scheme received but missing url query param\n")
            return
        }

        selectedTab = .download
        urlText = sharedLink
        appendConsoleText("[palladium] app opened via url scheme. link: \(sharedLink)\n")

        if isRunning {
            appendConsoleText("[palladium] download already running, queued link in input field only\n")
            return
        }

        if shareSheetDownloadMode == .ask {
            shareSheetURL = sharedLink
            showShareSheetDownloadPicker = true
            return
        }

        let presetToUse = shareSheetDownloadMode.preset ?? .autoVideo
        startDownloadFromSharedURL(sharedLink, preset: presetToUse)
    }

    func cancelDownloadFlow() {
        guard isRunning else { return }
        requestActiveOperationCancellation()
        currentDownloadTask?.cancel()
        pendingDownloadProgressLine = ""
        ffmpegProgressDurationSeconds = nil
        progressText = "Cancelling..."
    }

    func updateProgress(from chunk: String) {
        let normalized = chunk
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let combined = pendingDownloadProgressLine + normalized
        guard !combined.isEmpty else { return }

        var lines = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if combined.hasSuffix("\n") {
            pendingDownloadProgressLine = ""
        } else {
            pendingDownloadProgressLine = lines.popLast() ?? ""
        }

        for line in lines {
            updateProgressLine(line)
        }
    }

    func updateProgressLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("[palladium][ffmpeg-progress] duration=") {
            ffmpegProgressDurationSeconds = parseFFmpegDuration(from: trimmed)
        } else if trimmed.hasPrefix("[palladium][ffmpeg-progress] time=") {
            if let update = parseFFmpegProgressUpdate(from: trimmed) {
                if let progressPercent = update.percent {
                    lastDownloadProgressPercent = progressPercent
                    let clampedPercent = min(max(progressPercent, 0), 100)
                    if let speedText = update.speedText {
                        progressText = String(format: "Processing with ffmpeg... %.1f%% (%@)", clampedPercent, speedText)
                    } else {
                        progressText = String(format: "Processing with ffmpeg... %.1f%%", clampedPercent)
                    }
                } else {
                    progressText = "Processing with ffmpeg..."
                }
            }
        } else if detailedProgressEnabled, shouldShowDetailedProgressLine(trimmed) {
            progressText = trimmed
        } else if trimmed.contains("[download]") {
            guard shouldAcceptDownloadProgressLine(trimmed) else { return }
            progressText = trimmed
        } else if trimmed.contains("[Merger]") {
            progressText = trimmed
        } else if trimmed.contains("yt-dlp Popen running ffmpeg") {
            progressText = "Merging audio and video..."
        } else if trimmed.contains("yt-dlp Popen ffmpeg finished") {
            progressText = "Merge finished"
        } else if trimmed.contains("[palladium] downloaded file:") {
            progressText = "download complete"
        } else if trimmed.hasPrefix("[ExtractAudio]") {
            progressText = trimmed
        } else if trimmed.hasPrefix("[palladium] running yt-dlp") {
            progressText = "Downloading..."
            lastDownloadProgressPercent = nil
        }
    }

    private func shouldShowDetailedProgressLine(_ line: String) -> Bool {
        if line.hasPrefix("[palladium][ffmpeg-progress]") {
            return false
        }
        return true
    }

    func downloadErrorDetails(from outcome: PythonFlowOutcome) -> String? {
        var lines: [String] = []

        let errorLines = outcome.outputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.hasPrefix("ERROR:") }
        if let lastErrorLine = errorLines.last {
            lines.append(lastErrorLine)
        }

        if let ytDlpExitCode = outcome.ytDlpExitCode {
            lines.append("yt-dlp exit code: \(ytDlpExitCode)")
        }
        if let pipExitCode = outcome.pipExitCode, pipExitCode != 0 {
            lines.append("pip exit code: \(pipExitCode)")
        }

        if lines.isEmpty {
            return nil
        }
        return lines.joined(separator: "\n")
    }

    func enqueueConsoleChunk(_ chunk: String, trackProgress: Bool) {
        if trackProgress {
            updateProgress(from: chunk)
        }
        guard !chunk.isEmpty else { return }
        pendingConsoleChunks.append(chunk)
        guard !isConsoleFlushScheduled else { return }
        isConsoleFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            flushConsoleChunks()
        }
    }

    func flushConsoleChunks() {
        isConsoleFlushScheduled = false
        guard !pendingConsoleChunks.isEmpty else { return }
        appendConsoleText(pendingConsoleChunks)
        pendingConsoleChunks = ""
    }

    private func shouldAcceptDownloadProgressLine(_ line: String) -> Bool {
        guard let newPercent = extractDownloadPercent(from: line) else {
            return true
        }

        guard let lastPercent = lastDownloadProgressPercent else {
            lastDownloadProgressPercent = newPercent
            return true
        }

        if newPercent + 0.05 >= lastPercent {
            lastDownloadProgressPercent = newPercent
            return true
        }

        if lastPercent >= 99.5 && newPercent <= 5 {
            lastDownloadProgressPercent = newPercent
            return true
        }

        return false
    }

    private func parseFFmpegDuration(from line: String) -> Double? {
        guard let value = line.split(separator: "=", maxSplits: 1).last else {
            return nil
        }
        return parseFFmpegTimestamp(String(value))
    }

    private func parseFFmpegProgressUpdate(from line: String) -> (percent: Double?, speedText: String?)? {
        let payload = line.replacingOccurrences(of: "[palladium][ffmpeg-progress] ", with: "")
        let fields = payload.split(separator: " ").map(String.init)
        var currentTimeText: String?
        var speedText: String?

        for field in fields {
            if field.hasPrefix("time=") {
                currentTimeText = String(field.dropFirst(5))
            } else if field.hasPrefix("speed=") {
                speedText = String(field.dropFirst(6))
            }
        }

        guard let currentTimeText else {
            return nil
        }

        let currentTimeSeconds = parseFFmpegTimestamp(currentTimeText)
        let percent: Double?
        if let currentTimeSeconds,
           let durationSeconds = ffmpegProgressDurationSeconds,
           durationSeconds > 0 {
            percent = (currentTimeSeconds / durationSeconds) * 100
        } else {
            percent = nil
        }

        return (percent, speedText)
    }

    private func parseFFmpegTimestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return (hours * 3600) + (minutes * 60) + seconds
    }

    private func extractDownloadPercent(from line: String) -> Double? {
        guard let range = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        let rawValue = line[range].dropLast()
        return Double(rawValue)
    }
}
