import Foundation

struct LinkPreview: Equatable, Sendable {
    let title: String
    let uploader: String
    let site: String
    let duration: TimeInterval?
    let thumbnailURL: URL?
    let fileSize: Int64?
    let fileSizeIsApproximate: Bool
    let isPlaylist: Bool
    let entryCount: Int?

    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = totalSeconds % 3600 / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var fileSizeText: String? {
        guard let fileSize, fileSize > 0 else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .binary)
        return fileSizeIsApproximate ? "≈\(size)" : size
    }

    var sourceText: String {
        [uploader, site].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Identifies one preview fetch so stale results can be ignored.
struct LinkPreviewRequest: Hashable, Sendable {
    let url: String
    let cookieFileName: String?
    let downloadPlaylist: Bool
    let preset: DownloadPreset
    let extraArgs: String
}

/// A fetched preview plus the preset quality arguments it was sized with.
struct CachedLinkPreview: Sendable {
    let presetArgsJSON: String
    let preview: LinkPreview
}

struct LinkPreviewInput: Equatable {
    let text: String
    let request: LinkPreviewRequest?
}

enum LinkPreviewState: Equatable {
    case loading(LinkPreviewRequest)
    case loaded(LinkPreviewRequest, LinkPreview)
    case failed(LinkPreviewRequest)

    var request: LinkPreviewRequest {
        switch self {
        case .loading(let request), .loaded(let request, _), .failed(let request):
            return request
        }
    }
}

struct LinkPreviewResolution: Sendable {
    let preview: LinkPreview?
    let outputText: String
    let errorMessage: String?
}

enum LinkPreviewPolicy {
    private static let supportedSchemes: Set<String> = ["http", "https"]

    /// Returns the link to preview when the text is exactly one web link.
    /// Multi-link text is queued instead, so it has no single preview.
    static func previewURL(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme),
              let host = url.host(percentEncoded: false), !host.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Typing changes the text one character at a time, so wait for it to settle.
    /// Pastes, history picks, and option changes fetch right away.
    static func shouldDebounce(from previousText: String, to text: String) -> Bool {
        abs(text.count - previousText.count) == 1
    }

    static func isInHistory(_ url: String, entries: [LinkHistoryEntry]) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return entries.contains { $0.url == trimmed }
    }
}
