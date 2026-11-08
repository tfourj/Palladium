//
//  ContentView+LinkPreview.swift
//  Palladium
//

import Foundation

extension ContentView {
    private static let linkPreviewDebounce: Duration = .milliseconds(600)
    private static let linkPreviewCacheLimit = 20

    /// The preview the download tab should show, or nil when previews do not apply.
    /// Kept free of file access because SwiftUI evaluates it on every update.
    var linkPreviewTrigger: LinkPreviewRequest? {
        guard linkPreviewEnabled,
              !isRunning,
              !isPackageRunning,
              selectedPreset != .images,
              let url = LinkPreviewPolicy.previewURL(for: urlText) else {
            return nil
        }
        let cookieName = selectedCookieFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkPreviewRequest(
            url: url,
            cookieFileName: useCookies && !cookieName.isEmpty ? cookieName : nil,
            downloadPlaylist: downloadPlaylist,
            preset: selectedPreset,
            extraArgs: extraArgsText
        )
    }

    /// Pairs the text with the request so one change handler sees the previous text.
    var linkPreviewInput: LinkPreviewInput {
        LinkPreviewInput(text: urlText, request: linkPreviewTrigger)
    }

    var linkPreviewIsInHistory: Bool {
        guard linkHistoryEnabled, let url = linkPreviewState?.request.url else { return false }
        return LinkPreviewPolicy.isInHistory(url, entries: linkHistoryEntries)
    }

    func refreshLinkPreview(debounce: Bool) {
        let request = linkPreviewTrigger
        guard request != linkPreviewState?.request || request == nil else { return }

        linkPreviewTask?.cancel()
        linkPreviewTask = nil
        guard let request else {
            linkPreviewState = nil
            return
        }
        // Quality settings are read here rather than in the trigger, which runs on every view update.
        let presetArgsJSON = buildPresetArgumentsJSON()
        if let cached = linkPreviewCache[request], cached.presetArgsJSON == presetArgsJSON {
            linkPreviewState = .loaded(request, cached.preview)
            return
        }

        linkPreviewState = .loading(request)
        linkPreviewTask = Task {
            if debounce {
                try? await Task.sleep(for: Self.linkPreviewDebounce)
            }
            guard !Task.isCancelled, linkPreviewState?.request == request else { return }

            let cookiePath = request.cookieFileName == nil ? nil : resolvedSelectedCookieFilePath()
            let resolution = await PythonFlowRunner.resolveLinkPreview(
                request,
                cookieFilePath: cookiePath,
                presetArgsJSON: presetArgsJSON
            )
            guard linkPreviewState?.request == request else { return }

            linkPreviewTask = nil
            if let preview = resolution.preview {
                if linkPreviewCache.count >= Self.linkPreviewCacheLimit {
                    linkPreviewCache.removeAll()
                }
                linkPreviewCache[request] = CachedLinkPreview(presetArgsJSON: presetArgsJSON, preview: preview)
                linkPreviewState = .loaded(request, preview)
            } else {
                linkPreviewState = .failed(request)
                let reason = resolution.errorMessage ?? "unknown error"
                appendConsoleText("[palladium] link preview failed for \(request.url): \(reason)\n")
            }
        }
    }
}
