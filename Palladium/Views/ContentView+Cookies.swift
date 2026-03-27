//
//  ContentView+Cookies.swift
//  Palladium
//

import Foundation

extension ContentView {
    func refreshImportedCookieFiles() {
        do {
            importedCookieFiles = try listImportedCookieFiles()
            guard !selectedCookieFileName.isEmpty else { return }
            if !importedCookieFiles.contains(where: { $0.fileName == selectedCookieFileName }) {
                selectedCookieFileName = ""
            }
        } catch {
            appendConsoleText("[palladium] failed to refresh cookies list: \(error.localizedDescription)\n", source: .app)
        }
    }

    func importCookieFile(from sourceURL: URL) throws {
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        let validatedText = try validatedNetscapeCookiesText(from: data)
        let destinationURL = try uniqueCookieDestinationURL(for: sanitizedCookieFileName(from: sourceURL.lastPathComponent))
        try FileManager.default.createDirectory(at: try cookiesDirectoryURL(), withIntermediateDirectories: true)
        try validatedText.write(to: destinationURL, atomically: true, encoding: .utf8)
        refreshImportedCookieFiles()
        showTemporaryToast(String(format: String(localized: "cookies.toast.imported"), destinationURL.lastPathComponent))
    }

    func deleteImportedCookieFile(_ cookieFile: ImportedCookieFile) throws {
        try FileManager.default.removeItem(at: cookieFile.fileURL)
        refreshImportedCookieFiles()
        if selectedCookieFileName == cookieFile.fileName {
            selectedCookieFileName = ""
        }
    }

    func resolvedSelectedCookieFilePath() -> String? {
        let trimmedSelection = selectedCookieFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return nil }
        do {
            let files = try listImportedCookieFiles()
            importedCookieFiles = files
            if let match = files.first(where: { $0.fileName == trimmedSelection }) {
                return match.fileURL.path
            }
        } catch {
            appendConsoleText("[palladium] failed to resolve selected cookie file: \(error.localizedDescription)\n", source: .app)
        }
        appendConsoleText("[palladium] selected cookie file missing, clearing selection\n", source: .app)
        selectedCookieFileName = ""
        return nil
    }

    func cookiesDirectoryURL() throws -> URL {
        try documentsDirectoryURL().appendingPathComponent("Cookies", isDirectory: true)
    }

    static func loadSelectedCookieFileName() -> String {
        UserDefaults.standard.string(forKey: selectedCookieFileNameDefaultsKey) ?? ""
    }

    private func listImportedCookieFiles() throws -> [ImportedCookieFile] {
        let cookiesURL = try cookiesDirectoryURL()
        try FileManager.default.createDirectory(at: cookiesURL, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: cookiesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return try contents.compactMap { fileURL in
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true else { return nil }
            return ImportedCookieFile(
                fileName: fileURL.lastPathComponent,
                fileURL: fileURL,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: Int64(values.fileSize ?? 0)
            )
        }
        .sorted {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
        }
    }

    private func validatedNetscapeCookiesText(from data: Data) throws -> String {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .isoLatin1)

        guard let text else {
            throw NSError(
                domain: "PalladiumCookies",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "cookies.error.unreadable")]
            )
        }

        let normalizedLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        let hasHeader = normalizedLines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "# Netscape HTTP Cookie File" }
        let hasCookieRecord = normalizedLines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
            return trimmed.split(separator: "\t").count >= 7
        }

        guard hasHeader || hasCookieRecord else {
            throw NSError(
                domain: "PalladiumCookies",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "cookies.error.invalid_format")]
            )
        }

        return normalizedLines.joined(separator: "\n")
    }

    private func sanitizedCookieFileName(from rawValue: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = rawValue.components(separatedBy: invalidCharacters)
        let collapsed = parts.joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty {
            return "cookies.txt"
        }
        return collapsed
    }

    private func uniqueCookieDestinationURL(for fileName: String) throws -> URL {
        let cookiesURL = try cookiesDirectoryURL()
        let baseURL = cookiesURL.appendingPathComponent(fileName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: baseURL.path) else {
            let stem = baseURL.deletingPathExtension().lastPathComponent
            let ext = baseURL.pathExtension
            for index in 2...999 {
                let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                let candidateURL = cookiesURL.appendingPathComponent(candidateName, isDirectory: false)
                if !FileManager.default.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
            throw NSError(
                domain: "PalladiumCookies",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "cookies.error.name_conflict")]
            )
        }
        return baseURL
    }
}
