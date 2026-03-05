import Foundation
import Combine

enum ConsoleLogFilter: String, CaseIterable, Identifiable {
    case all
    case app
    case ffmpeg
    case download

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .app: return "App"
        case .ffmpeg: return "FFmpeg"
        case .download: return "Download"
        }
    }
}

enum ConsoleLogSource: String, Sendable {
    case app
    case ffmpeg
    case download
}

struct ConsoleLogEntry: Identifiable, Sendable {
    let id: Int
    let source: ConsoleLogSource
    let text: String
}

@MainActor
final class ConsoleLogStore: ObservableObject {
    @Published private(set) var entries: [ConsoleLogEntry] = []
    @Published var selectedFilter: ConsoleLogFilter = .all

    let activeLogFileURL: URL

    private let maxEntries: Int
    private let writer: ConsoleLogFileWriter
    private var nextEntryID = 0
    private var pendingPartialLine = ""

    init(maxEntries: Int = 4_000) {
        self.maxEntries = maxEntries

        let logsDirectoryURL = Self.defaultLogsDirectoryURL()
        self.activeLogFileURL = logsDirectoryURL.appendingPathComponent("console.log")
        self.writer = ConsoleLogFileWriter(
            directoryURL: logsDirectoryURL,
            baseFilename: "console.log",
            maxBytesPerFile: 5 * 1024 * 1024,
            maxArchives: 3
        )

        Task {
            await writer.prepare()
        }
    }

    var entryCount: Int {
        entries.count
    }

    var filteredEntries: [ConsoleLogEntry] {
        switch selectedFilter {
        case .all:
            return entries
        case .app:
            return entries.filter { $0.source == .app }
        case .ffmpeg:
            return entries.filter { $0.source == .ffmpeg }
        case .download:
            return entries.filter { $0.source == .download }
        }
    }

    func appendChunk(_ chunk: String, sourceHint: ConsoleLogSource? = nil) {
        guard !chunk.isEmpty else { return }

        Task {
            await writer.append(chunk)
        }

        appendInMemory(chunk, sourceHint: sourceHint)
    }

    func clearAll() {
        entries.removeAll(keepingCapacity: false)
        pendingPartialLine = ""
        nextEntryID = 0

        Task {
            await writer.clearAll()
        }
    }

    private func appendInMemory(_ chunk: String, sourceHint: ConsoleLogSource?) {
        let normalized = chunk
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let combined = pendingPartialLine + normalized
        guard !combined.isEmpty else { return }

        var lines = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hasTrailingNewline = combined.hasSuffix("\n")

        if !hasTrailingNewline, let tail = lines.popLast() {
            pendingPartialLine = tail
        } else {
            pendingPartialLine = ""
        }

        guard !lines.isEmpty else { return }

        var appendedEntries: [ConsoleLogEntry] = []
        appendedEntries.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let source = sourceHint ?? classify(trimmed)
            appendedEntries.append(
                ConsoleLogEntry(id: nextEntryID, source: source, text: trimmed)
            )
            nextEntryID += 1
        }

        guard !appendedEntries.isEmpty else { return }

        entries.append(contentsOf: appendedEntries)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func classify(_ line: String) -> ConsoleLogSource {
        let lower = line.lowercased()

        if line.contains("[palladium][ffmpeg-bridge]")
            || lower.contains("ffmpeg-bridge")
            || line.contains("ffprobe") {
            return .ffmpeg
        }

        if line.contains("[download]")
            || line.contains("[Merger]")
            || line.contains("[ExtractAudio]") {
            return .download
        }

        return .app
    }

    private static func defaultLogsDirectoryURL() -> URL {
        let fileManager = FileManager.default
        if let documentsURL = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return documentsURL.appendingPathComponent("Logs", isDirectory: true)
        }

        return fileManager.temporaryDirectory.appendingPathComponent("PalladiumLogs", isDirectory: true)
    }
}

actor ConsoleLogFileWriter {
    private let directoryURL: URL
    private let activeLogFileURL: URL
    private let baseName: String
    private let fileExtension: String
    private let maxBytesPerFile: Int
    private let maxArchives: Int

    init(directoryURL: URL, baseFilename: String, maxBytesPerFile: Int, maxArchives: Int) {
        self.directoryURL = directoryURL
        self.activeLogFileURL = directoryURL.appendingPathComponent(baseFilename)
        self.baseName = (baseFilename as NSString).deletingPathExtension
        self.fileExtension = (baseFilename as NSString).pathExtension
        self.maxBytesPerFile = maxBytesPerFile
        self.maxArchives = max(0, maxArchives)
    }

    func prepare() {
        createDirectoryIfNeeded()
        ensureActiveFileExists()
    }

    func append(_ text: String) {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }

        createDirectoryIfNeeded()
        ensureActiveFileExists()
        rotateIfNeeded(forAdditionalBytes: data.count)

        guard let handle = try? FileHandle(forWritingTo: activeLogFileURL) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }

    func clearAll() {
        createDirectoryIfNeeded()

        if FileManager.default.fileExists(atPath: activeLogFileURL.path) {
            try? FileManager.default.removeItem(at: activeLogFileURL)
        }

        guard maxArchives > 0 else {
            ensureActiveFileExists()
            return
        }

        for index in 1...maxArchives {
            let archive = archiveURL(index: index)
            if FileManager.default.fileExists(atPath: archive.path) {
                try? FileManager.default.removeItem(at: archive)
            }
        }

        ensureActiveFileExists()
    }

    private func rotateIfNeeded(forAdditionalBytes additionalBytes: Int) {
        let currentSize = currentFileSizeBytes()
        guard currentSize + additionalBytes > maxBytesPerFile else { return }

        if maxArchives > 0 {
            let oldestArchive = archiveURL(index: maxArchives)
            if FileManager.default.fileExists(atPath: oldestArchive.path) {
                try? FileManager.default.removeItem(at: oldestArchive)
            }

            if maxArchives > 1 {
                for index in stride(from: maxArchives - 1, through: 1, by: -1) {
                    let source = archiveURL(index: index)
                    let destination = archiveURL(index: index + 1)
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try? FileManager.default.removeItem(at: destination)
                    }
                    try? FileManager.default.moveItem(at: source, to: destination)
                }
            }

            let firstArchive = archiveURL(index: 1)
            if FileManager.default.fileExists(atPath: firstArchive.path) {
                try? FileManager.default.removeItem(at: firstArchive)
            }
            if FileManager.default.fileExists(atPath: activeLogFileURL.path) {
                try? FileManager.default.moveItem(at: activeLogFileURL, to: firstArchive)
            }
        } else if FileManager.default.fileExists(atPath: activeLogFileURL.path) {
            try? FileManager.default.removeItem(at: activeLogFileURL)
        }

        ensureActiveFileExists()
    }

    private func currentFileSizeBytes() -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: activeLogFileURL.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return 0
        }
        return sizeNumber.intValue
    }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func ensureActiveFileExists() {
        guard !FileManager.default.fileExists(atPath: activeLogFileURL.path) else { return }
        _ = FileManager.default.createFile(atPath: activeLogFileURL.path, contents: nil)
    }

    private func archiveURL(index: Int) -> URL {
        let name: String
        if fileExtension.isEmpty {
            name = "\(baseName).\(index)"
        } else {
            name = "\(baseName).\(index).\(fileExtension)"
        }
        return directoryURL.appendingPathComponent(name)
    }
}
