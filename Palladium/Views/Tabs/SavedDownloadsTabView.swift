import SwiftUI

struct SavedDownloadsTabView: View {
    let savedDirectory: URL
    let onSelectMedia: (SavedDownloadItem) -> Void

    @State private var items: [SavedDownloadItem] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        String(localized: "downloads.error.title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "downloads.empty.title"),
                        systemImage: "tray",
                        description: Text("downloads.empty.message")
                    )
                } else {
                    List(items) { item in
                        SavedDownloadRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !item.isFolder else { return }
                                onSelectMedia(item)
                            }
                            .background {
                                if item.isFolder {
                                    NavigationLink(value: item) {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                }
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("tab.downloads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadItems) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("downloads.refresh")
                }
            }
            .navigationDestination(for: SavedDownloadItem.self) { item in
                SavedDownloadsFolderView(folder: item, onSelectMedia: onSelectMedia)
            }
        }
        .onAppear(perform: loadItems)
    }

    private func loadItems() {
        do {
            items = try SavedDownloadScanner.topLevelItems(in: savedDirectory)
            loadError = nil
        } catch {
            items = []
            loadError = error.localizedDescription
        }
    }
}

private struct SavedDownloadsFolderView: View {
    let folder: SavedDownloadItem
    let onSelectMedia: (SavedDownloadItem) -> Void

    @State private var items: [SavedDownloadItem] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    String(localized: "downloads.error.title"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "downloads.folder.empty.title"),
                    systemImage: "folder",
                    description: Text("downloads.folder.empty.message")
                )
            } else {
                List(items) { item in
                    SavedDownloadRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectMedia(item)
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(folder.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: loadItems) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("downloads.refresh")
            }
        }
        .onAppear(perform: loadItems)
    }

    private func loadItems() {
        do {
            items = try SavedDownloadScanner.mediaItems(in: folder.url)
            loadError = nil
        } catch {
            items = []
            loadError = error.localizedDescription
        }
    }
}

private struct SavedDownloadRow: View {
    let item: SavedDownloadItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: item.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(item.iconColor)
            }
            .frame(width: 58, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SavedDownloadItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder(mediaCount: Int)
        case video
        case audio
        case image
    }

    let url: URL
    let kind: Kind
    let modifiedDate: Date?
    let fileSize: Int64?

    var id: String { url.path }
    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var subtitle: String {
        switch kind {
        case .folder(let mediaCount):
            return String(format: String(localized: "downloads.folder.count"), mediaCount)
        case .video, .audio, .image:
            var parts: [String] = [mediaTypeTitle]
            if let fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            }
            if let modifiedDate {
                parts.append(modifiedDate.formatted(date: .abbreviated, time: .shortened))
            }
            return parts.joined(separator: " • ")
        }
    }

    var mediaTypeTitle: String {
        switch kind {
        case .folder:
            return String(localized: "downloads.type.folder")
        case .video:
            return String(localized: "downloads.type.video")
        case .audio:
            return String(localized: "downloads.type.audio")
        case .image:
            return String(localized: "downloads.type.image")
        }
    }

    var iconName: String {
        switch kind {
        case .folder:
            return "folder"
        case .video:
            return "play.rectangle"
        case .audio:
            return "music.note"
        case .image:
            return "photo"
        }
    }

    var iconColor: Color {
        switch kind {
        case .folder:
            return .orange
        case .video:
            return .blue
        case .audio:
            return .purple
        case .image:
            return .green
        }
    }
}

enum SavedDownloadScanner {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "flv", "ts", "mpeg", "mpg"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "opus", "ogg"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heif", "heic", "webp"]

    static func topLevelItems(in directory: URL) throws -> [SavedDownloadItem] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return try contents.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
            if values.isDirectory == true {
                let mediaCount = try mediaItems(in: url).count
                guard mediaCount > 0 else { return nil }
                return SavedDownloadItem(
                    url: url,
                    kind: .folder(mediaCount: mediaCount),
                    modifiedDate: values.contentModificationDate,
                    fileSize: nil
                )
            }
            guard let kind = mediaKind(for: url) else { return nil }
            return SavedDownloadItem(
                url: url,
                kind: kind,
                modifiedDate: values.contentModificationDate,
                fileSize: Int64(values.fileSize ?? 0)
            )
        }
        .sorted(by: sortItems)
    }

    static func mediaItems(in directory: URL) throws -> [SavedDownloadItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [SavedDownloadItem] = []
        for case let url as URL in enumerator {
            guard let kind = mediaKind(for: url) else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            items.append(
                SavedDownloadItem(
                    url: url,
                    kind: kind,
                    modifiedDate: values.contentModificationDate,
                    fileSize: Int64(values.fileSize ?? 0)
                )
            )
        }
        return items.sorted(by: sortItems)
    }

    private static func mediaKind(for url: URL) -> SavedDownloadItem.Kind? {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
        return nil
    }

    private static func sortItems(_ lhs: SavedDownloadItem, _ rhs: SavedDownloadItem) -> Bool {
        switch (lhs.isFolder, rhs.isFolder) {
        case (true, false):
            return true
        case (false, true):
            return false
        default:
            break
        }

        let lhsDate = lhs.modifiedDate ?? .distantPast
        let rhsDate = rhs.modifiedDate ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}
