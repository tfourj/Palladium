//
//  ContentView.swift
//  Palladium
//
//  Created by TfourJ on 3. 3. 26.
//

import SwiftUI
import OSLog
import Foundation
import UIKit
import Photos
import AVFoundation
import UserNotifications

struct ContentView: View {
    private enum AppTab: Hashable {
        case download
        case packages
        case settings
        case console
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium",
        category: "python"
    )

    private static let presetDefaultsKey = "palladium.selectedPreset"
    private static let customArgsDefaultsKey = "palladium.customArgs"
    private static let extraArgsDefaultsKey = "palladium.extraArgs"
    private static let askUserAfterDownloadDefaultsKey = "palladium.askUserAfterDownload"
    private static let selectedPostDownloadActionDefaultsKey = "palladium.selectedPostDownloadAction"
    private static let notificationsEnabledDefaultsKey = "palladium.notificationsEnabled"

    @Environment(\.scenePhase) private var scenePhase
    @State private var isRunning = false
    @State private var statusText = "idle"
    @State private var urlText: String
    @State private var progressText = "Enter a URL and tap Download."
    @State private var selectedPreset: DownloadPreset
    @State private var customArgsText: String
    @State private var extraArgsText: String
    @State private var askUserAfterDownload: Bool
    @State private var selectedPostDownloadAction: PostDownloadAction
    @State private var notificationsEnabled: Bool
    @State private var selectedTab: AppTab = .download
    @State private var packageStatusText = "idle"
    @State private var versionsText = "yt-dlp: unknown\nyt-dlp-apple-webkit-jsi: unknown"
    @State private var packageUpdatesAvailable = false
    @State private var packageUpdatesSummaryText = "Updates not checked yet."
    @State private var consoleLogText = ""
    @State private var completedDownloadURL: URL?
    @State private var showDownloadActionDialog = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var shareItem: ShareItem?
    @State private var currentDownloadTask: Task<Void, Never>?
    @State private var cancelMarkerURL: URL?
    @State private var pendingConsoleChunks = ""
    @State private var isConsoleFlushScheduled = false

    private let consoleMaxChars = 200_000

