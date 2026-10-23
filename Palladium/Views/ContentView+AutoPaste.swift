//
//  ContentView+AutoPaste.swift
//  Palladium
//

import SwiftUI
import UIKit

extension ContentView {
    var canStartAutoPasteDownload: Bool {
        !isRunning
            && pendingSharedDownloadURL.isEmpty
            && !showShareSheetDownloadPicker
            && !showDownloadActionSheet
            && completedDownloadResult == nil
            && sharePayload == nil
            && !showGalleryPicker
            && !showFormatPicker
            && !isResolvingGallery
            && !isResolvingFormats
    }

    // Copies made inside Palladium should not trigger a download when the app becomes active again.
    func rememberClipboardChangeCount() {
        UserDefaults.standard.set(UIPasteboard.general.changeCount, forKey: Self.autoPasteLastChangeCountDefaultsKey)
    }

    func checkClipboardForAutoPasteLink() {
        guard autoPasteLinkEnabled else { return }

        let pasteboard = UIPasteboard.general
        let defaults = UserDefaults.standard
        let changeCount = pasteboard.changeCount
        if defaults.object(forKey: Self.autoPasteLastChangeCountDefaultsKey) != nil,
           defaults.integer(forKey: Self.autoPasteLastChangeCountDefaultsKey) == changeCount {
            return
        }
        defaults.set(changeCount, forKey: Self.autoPasteLastChangeCountDefaultsKey)
        guard pasteboard.hasStrings || pasteboard.hasURLs else { return }

        // Pattern detection does not trigger the paste permission prompt, so only read likely links.
        Task { @MainActor in
            guard let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
                  patterns.contains(\UIPasteboard.DetectedValues.probableWebURL) else {
                return
            }
            let clipboardText = pasteboard.string ?? pasteboard.url?.absoluteString
            guard let link = ClipboardLinkDetector.firstLink(in: clipboardText) else { return }
            handleAutoPasteLink(link)
        }
    }

    func handleAutoPasteLink(_ link: String) {
        guard autoPasteLinkEnabled else { return }
        guard canStartAutoPasteDownload else {
            appendConsoleText("[palladium] auto paste link skipped while another task is active\n")
            return
        }
        appendConsoleText("[palladium] auto paste link detected: \(link)\n")
        routeExternalLink(link, mode: autoPasteDownloadMode)
    }
}
