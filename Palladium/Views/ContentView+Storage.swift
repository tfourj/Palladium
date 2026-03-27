//
//  ContentView+Storage.swift
//  Palladium
//

import Foundation

extension ContentView {
    func clearDownloadsDirectoryContents() throws -> Int {
        let downloadsURL = try downloadsDirectoryURL()
        return try clearDirectoryContents(at: downloadsURL)
    }

    func refreshStorageSummary() {
        do {
            storageSummary = try buildStorageManagementSummary()
        } catch {
            appendConsoleText("[palladium] failed to refresh storage summary: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.refresh_summary"), error.localizedDescription)
            showAlert = true
        }
    }

    func clearTemporaryDownloadsStorage() {
        guard !isRunning, !isPackageRunning else { return }
        do {
            let removed = try clearDirectoryContents(at: try downloadsDirectoryURL())
            refreshStorageSummary()
            appendConsoleText("[palladium] cleared temporary download entries: \(removed)\n", source: .app)
            showTemporaryToast(removed == 0 ? String(localized: "storage.toast.downloads_empty") : String(localized: "storage.toast.downloads_cleared"))
        } catch {
            appendConsoleText("[palladium] failed to clear temporary downloads: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.clear_downloads"), error.localizedDescription)
            showAlert = true
        }
    }

    func clearYtDlpCacheStorage() {
        guard !isRunning, !isPackageRunning else { return }
        do {
            let removed = try clearDirectoryContents(at: try cacheDirectoryURL())
            refreshStorageSummary()
            appendConsoleText("[palladium] cleared yt-dlp cache entries: \(removed)\n", source: .app)
            showTemporaryToast(removed == 0 ? String(localized: "storage.toast.cache_empty") : String(localized: "storage.toast.cache_cleared"))
        } catch {
            appendConsoleText("[palladium] failed to clear yt-dlp cache: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.clear_cache"), error.localizedDescription)
            showAlert = true
        }
    }

    func clearSavedDownloadsStorage() {
        guard !isRunning, !isPackageRunning else { return }
        do {
            let removed = try clearDirectoryContents(at: try savedDirectoryURL())
            refreshStorageSummary()
            appendConsoleText("[palladium] cleared saved download entries: \(removed)\n", source: .app)
            showTemporaryToast(removed == 0 ? String(localized: "storage.toast.saved_empty") : String(localized: "storage.toast.saved_cleared"))
        } catch {
            appendConsoleText("[palladium] failed to clear saved downloads: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.clear_saved"), error.localizedDescription)
            showAlert = true
        }
    }

    func pruneTemporaryDownloadsStorage(_ window: StoragePruneWindow) {
        guard !isRunning, !isPackageRunning else { return }
        do {
            let removed = try removeDirectoryItems(olderThan: window.cutoffDate, at: try downloadsDirectoryURL())
            refreshStorageSummary()
            appendConsoleText("[palladium] pruned temporary download entries older than \(window.title): \(removed)\n", source: .app)
            showTemporaryToast(
                removed == 0
                    ? String(localized: "storage.toast.nothing")
                    : String(format: String(localized: "storage.toast.removed_old_items"), removed)
            )
        } catch {
            appendConsoleText("[palladium] failed to prune temporary downloads: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.prune_downloads"), error.localizedDescription)
            showAlert = true
        }
    }

    func pruneYtDlpCacheStorage(_ window: StoragePruneWindow) {
        guard !isRunning, !isPackageRunning else { return }
        do {
            let removed = try removeDirectoryItems(olderThan: window.cutoffDate, at: try cacheDirectoryURL())
            refreshStorageSummary()
            appendConsoleText("[palladium] pruned cache entries older than \(window.title): \(removed)\n", source: .app)
            showTemporaryToast(
                removed == 0
                    ? String(localized: "storage.toast.nothing")
                    : String(format: String(localized: "storage.toast.removed_old_items"), removed)
            )
        } catch {
            appendConsoleText("[palladium] failed to prune yt-dlp cache: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.prune_cache"), error.localizedDescription)
            showAlert = true
        }
    }

    func pruneSavedDownloadsStorage(_ window: StoragePruneWindow) {
        guard !isRunning, !isPackageRunning else { return }
        do {
            let removed = try removeDirectoryItems(olderThan: window.cutoffDate, at: try savedDirectoryURL())
            refreshStorageSummary()
            appendConsoleText("[palladium] pruned saved download entries older than \(window.title): \(removed)\n", source: .app)
            showTemporaryToast(
                removed == 0
                    ? String(localized: "storage.toast.nothing")
                    : String(format: String(localized: "storage.toast.removed_old_items"), removed)
            )
        } catch {
            appendConsoleText("[palladium] failed to prune saved downloads: \(error.localizedDescription)\n", source: .app)
            alertMessage = String(format: String(localized: "storage.error.prune_saved"), error.localizedDescription)
            showAlert = true
        }
    }

    func buildStorageManagementSummary() throws -> StorageManagementSummary {
        StorageManagementSummary(
            downloads: try summarizeDirectory(at: try downloadsDirectoryURL(), locationLabel: String(localized: "storage.path.temp")),
            saved: try summarizeDirectory(at: try savedDirectoryURL(), locationLabel: String(localized: "storage.path.saved")),
            cache: try summarizeDirectory(at: try cacheDirectoryURL(), locationLabel: String(localized: "storage.path.cache"))
        )
    }

    func summarizeDirectory(at directoryURL: URL, locationLabel: String) throws -> StorageLocationSummary {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return StorageLocationSummary(
            locationLabel: locationLabel,
            itemCount: contents.count,
            totalBytes: directoryAllocatedSize(at: directoryURL)
        )
    }

    func directoryAllocatedSize(at directoryURL: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            total += Int64(resourceValues.fileSize ?? 0)
        }
        return total
    }

    func clearDirectoryContents(at directoryURL: URL) throws -> Int {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        var removed = 0
        for item in contents {
            try FileManager.default.removeItem(at: item)
            removed += 1
        }
        return removed
    }

    func removeDirectoryItems(olderThan cutoffDate: Date, at directoryURL: URL) throws -> Int {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        var removed = 0
        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let referenceDate = resourceValues?.contentModificationDate ?? resourceValues?.creationDate ?? .distantFuture
            if referenceDate < cutoffDate {
                try FileManager.default.removeItem(at: item)
                removed += 1
            }
        }
        return removed
    }

    func downloadsDirectoryURL() throws -> URL {
        if let downloadsPath = ProcessInfo.processInfo.environment["PALLADIUM_DOWNLOADS"], !downloadsPath.isEmpty {
            return URL(fileURLWithPath: downloadsPath, isDirectory: true)
        }
        return try documentsDirectoryURL().appendingPathComponent("Temp", isDirectory: true)
    }

    func savedDirectoryURL() throws -> URL {
        try documentsDirectoryURL().appendingPathComponent("Saved", isDirectory: true)
    }

    func cacheDirectoryURL() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("yt-dlp", isDirectory: true)
    }

    func documentsDirectoryURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

}
