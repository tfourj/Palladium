import Foundation
import Observation

/// Where "Save to App Folder" copies land: Documents/Saved by default, or a Palladium
/// folder inside a folder picked in Files (for example iCloud Drive).
@Observable
final class SavedDownloadLocationStore {
    enum State: Equatable {
        case appFolder
        case custom(folderName: String)
        case unavailable(folderName: String)
    }

    static let shared = SavedDownloadLocationStore()
    static let bookmarkKey = "palladium.savedDownloads.locationBookmark"
    static let folderNameKey = "palladium.savedDownloads.locationName"
    static let customSubfolderName = "Palladium"

    private(set) var state: State = .appFolder
    private(set) var directoryURL: URL

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let appFolderURL: URL
    @ObservationIgnored private var accessedFolderURL: URL?

    init(defaults: UserDefaults = .standard, appFolderURL: URL? = nil) {
        let resolvedAppFolderURL = appFolderURL ?? Self.defaultAppFolderURL()
        self.defaults = defaults
        self.appFolderURL = resolvedAppFolderURL
        self.directoryURL = resolvedAppFolderURL
        reload()
    }

    var isCustom: Bool {
        state != .appFolder
    }

    /// Short path shown in storage settings, such as "Documents/Saved" or "iCloud Folder/Palladium".
    var displayPath: String {
        switch state {
        case .appFolder, .unavailable:
            return "Documents/Saved"
        case .custom(let folderName):
            return "\(folderName)/\(Self.customSubfolderName)"
        }
    }

    /// Saves a bookmark to a folder picked with the Files picker and starts saving into it.
    func useFolder(_ pickedURL: URL) throws {
        let bookmark = try makeBookmark(for: pickedURL)
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(pickedURL.lastPathComponent, forKey: Self.folderNameKey)
        reload()
        if case .unavailable = state {
            resetToAppFolder()
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    func resetToAppFolder() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.folderNameKey)
        reload()
    }

    /// Retries a chosen folder that could not be reached, for example after iCloud comes back.
    func reloadIfUnavailable() {
        if case .unavailable = state {
            reload()
        }
    }

    func reload() {
        stopAccessingFolder()
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else {
            state = .appFolder
            directoryURL = appFolderURL
            return
        }

        let folderName = defaults.string(forKey: Self.folderNameKey) ?? Self.customSubfolderName
        do {
            var isStale = false
            let folderURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if folderURL.startAccessingSecurityScopedResource() {
                accessedFolderURL = folderURL
            }

            let savedURL = folderURL.appendingPathComponent(Self.customSubfolderName, isDirectory: true)
            try FileManager.default.createDirectory(at: savedURL, withIntermediateDirectories: true)
            if isStale, let freshBookmark = try? folderURL.bookmarkData() {
                defaults.set(freshBookmark, forKey: Self.bookmarkKey)
            }
            state = .custom(folderName: folderURL.lastPathComponent)
            directoryURL = savedURL
        } catch {
            stopAccessingFolder()
            state = .unavailable(folderName: folderName)
            directoryURL = appFolderURL
        }
    }

    private func makeBookmark(for pickedURL: URL) throws -> Data {
        let isAccessing = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                pickedURL.stopAccessingSecurityScopedResource()
            }
        }
        let savedURL = pickedURL.appendingPathComponent(Self.customSubfolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: savedURL, withIntermediateDirectories: true)
        return try pickedURL.bookmarkData()
    }

    private func stopAccessingFolder() {
        accessedFolderURL?.stopAccessingSecurityScopedResource()
        accessedFolderURL = nil
    }

    private static func defaultAppFolderURL() -> URL {
        let documents = (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Saved", isDirectory: true)
    }
}
