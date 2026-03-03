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

struct ContentView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium",
        category: "python"
    )

    private static let presetDefaultsKey = "palladium.selectedPreset"
    private static let settingsDefaultsKey = "palladium.downloadSettings"

    @State private var isRunning = false
    @State private var statusText = "idle"
    @State private var urlText: String
    @State private var progressText = "Enter a URL and tap Download."
    @State private var selectedPreset: DownloadPreset
    @State private var downloadSettings: DownloadSettings
    @State private var packageStatusText = "idle"
    @State private var versionsText = "yt-dlp: unknown\nyt-dlp-apple-webkit-jsi: unknown"
    @State private var consoleLogText = ""
    @State private var completedDownloadURL: URL?
    @State private var showDownloadActionDialog = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var shareItem: ShareItem?

    init() {
        #if DEBUG
        _urlText = State(initialValue: "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        #else
        _urlText = State(initialValue: "")
        #endif
        _selectedPreset = State(initialValue: Self.loadSelectedPreset())
        _downloadSettings = State(initialValue: Self.loadDownloadSettings())
    }

    var body: some View {
        TabView {
            DownloadTabView(
                statusText: $statusText,
                urlText: $urlText,
                selectedPreset: $selectedPreset,
                isRunning: isRunning,
                progressText: progressText,
                onDownload: runDownloadFlow
            )
            .tabItem {
                Label("Download", systemImage: "arrow.down.circle")
            }

            PackagesTabView(
                packageStatusText: packageStatusText,
                versionsText: versionsText,
                isRunning: isRunning,
                onRefreshVersions: refreshPackageVersions,
                onUpdatePackages: updatePackages
            )
            .tabItem {
                Label("Packages", systemImage: "shippingbox")
            }

            SettingsTabView(settings: $downloadSettings, isRunning: isRunning)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }

            ConsoleTabView(consoleLogText: $consoleLogText)
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }
        }
        .onChange(of: selectedPreset) { _ in
            persistPreferences()
        }
        .onChange(of: downloadSettings) { _ in
            persistPreferences()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .confirmationDialog("Download Complete", isPresented: $showDownloadActionDialog, titleVisibility: .visible) {
            if completedDownloadURL != nil {
                Button("Share") {
                    if let url = completedDownloadURL {
                        shareItem = ShareItem(url: url)
                    }
                }
                Button("Save to Photos") {
                    if let url = completedDownloadURL {
                        saveDownloadedFileToPhotos(url)
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

        isRunning = true
        statusText = "running"
        progressText = "Downloading..."

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        let presetAtStart = selectedPreset.pythonValue
        let settingsAtStart = downloadSettings.jsonString
        setenv("PALLADIUM_LOG_FD", "\(writeFD)", 1)

        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                consoleLogText.append(chunk)
                updateProgress(from: chunk)
            }
        }

        Task {
            let outcome = await PythonFlowRunner.executeDownloadFlow(
                url: targetURL,
                preset: presetAtStart,
                settingsJSON: settingsAtStart
            )

            unsetenv("PALLADIUM_LOG_FD")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()

            isRunning = false
            statusText = outcome.statusText
            progressText = outcome.statusText == "success" ? "download complete" : "download failed"
            let outputBody = outcome.outputText
            consoleLogText += "\n\(outcome.summaryText)\n\n\(outputBody)\n"
            Self.logger.info("yt-dlp flow finished with status: \(outcome.statusText, privacy: .public)")
            Self.logger.info("\(consoleLogText, privacy: .public)")
            print(consoleLogText)

            if outcome.statusText == "success",
               let downloadedPath = outcome.downloadedPath,
               FileManager.default.fileExists(atPath: downloadedPath) {
                completedDownloadURL = URL(fileURLWithPath: downloadedPath)
                showDownloadActionDialog = true
            }
        }
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
                consoleLogText.append(chunk)
            }
        }

        Task {
            let outcome = await PythonFlowRunner.executePackageFlow(action: action)

            unsetenv("PALLADIUM_LOG_FD")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()

            isRunning = false
            packageStatusText = outcome.statusText
            let outputBody = outcome.outputText
            consoleLogText += "\n\(outcome.summaryText)\n\n\(outputBody)\n"
            if let versionsText = outcome.versionsText {
                self.versionsText = versionsText
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
        if let data = try? JSONEncoder().encode(downloadSettings) {
            defaults.set(data, forKey: Self.settingsDefaultsKey)
        }
    }

    private static func loadSelectedPreset() -> DownloadPreset {
        guard let rawValue = UserDefaults.standard.string(forKey: presetDefaultsKey),
              let preset = DownloadPreset(rawValue: rawValue) else {
            return .autoVideo
        }
        return preset
    }

    private static func loadDownloadSettings() -> DownloadSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsDefaultsKey),
              let settings = try? JSONDecoder().decode(DownloadSettings.self, from: data) else {
            return DownloadSettings()
        }
        return settings
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
