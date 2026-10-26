import Foundation

/// Picks the latest readable step from package flow log output for the update overlay.
enum PackageActivityLine {
    static let maxLength = 160

    private static let palladiumPrefix = "[palladium]"

    static func latest(in chunk: String) -> String? {
        for rawLine in chunk.split(whereSeparator: \.isNewline).reversed() {
            if let line = displayText(for: String(rawLine)) {
                return line
            }
        }
        return nil
    }

    static func displayText(for rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Machine-readable markers such as [palladium][ffmpeg-progress] are not user facing.
        guard !line.isEmpty, !line.hasPrefix("\(palladiumPrefix)[") else { return nil }

        if line.hasPrefix(palladiumPrefix) {
            line = String(line.dropFirst(palladiumPrefix.count))
        }
        line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !line.isEmpty else { return nil }

        if line.count > maxLength {
            line = String(line.prefix(maxLength - 1)) + "…"
        }
        return line
    }
}
