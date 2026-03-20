//
//  ContentView+Packages.swift
//  Palladium
//

import Foundation
import OSLog

extension ContentView {
    func cancelPackageFlow() {
        guard isPackageRunning else { return }
        requestActiveOperationCancellation()
        currentPackageTask?.cancel()
    }

    func runPackageFlow(action: String, customVersions: [String: String]? = nil) {
        guard !isRunning, !isPackageRunning else { return }

        isPackageRunning = true
        switch action {
        case "update":
            packageStatusText = "updating"
        case "index_versions":
            packageStatusText = "indexing"
            isLoadingPackageVersions = true
        default:
            packageStatusText = "checking"
        }

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
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
            Task { @MainActor in
                enqueueConsoleChunk(chunk, trackProgress: false)
            }
        }

        let task = Task {
            let outcome = await PythonFlowRunner.executePackageFlow(action: action, customVersions: customVersions)

            unsetenv("PALLADIUM_LOG_FD")
            unsetenv("PALLADIUM_CANCEL_FILE")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()
            let trailingChunk = liveLogDecoder.finish()
            await MainActor.run {
                if !trailingChunk.isEmpty {
                    enqueueConsoleChunk(trailingChunk, trackProgress: false)
                }
                flushConsoleChunks()
            }
            if let cancelMarkerURL {
                try? FileManager.default.removeItem(at: cancelMarkerURL)
            }
            self.cancelMarkerURL = nil
            self.currentPackageTask = nil

            isPackageRunning = false
            isLoadingPackageVersions = false
            packageStatusText = outcome.statusText
            appendConsoleText("\n\(outcome.summaryText)\n")
            if let versionsText = outcome.versionsText {
                self.versionsText = versionsText
                persistPackageVersionsText(versionsText)
            }
            if let updatesAvailable = outcome.updatesAvailable {
                self.packageUpdatesAvailable = updatesAvailable
            }
            if let updatesSummary = outcome.updatesSummary {
                self.packageUpdatesSummaryText = updatesSummary
            }
            if let availableVersions = outcome.availableVersions {
                self.availablePackageVersions = availableVersions
            }
            self.hasLoadedPackageStatus = true
            Self.logger.info("package flow finished with status: \(outcome.statusText, privacy: .public)")
        }
        currentPackageTask = task
    }

    func refreshPackageVersions() {
        runPackageFlow(action: "check")
    }

    func loadPackageStatusIfNeeded() {
        guard !hasLoadedPackageStatus else { return }
        runPackageFlow(action: "check")
    }

    func updatePackages() {
        runPackageFlow(action: "update")
    }

    func updatePackagesWithCustomVersions(_ ytDlpVersion: String?, _ webkitJSIVersion: String?, _ pipVersion: String?) {
        var customVersions: [String: String] = [:]
        if let ytDlpVersion {
            customVersions["yt-dlp"] = ytDlpVersion
        }
        if let webkitJSIVersion {
            customVersions["yt-dlp-apple-webkit-jsi"] = webkitJSIVersion
        }
        if let pipVersion {
            customVersions["pip"] = pipVersion
        }
        guard !customVersions.isEmpty else { return }
        runPackageFlow(action: "update", customVersions: customVersions)
    }

    func fetchPackageIndexVersions() {
        runPackageFlow(action: "index_versions")
    }

    func persistPackageVersionsText(_ text: String) {
        UserDefaults.standard.set(text, forKey: Self.packageVersionsTextDefaultsKey)
    }
}
