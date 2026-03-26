//
//  ContentView+History.swift
//  Palladium
//

import UIKit

extension ContentView {
    func handleHistoryEntrySelection(_ entry: LinkHistoryEntry) {
        selectedTab = .download
        urlText = entry.url
        selectedPreset = entry.preset
    }

    func removeHistoryEntry(_ entry: LinkHistoryEntry) {
        linkHistoryEntries.removeAll { $0.id == entry.id }
        persistLinkHistoryEntries()
    }

    func copyHistoryLink(_ url: String) {
        UIPasteboard.general.string = url
        appendConsoleText("[palladium] copied history link\n")
    }

    func addLinkHistoryEntry(
        url: String,
        presetRawValue: String,
        downloadedPaths: [String],
        primaryDownloadedPath: String?,
        outputText: String
    ) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let title = extractHistoryTitle(
            downloadedPaths: downloadedPaths,
            primaryDownloadedPath: primaryDownloadedPath,
            outputText: outputText
        )
        let entry = LinkHistoryEntry(
            id: UUID(),
            url: trimmedURL,
            presetRawValue: presetRawValue,
            title: title,
            timestamp: Date()
        )

        linkHistoryEntries.removeAll { $0.url == entry.url && $0.presetRawValue == entry.presetRawValue }
        linkHistoryEntries.insert(entry, at: 0)
        trimLinkHistoryEntriesIfNeeded()
        persistLinkHistoryEntries()
    }

    func trimLinkHistoryEntriesIfNeeded() {
        let maxEntries = max(0, min(linkHistoryLimit, Self.maxLinkHistoryLimit))
        if linkHistoryEntries.count > maxEntries {
            linkHistoryEntries = Array(linkHistoryEntries.prefix(maxEntries))
        }
    }

    func extractHistoryTitle(
        downloadedPaths: [String],
        primaryDownloadedPath: String?,
        outputText: String
    ) -> String? {
        if let playlistTitle = outputText.components(separatedBy: .newlines)
            .compactMap({ line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[download] Downloading playlist: ") {
                    return trimmed.replacingOccurrences(of: "[download] Downloading playlist: ", with: "")
                }
                if trimmed.hasPrefix("[youtube:tab] Downloading playlist ") {
                    return trimmed.replacingOccurrences(of: "[youtube:tab] Downloading playlist ", with: "")
                }
                return nil
            })
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !playlistTitle.isEmpty {
            return playlistTitle
        }

        if let destinationMatch = outputText.components(separatedBy: .newlines)
            .reversed()
            .first(where: { $0.hasPrefix("[download] Destination: ") }) {
            let pathText = destinationMatch.replacingOccurrences(of: "[download] Destination: ", with: "")
            if let parsed = normalizedHistoryTitle(fromPath: pathText) {
                return parsed
            }
        }

        if let primaryDownloadedPath,
           let title = normalizedHistoryTitle(fromPath: primaryDownloadedPath) {
            return title
        }

        return downloadedPaths.lazy.compactMap(normalizedHistoryTitle(fromPath:)).first
    }

    func persistLinkHistoryEntries() {
        let defaults = UserDefaults.standard
        guard let data = try? JSONEncoder().encode(linkHistoryEntries) else { return }
        defaults.set(data, forKey: Self.linkHistoryEntriesDefaultsKey)
    }

    private func normalizedHistoryTitle(fromPath path: String) -> String? {
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !fileName.isEmpty else { return nil }
        let cleaned = fileName.replacingOccurrences(
            of: #"\s\[[^\]]+\]$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
