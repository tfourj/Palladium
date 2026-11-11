import Foundation

/// A yt-dlp plugin archive or folder stored in the app's plugin folder.
nonisolated struct YTDLPPlugin: Identifiable, Equatable, Hashable {
    /// Plugin types yt-dlp loads from the `yt_dlp_plugins` namespace package.
    enum Kind: String, CaseIterable {
        case extractor
        case postprocessor

        var localizedName: String {
            switch self {
            case .extractor:
                return String(localized: "plugins.kind.extractor", bundle: .app)
            case .postprocessor:
                return String(localized: "plugins.kind.postprocessor", bundle: .app)
            }
        }
    }

    let fileName: String
    let fileURL: URL
    let isFolder: Bool
    let kinds: [Kind]
    let modifiedAt: Date
    let sizeBytes: Int64

    var id: String { fileName }

    var isRecognized: Bool { !kinds.isEmpty }

    var displayName: String {
        guard !isFolder else { return fileName }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? fileName : stem
    }
}
