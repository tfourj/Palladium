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

struct ContentView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium",
        category: "python"
    )

    @State private var isRunning = false
    @State private var statusText = "idle"
    @State private var urlText = {
        #if DEBUG
        return "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        #else
        return ""
        #endif
    }()
    @State private var progressText = "Enter a URL and tap Download."
    @State private var selectedPreset: DownloadPreset = .autoVideo
    @State private var downloadSettings = DownloadSettings()
    @State private var packageStatusText = "idle"
    @State private var versionsText = "yt-dlp: unknown\nyt-dlp-apple-webkit-jsi: unknown"
    @State private var consoleLogText = ""
    @State private var completedDownloadURL: URL?
    @State private var showDownloadActionDialog = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var shareItem: ShareItem?

    var body: some View {
        TabView {
            downloadTab
                .tabItem {
                    Label("Download", systemImage: "arrow.down.circle")
                }

            packagesTab
                .tabItem {
                    Label("Packages", systemImage: "shippingbox")
                }

            settingsTab
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }

            consoleTab
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }
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

    private var downloadTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yt-dlp downloader")
                .font(.title2.bold())

            Text("status: \(statusText)")
                .font(.subheadline.monospaced())

            TextField("https://example.com/video", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                presetButton(.autoVideo, title: "Auto (Video)")
                presetButton(.mute, title: "Mute")
                presetButton(.audio, title: "Audio")
            }

            Button(action: runDownloadFlow) {
                Text(isRunning ? "Running..." : "Download")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Downloading...")
                        .font(.footnote)
                }
            }

            Text(progressText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var packagesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("package manager")
                .font(.title2.bold())

            Text("status: \(packageStatusText)")
                .font(.subheadline.monospaced())

            Text(versionsText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(action: refreshPackageVersions) {
                    Text(isRunning ? "Running..." : "Refresh Versions")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button(action: updatePackages) {
                    Text(isRunning ? "Running..." : "Update Packages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var consoleTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("console")
                    .font(.title2.bold())
                Spacer()
                Button("Clear") {
                    consoleLogText = ""
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(consoleLogText.isEmpty ? "No logs yet." : consoleLogText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }

    private var settingsTab: some View {
        Form {
            Section("Export") {
                Picker("Container", selection: $downloadSettings.container) {
                    ForEach(DownloadContainer.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)

                Picker("Max resolution", selection: $downloadSettings.maxResolution) {
                    ForEach(DownloadMaxResolution.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)

                Picker("Audio format", selection: $downloadSettings.audioFormat) {
                    ForEach(AudioFormatOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)
            }

            Section("Behavior") {
                Toggle("Single video only (--no-playlist)", isOn: $downloadSettings.noPlaylist)
                    .disabled(isRunning)
                Toggle("Embed subtitles when available", isOn: $downloadSettings.embedSubtitles)
                    .disabled(isRunning)
            }
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
                    alertMessage = "Saved to Photos."
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

    private func presetButton(_ preset: DownloadPreset, title: String) -> some View {
        Button(title) {
            selectedPreset = preset
        }
        .buttonStyle(.borderedProminent)
        .tint(selectedPreset == preset ? .blue : .gray)
        .frame(maxWidth: .infinity)
        .disabled(isRunning)
    }
}

private enum DownloadPreset: String {
    case autoVideo = "auto_video"
    case mute = "mute"
    case audio = "audio"

    var pythonValue: String { rawValue }
}

private struct DownloadSettings: Codable {
    var container: DownloadContainer = .automatic
    var maxResolution: DownloadMaxResolution = .source
    var audioFormat: AudioFormatOption = .automatic
    var noPlaylist: Bool = true
    var embedSubtitles: Bool = false

    var jsonString: String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

private enum DownloadContainer: String, Codable, CaseIterable, Identifiable {
    case automatic
    case mp4
    case webm

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .mp4: return "MP4"
        case .webm: return "WEBM"
        }
    }
}

private enum DownloadMaxResolution: String, Codable, CaseIterable, Identifiable {
    case source
    case p2160
    case p1440
    case p1080
    case p720
    case p480
    case p360

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .p2160: return "2160p"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
}

private enum AudioFormatOption: String, Codable, CaseIterable, Identifiable {
    case automatic
    case m4a
    case mp3
    case opus

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .m4a: return "M4A"
        case .mp3: return "MP3"
        case .opus: return "OPUS"
        }
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
