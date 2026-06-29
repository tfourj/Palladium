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

    func runPackageFlow(
        action: String,
        customVersions: [String: String]? = nil,
        updateWhenAvailable: Bool = false,
        isAutomaticUpdate: Bool = false
    ) {
        guard !isRunning, !isPackageRunning, !isCheckingDownloadAllowlist, !isResolvingGallery else { return }

        isPackageRunning = true
        isAutomaticallyUpdatingPackages = isAutomaticUpdate
        syncIdleTimerDisabled()
        switch action {
        case "update", "reinstall":
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
        let liveLogFD: Int32? = writeFD
        let liveLogDecoder = StreamingUTF8Decoder()
        let cancelMarker = makeCancelMarkerURL()
        cancelMarkerURL = cancelMarker
        FFmpegBridgeControl.setLiveLogFD(liveLogFD)
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
            let outcome = await PythonFlowRunner.executePackageFlow(
                action: action,
                customVersions: customVersions,
                packageSourceJSON: buildPackageSourceJSON(),
                liveLogFD: liveLogFD
            )

            FFmpegBridgeControl.setLiveLogFD(nil)
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
            isAutomaticallyUpdatingPackages = false
            syncIdleTimerDisabled()
            isLoadingPackageVersions = false
            packageStatusText = outcome.statusText
            appendConsoleText("\n\(outcome.summaryText)\n")
            if let versionsText = outcome.versionsText {
                self.versionsText = versionsText
                persistPackageVersionsText(versionsText)
            }
            if let runtimePackagesMissing = outcome.runtimePackagesMissing {
                self.runtimePackagesMissing = runtimePackagesMissing
            }
            let updatesAvailable = outcome.updatesAvailable ?? false
            if outcome.updatesAvailable != nil {
                self.packageUpdatesAvailable = updatesAvailable
                self.packageUpdatesAvailable = updatesAvailable
            }
            if let updatesSummary = outcome.updatesSummary {
                self.packageUpdatesSummaryText = updatesSummary
            }
            if let availableVersions = outcome.availableVersions {
                self.availablePackageVersions = availableVersions
            }
            if outcome.restartRequired {
                alertMessage = String(localized: "settings.advanced.restart_required")
                showAlert = true
            }
            self.hasLoadedPackageStatus = true
            Self.logger.info("package flow finished with status: \(outcome.statusText, privacy: .public)")

            if action == "check", updateWhenAvailable, updatesAvailable {
                guard !isRunning, !isCheckingDownloadAllowlist, !isResolvingGallery else {
                    appendConsoleText("[palladium] automatic package update skipped because a download is starting\n")
                    return
                }
                runPackageFlow(action: "update", isAutomaticUpdate: true)
            }


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
        if packageSourceMode == .custom && customPackageSpecs().isEmpty {
            alertMessage = String(localized: "packages.source.custom_specs.empty")
            showAlert = true
            return
        }
        runPackageFlow(action: "update")
    }

    func reinstallPackages() {
        if packageSourceMode == .custom && customPackageSpecs().isEmpty {
            alertMessage = String(localized: "packages.source.custom_specs.empty")
            showAlert = true
            return
        }
        runPackageFlow(action: "reinstall")
    }

    func updatePackagesWithCustomVersions(
        _ ytDlpVersion: String?,
        _ webkitJSIVersion: String?,
        _ curlCFFIVersion: String?,
        _ galleryDLVersion: String?,
        _ pipVersion: String?
    ) {
        guard packageSourceMode != .custom else { return }
        var customVersions: [String: String] = [:]
        if let ytDlpVersion {
            customVersions["yt-dlp"] = ytDlpVersion
        }
        if let webkitJSIVersion {
            customVersions["yt-dlp-apple-webkit-jsi"] = webkitJSIVersion
        }
        if let curlCFFIVersion {
            customVersions["curl-cffi"] = curlCFFIVersion
        }
        if let galleryDLVersion {
            customVersions["gallery-dl"] = galleryDLVersion
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

    func buildPackageSourceJSON() -> String {
        let specs = customPackageSpecs()
        let payload: [String: Any] = [
            "mode": packageSourceMode.rawValue,
            "custom_specs": specs,
            "disable_webkit_jsi_patch": disableWebKitJSIPatch
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"mode\":\"stable\",\"custom_specs\":[]}"
        }
        return text
    }

    func customPackageSpecs() -> [String] {
        customPackageSpecsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
