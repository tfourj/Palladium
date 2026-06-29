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
                do {
                    try normalizeImportedCookieFileIfNeeded(at: match.fileURL)
                } catch {
                    appendConsoleText(
                        "[palladium] selected cookie file is invalid: \(error.localizedDescription)\n",
                        source: .app
                    )
                    selectedCookieFileName = ""
                    refreshImportedCookieFiles()
                    return nil
                }
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
        try normalizedNetscapeCookiesText(from: decodedCookieText(from: data))
    }

    private func decodedCookieText(from data: Data) throws -> String {
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
        return text
    }

    private func normalizeImportedCookieFileIfNeeded(at fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        let originalText = try decodedCookieText(from: data)
        let normalizedText = try normalizedNetscapeCookiesText(from: originalText)
        guard normalizedText != normalizedLineEndings(for: originalText) else { return }
        try normalizedText.write(to: fileURL, atomically: true, encoding: .utf8)
        appendConsoleText(
            "[palladium] normalized selected cookie file: \(fileURL.lastPathComponent)\n",
            source: .app
        )
        refreshImportedCookieFiles()
    }

    private func normalizedNetscapeCookiesText(from text: String) throws -> String {
        let normalizedLines = normalizedLineEndings(for: text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        var outputLines = ["# Netscape HTTP Cookie File"]
        var foundCookieRecord = false

        for line in normalizedLines {
            if shouldSkipCookieLine(line) {
                continue
            }

            guard let record = normalizedNetscapeCookieRecord(from: line) else {
                throw invalidCookieFormatError()
            }

            outputLines.append(record)
            foundCookieRecord = true
        }

        guard foundCookieRecord else {
            throw invalidCookieFormatError()
        }

        return outputLines.joined(separator: "\n") + "\n"
    }

    private func normalizedLineEndings(for text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func shouldSkipCookieLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if isCookieFileHeader(trimmed) {
            return true
        }
        return trimmed.hasPrefix("#") && !trimmed.hasPrefix("#HttpOnly_")
    }

    private func isCookieFileHeader(_ line: String) -> Bool {
        line == "# Netscape HTTP Cookie File" || line == "# HTTP Cookie File"
    }

    private func normalizedNetscapeCookieRecord(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawFields: [String]

        if line.contains("\t") {
            rawFields = line
                .split(separator: "\t", omittingEmptySubsequences: false)
                .map { String($0) }
        } else {
            let splitFields = trimmed.split(
                maxSplits: 6,
                omittingEmptySubsequences: true,
                whereSeparator: isCookieFieldSeparator
            )
            rawFields = splitFields.map { String($0) }
        }

        guard rawFields.count == 7 else { return nil }

        let domain = rawFields[0].trimmingCharacters(in: .whitespaces)
        let includeSubdomains = normalizedCookieBoolean(rawFields[1])
        let path = rawFields[2].trimmingCharacters(in: .whitespaces)
        let secure = normalizedCookieBoolean(rawFields[3])
        let expiration = rawFields[4].trimmingCharacters(in: .whitespaces)
        let name = rawFields[5].trimmingCharacters(in: .whitespaces)
        let value = rawFields[6]

        guard !domain.isEmpty,
              let includeSubdomains,
              !path.isEmpty,
              let secure,
              Int64(expiration) != nil,
              !name.isEmpty else {
            return nil
        }

        return [
            domain,
            includeSubdomains,
            path,
            secure,
            expiration,
            name,
            value,
        ].joined(separator: "\t")
    }

    private func isCookieFieldSeparator(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    private func normalizedCookieBoolean(_ rawValue: String) -> String? {
        switch rawValue.trimmingCharacters(in: .whitespaces).uppercased() {
        case "TRUE":
            return "TRUE"
        case "FALSE":
            return "FALSE"
        default:
            return nil
        }
    }

    private func invalidCookieFormatError() -> NSError {
        NSError(
            domain: "PalladiumCookies",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "cookies.error.invalid_format")]
        )
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