    init() {
        #if DEBUG
        _urlText = State(initialValue: "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        #else
        _urlText = State(initialValue: "")
        #endif
        _selectedPreset = State(initialValue: Self.loadSelectedPreset())
        _customArgsText = State(initialValue: Self.loadCustomArgs())
        _extraArgsText = State(initialValue: Self.loadExtraArgs())
        _askUserAfterDownload = State(initialValue: Self.loadAskUserAfterDownload())
        _selectedPostDownloadAction = State(initialValue: Self.loadSelectedPostDownloadAction())
        _notificationsEnabled = State(initialValue: Self.loadNotificationsEnabled())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DownloadTabView(
                statusText: $statusText,
                urlText: $urlText,
                selectedPreset: $selectedPreset,
                isRunning: isRunning,
                progressText: progressText,
                onDownload: runDownloadFlow,
                onCancel: cancelDownloadFlow
            )
            .tabItem {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .tag(AppTab.download)

            PackagesTabView(
                packageStatusText: packageStatusText,
                versionsText: versionsText,
                updatesSummaryText: packageUpdatesSummaryText,
                updatesAvailable: packageUpdatesAvailable,
                isRunning: isRunning,
                onRefreshVersions: refreshPackageVersions,
                onUpdatePackages: updatePackages
            )
            .tabItem {
                Label("Packages", systemImage: "shippingbox")
            }
            .tag(AppTab.packages)

            SettingsTabView(
                customArgsText: $customArgsText,
                extraArgsText: $extraArgsText,
                askUserAfterDownload: $askUserAfterDownload,
                selectedPostDownloadAction: $selectedPostDownloadAction,
                notificationsEnabled: $notificationsEnabled,
                isRunning: isRunning
            )
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .tag(AppTab.settings)

            ConsoleTabView(consoleLogText: $consoleLogText)
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }
                .tag(AppTab.console)
        }
        .onChange(of: selectedPreset) { _ in
            persistPreferences()
        }
        .onChange(of: customArgsText) { _ in
            persistPreferences()
        }
        .onChange(of: extraArgsText) { _ in
            persistPreferences()
        }
        .onChange(of: askUserAfterDownload) { _ in
            persistPreferences()
        }
        .onChange(of: selectedPostDownloadAction) { _ in
            persistPreferences()
        }
        .onChange(of: notificationsEnabled) { _ in
            persistPreferences()
            debugNotification("setting changed notificationsEnabled=\(notificationsEnabled)")
            if notificationsEnabled {
                requestNotificationAuthorizationIfNeeded()
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .confirmationDialog("Download Complete", isPresented: $showDownloadActionDialog, titleVisibility: .visible) {
            if completedDownloadURL != nil {
                Button("Share") {
                    if let url = completedDownloadURL {
                        handlePostDownloadAction(.openShareSheet, for: url)
                    }
                }
                Button("Save to Photos") {
                    if let url = completedDownloadURL {
                        handlePostDownloadAction(.saveToPhotos, for: url)
                    }
                }
                Button("Save to App Folder") {
                    if let url = completedDownloadURL {
                        handlePostDownloadAction(.saveToApplicationFolder, for: url)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to do with the downloaded file.")
        }
        .alert("Result", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func runDownloadFlow() {
        guard !isRunning else { return }
        let targetURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else { return }

        consoleLogText = ""
        pendingConsoleChunks = ""
        isConsoleFlushScheduled = false

        do {
            let removedCount = try clearDownloadsDirectoryContents()
            appendConsoleText("[palladium] cleared downloads folder entries: \(removedCount)\n")
        } catch {
            appendConsoleText("[palladium] failed to clear downloads folder: \(error.localizedDescription)\n")
        }

        isRunning = true
        statusText = "running"
        progressText = "Downloading..."

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        let presetAtStart = selectedPreset.pythonValue
        let extraArgsAtStart = extraArgsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetArgsJSONAtStart = buildPresetArgumentsJSON()
        let askUserAfterDownloadAtStart = askUserAfterDownload
        let selectedPostDownloadActionAtStart = selectedPostDownloadAction
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
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                enqueueConsoleChunk(chunk, trackProgress: true)
            }
        }

        let task = Task {
            let outcome = await PythonFlowRunner.executeDownloadFlow(
                url: targetURL,
                preset: presetAtStart,
                presetArgsJSON: presetArgsJSONAtStart,
                extraArgs: extraArgsAtStart
            )

            unsetenv("PALLADIUM_LOG_FD")
            unsetenv("PALLADIUM_CANCEL_FILE")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()
            await MainActor.run { flushConsoleChunks() }
            if let cancelMarkerURL {
                try? FileManager.default.removeItem(at: cancelMarkerURL)
            }
            self.cancelMarkerURL = nil
            self.currentDownloadTask = nil

            isRunning = false
            statusText = outcome.statusText
            if outcome.statusText == "cancelled" {
                progressText = "download cancelled"
            } else {
                progressText = outcome.statusText == "success" ? "download complete" : "download failed"
            }
            let outputBody = filteredConsoleChunk(outcome.outputText)
            appendConsoleText("\n\(outcome.summaryText)\n\n\(outputBody)\n")
            Self.logger.info("yt-dlp flow finished with status: \(outcome.statusText, privacy: .public)")
            Self.logger.info("\(consoleLogText, privacy: .public)")
            print(consoleLogText)

            if outcome.statusText == "success",
               let downloadedPath = outcome.downloadedPath,
               FileManager.default.fileExists(atPath: downloadedPath) {
                let completedURL = URL(fileURLWithPath: downloadedPath)
                completedDownloadURL = completedURL
                notifyDownloadCompletionIfNeeded(fileURL: completedURL)
                if askUserAfterDownloadAtStart {
                    showDownloadActionDialog = true
                } else {
                    handlePostDownloadAction(selectedPostDownloadActionAtStart, for: completedURL)
                }
            }
        }
        currentDownloadTask = task
    }

    private func cancelDownloadFlow() {
        guard isRunning else { return }
        if let markerURL = cancelMarkerURL {
            try? "cancel".write(to: markerURL, atomically: true, encoding: .utf8)
        }
        currentDownloadTask?.cancel()
        progressText = "Cancelling..."
    }

    private func runPackageFlow(action: String) {
        guard !isRunning else { return }

        isRunning = true
        packageStatusText = action == "update" ? "updating" : "checking"

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        setenv("PALLADIUM_LOG_FD", "\(writeFD)", 1)

        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                enqueueConsoleChunk(chunk, trackProgress: false)
            }
        }

        Task {
            let outcome = await PythonFlowRunner.executePackageFlow(action: action)

            unsetenv("PALLADIUM_LOG_FD")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()
            await MainActor.run { flushConsoleChunks() }

            isRunning = false
            packageStatusText = outcome.statusText
            let outputBody = outcome.outputText
            appendConsoleText("\n\(outcome.summaryText)\n\n\(outputBody)\n")
            if let versionsText = outcome.versionsText {
                self.versionsText = versionsText
            }
            if let updatesAvailable = outcome.updatesAvailable {
                self.packageUpdatesAvailable = updatesAvailable
            }
            if let updatesSummary = outcome.updatesSummary {
                self.packageUpdatesSummaryText = updatesSummary
            }
            Self.logger.info("package flow finished with status: \(outcome.statusText, privacy: .public)")
            Self.logger.info("\(consoleLogText, privacy: .public)")
            print(consoleLogText)
        }
    }

    private func refreshPackageVersions() {
        runPackageFlow(action: "check")
    }

    private func updatePackages() {
        runPackageFlow(action: "update")
    }

    private func updateProgress(from chunk: String) {
        let normalized = chunk.replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("[download]") {
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
            }
        }
    }

    private func enqueueConsoleChunk(_ chunk: String, trackProgress: Bool) {
        if trackProgress {
            updateProgress(from: chunk)
        }
        let chunkForConsole = trackProgress ? filteredConsoleChunk(chunk) : chunk
        guard !chunkForConsole.isEmpty else { return }
        pendingConsoleChunks.append(chunkForConsole)
        guard !isConsoleFlushScheduled else { return }
        isConsoleFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            flushConsoleChunks()
        }
    }

    private func flushConsoleChunks() {
        isConsoleFlushScheduled = false
        guard !pendingConsoleChunks.isEmpty else { return }
        appendConsoleText(pendingConsoleChunks)
        pendingConsoleChunks = ""
    }

    private func appendConsoleText(_ text: String) {
        consoleLogText.append(text)
        if consoleLogText.count > consoleMaxChars {
            let overflow = consoleLogText.count - consoleMaxChars
            let dropCount = min(overflow + 5_000, consoleLogText.count)
            consoleLogText.removeFirst(dropCount)
        }
    }

    private func filteredConsoleChunk(_ chunk: String) -> String {
        let normalized = chunk.replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return false
            }
            if trimmed.contains("[download]") && trimmed.contains("% of") {
                return false
            }
            return true
        }
        guard !filtered.isEmpty else { return "" }
        return filtered.joined(separator: "\n") + "\n"
    }

    private func saveDownloadedFileToPhotos(_ url: URL) {
        Task {
            let codecDescription = detectedVideoCodecDescription(for: url)
            let compatible = UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path)
            guard compatible else {
                await MainActor.run {
                    alertMessage = "iOS Photos cannot import this video format. Detected codec: \(codecDescription). Try remuxing to MP4/H.264 or HEVC."
                    showAlert = true
                }
                return
            }

            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                await MainActor.run {
                    alertMessage = "Photo library permission was denied."
                    showAlert = true
                }
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                await MainActor.run {
                    alertMessage = "Saved to Photos. Codec: \(codecDescription)"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to save to Photos: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func saveDownloadedFileToApplicationFolder(_ url: URL) {
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appFolder = documents.appendingPathComponent("Saved", isDirectory: true)
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            let destination = appFolder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            alertMessage = "Saved to app folder: \(destination.lastPathComponent)"
            showAlert = true
        } catch {
            alertMessage = "Failed to save to app folder: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func handlePostDownloadAction(_ action: PostDownloadAction, for url: URL) {
        switch action {
        case .saveToPhotos:
            saveDownloadedFileToPhotos(url)
        case .openShareSheet:
            shareItem = ShareItem(url: url)
        case .saveToApplicationFolder:
            saveDownloadedFileToApplicationFolder(url)
        }
    }

    private func detectedVideoCodecDescription(for url: URL) -> String {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let firstFormat = track.formatDescriptions.first else {
            return "unknown"
        }

        let format = firstFormat as! CMFormatDescription
        let subtype = CMFormatDescriptionGetMediaSubType(format)
        return fourCC(subtype)
    }

    private func fourCC(_ code: FourCharCode) -> String {
        let n = UInt32(code).bigEndian
        let bytes: [UInt8] = [
            UInt8((n >> 24) & 0xFF),
            UInt8((n >> 16) & 0xFF),
            UInt8((n >> 8) & 0xFF),
            UInt8(n & 0xFF)
        ]
        let chars = bytes.map { b -> Character in
            if b >= 32 && b <= 126 {
                return Character(UnicodeScalar(b))
            }
            return "."
        }
        return String(chars)
    }

    private func persistPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(selectedPreset.rawValue, forKey: Self.presetDefaultsKey)
        defaults.set(customArgsText, forKey: Self.customArgsDefaultsKey)
        defaults.set(extraArgsText, forKey: Self.extraArgsDefaultsKey)
        defaults.set(askUserAfterDownload, forKey: Self.askUserAfterDownloadDefaultsKey)
        defaults.set(selectedPostDownloadAction.rawValue, forKey: Self.selectedPostDownloadActionDefaultsKey)
        defaults.set(notificationsEnabled, forKey: Self.notificationsEnabledDefaultsKey)
    }

    private static func loadSelectedPreset() -> DownloadPreset {
        guard let rawValue = UserDefaults.standard.string(forKey: presetDefaultsKey),
              let preset = DownloadPreset(rawValue: rawValue) else {
            return .autoVideo
        }
        return preset
    }

    private static func loadCustomArgs() -> String {
        UserDefaults.standard.string(forKey: customArgsDefaultsKey) ?? ""
    }

    private static func loadExtraArgs() -> String {
        UserDefaults.standard.string(forKey: extraArgsDefaultsKey) ?? ""
    }

    private static func loadAskUserAfterDownload() -> Bool {
        if UserDefaults.standard.object(forKey: askUserAfterDownloadDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: askUserAfterDownloadDefaultsKey)
    }

    private static func loadSelectedPostDownloadAction() -> PostDownloadAction {
        guard let raw = UserDefaults.standard.string(forKey: selectedPostDownloadActionDefaultsKey),
              let action = PostDownloadAction(rawValue: raw) else {
            return .openShareSheet
        }
        return action
    }

    private static func loadNotificationsEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: notificationsEnabledDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: notificationsEnabledDefaultsKey)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            debugNotification("permission status=\(settings.authorizationStatus.rawValue)")
            guard settings.authorizationStatus == .notDetermined else {
                debugNotification("permission request skipped (already determined)")
                return
            }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    Self.logger.error("notification permission request failed: \(error.localizedDescription, privacy: .public)")
                    debugNotification("permission request failed: \(error.localizedDescription)")
                } else {
                    Self.logger.info("notification permission granted: \(granted, privacy: .public)")
                    debugNotification("permission request result granted=\(granted)")
                }
            }
        }
    }

    private func notifyDownloadCompletionIfNeeded(fileURL: URL) {
        guard notificationsEnabled else {
            debugNotification("completion notification skipped (disabled)")
            return
        }
        scheduleCompletionNotificationIfNeeded(fileURL: fileURL, attempt: 1)
    }

    private func scheduleCompletionNotificationIfNeeded(fileURL: URL, attempt: Int) {
        let appState = UIApplication.shared.applicationState
        debugNotification("completion check attempt=\(attempt) scenePhase=\(String(describing: scenePhase)) appState=\(appState.rawValue)")
        if appState == .active {
            if attempt == 1 {
                debugNotification("app still active, retrying notification check shortly")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    scheduleCompletionNotificationIfNeeded(fileURL: fileURL, attempt: 2)
                }
            } else {
                debugNotification("completion notification skipped (user in app)")
            }
            return
        }

        debugNotification("scheduling notification file=\(fileURL.lastPathComponent)")

        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = fileURL.lastPathComponent
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "palladium-download-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("failed to schedule completion notification: \(error.localizedDescription, privacy: .public)")
                debugNotification("schedule failed: \(error.localizedDescription)")
            } else {
                debugNotification("schedule success id=\(request.identifier)")
            }
        }
    }

    private func debugNotification(_ message: String) {
        let line = "[notify] \(message)"
        Self.logger.info("\(line, privacy: .public)")
        print(line)
        Task { @MainActor in
            appendConsoleText("\(line)\n")
        }
    }

    private func buildPresetArgumentsJSON() -> String {
        let payload: [String: String] = [
            "custom": customArgsText
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func makeCancelMarkerURL() -> URL? {
        if let downloadsPath = ProcessInfo.processInfo.environment["PALLADIUM_DOWNLOADS"], !downloadsPath.isEmpty {
            return URL(fileURLWithPath: downloadsPath).appendingPathComponent(".palladium-cancel-\(UUID().uuidString)")
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(".palladium-cancel-\(UUID().uuidString)")
    }

    private func clearDownloadsDirectoryContents() throws -> Int {
        let downloadsURL: URL
        if let downloadsPath = ProcessInfo.processInfo.environment["PALLADIUM_DOWNLOADS"], !downloadsPath.isEmpty {
            downloadsURL = URL(fileURLWithPath: downloadsPath, isDirectory: true)
        } else {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            downloadsURL = documents.appendingPathComponent("Downloads", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: nil
        )

        var removed = 0
        for item in contents {
            try FileManager.default.removeItem(at: item)
            removed += 1
        }
        return removed
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
