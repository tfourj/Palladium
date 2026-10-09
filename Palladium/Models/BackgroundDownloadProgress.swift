import Foundation

/// Combines yt-dlp's per-stream progress lines into one fraction for the system background task UI.
///
/// yt-dlp announces the formats it will download, then reports each stream (and side files such as subtitles)
/// from 0% to 100% separately. Streams are weighted equally in the order they start, so the fraction only moves
/// forward, and side files are ignored.
struct BackgroundDownloadProgress: Equatable {
    private static let formatListMarker = "format(s): "
    private static let destinationPrefix = "[download] Destination: "
    private static let subtitleExtensions: Set<String> = [
        "ass", "dfxp", "json3", "lrc", "sbv", "srt", "srv1", "srv2", "srv3", "ssa", "ttml", "vtt"
    ]

    private(set) var formatIDs: [String] = []
    private(set) var streamIndex = 0
    private(set) var streamFraction: Double = 0
    private(set) var processingFraction: Double?
    private var startedStreamFiles: [String] = []
    private var isTrackingStream = false

    var isProcessing: Bool {
        processingFraction != nil
    }

    var fraction: Double {
        if let processingFraction {
            return processingFraction
        }
        let streamCount = max(formatIDs.count, streamIndex + 1)
        return min((Double(streamIndex) + streamFraction) / Double(streamCount), 1)
    }

    mutating func handleLine(_ line: String) {
        if line.hasPrefix("[info] "), let markerRange = line.range(of: Self.formatListMarker) {
            self = BackgroundDownloadProgress()
            formatIDs = line[markerRange.upperBound...]
                .split(whereSeparator: { $0 == "+" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else if line.hasPrefix(Self.destinationPrefix) {
            beginDestination(String(line.dropFirst(Self.destinationPrefix.count)))
        } else if line.hasPrefix("[download]"), isTrackingStream, let percent = Self.percent(in: line) {
            streamFraction = min(max(percent / 100, 0), 1)
        }
    }

    mutating func updateProcessing(percent: Double) {
        processingFraction = min(max(percent / 100, 0), 1)
    }

    private mutating func beginDestination(_ path: String) {
        let fileName = (path as NSString).lastPathComponent
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        guard !Self.subtitleExtensions.contains(fileExtension) else {
            isTrackingStream = false
            return
        }

        // A retried stream reports the same destination again and keeps its position.
        if let startedIndex = startedStreamFiles.firstIndex(of: fileName) {
            streamIndex = startedIndex
        } else {
            streamIndex = startedStreamFiles.count
            startedStreamFiles.append(fileName)
        }
        isTrackingStream = true
        streamFraction = 0
        processingFraction = nil
    }

    private static func percent(in line: String) -> Double? {
        guard let range = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        return Double(line[range].dropLast())
    }
}
