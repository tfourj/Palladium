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

            Button(action: runDownloadFlow) {
                Text(isRunning ? "Running..." : "Download")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

    private func runDownloadFlow() {
        guard !isRunning else { return }
        let targetURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else { return }

        isRunning = true
        statusText = "running"
        progressText = "starting..."

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        setenv("PALLADIUM_LOG_FD", "\(writeFD)", 1)
        setenv("PALLADIUM_DOWNLOAD_URL", targetURL, 1)

        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                consoleLogText.append(chunk)
                updateProgress(from: chunk)
            }
        }

        Task {
            let outcome = await PythonFlowRunner.executeDownloadFlow()

            unsetenv("PALLADIUM_LOG_FD")
            unsetenv("PALLADIUM_DOWNLOAD_URL")
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
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            if line.hasPrefix("[download]") {
                progressText = line
            } else if line.contains("[palladium] downloaded file:") {
                progressText = "download complete"
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
