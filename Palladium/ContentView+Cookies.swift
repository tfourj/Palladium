import Foundation

extension ContentView {
    func refreshCookieLibrary() {
        do {
            availableCookieFiles = try loadCookieLibraryItems()
        } catch {
            appendConsoleText("[palladium] failed to refresh cookie library: \(error.localizedDescription)\n", source: .app)
            alertMessage = "Failed to refresh cookie files: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func importCookieFile(from sourceURL: URL) {
        guard !isRunning, !isPackageRunning else { return }
        let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let destinationURL = try copyCookieFileToLibrary(from: sourceURL)
            refreshCookieLibrary()
            appendConsoleText("[palladium] imported cookie file: \(destinationURL.lastPathComponent)\n", source: .app)
            showTemporaryToast("Imported \(destinationURL.lastPathComponent)")
        } catch {
            appendConsoleText("[palladium] failed to import cookie file: \(error.localizedDescription)\n", source: .app)
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    func deleteCookieFile(_ item: CookieLibraryItem) {
        guard !isRunning, !isPackageRunning else { return }

        do {
            try FileManager.default.removeItem(at: item.fileURL)
            if selectedCookieFileName == item.fileName {
                selectedCookieFileName = nil
            }
            refreshCookieLibrary()
            appendConsoleText("[palladium] deleted cookie file: \(item.fileName)\n", source: .app)
            showTemporaryToast("Deleted \(item.fileName)")
        } catch {
            appendConsoleText("[palladium] failed to delete cookie file: \(error.localizedDescription)\n", source: .app)
            alertMessage = "Failed to delete cookie file: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func cookieFilesDirectoryURL(createIfMissing: Bool = true) throws -> URL {
        let directoryURL = try documentsDirectoryURL().appendingPathComponent("Cookies", isDirectory: true)
        if createIfMissing {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    func selectedCookiesFilePathForNextDownload(useCookies: Bool) throws -> String? {
        guard useCookies else { return nil }

        let trimmedSelection = (selectedCookieFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else {
            throw CookieLibraryError.noSelection
        }

        let fileURL = try cookieFilesDirectoryURL(createIfMissing: false)
            .appendingPathComponent(trimmedSelection, isDirectory: false)
        try validateCookieFile(at: fileURL)
        return fileURL.path
    }

    private func loadCookieLibraryItems() throws -> [CookieLibraryItem] {
        let directoryURL = try cookieFilesDirectoryURL()
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { fileURL in
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
            ),
            values.isRegularFile == true else {
                return nil
            }
            return CookieLibraryItem(
                fileName: fileURL.lastPathComponent,
                fileURL: fileURL,
                modifiedDate: values.contentModificationDate ?? values.creationDate ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.modifiedDate == rhs.modifiedDate {
                return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
            return lhs.modifiedDate > rhs.modifiedDate
        }
    }

    private func copyCookieFileToLibrary(from sourceURL: URL) throws -> URL {
        try validateCookieFile(at: sourceURL)

        let destinationDirectoryURL = try cookieFilesDirectoryURL()
        let destinationURL = uniqueCookieFileURL(
            in: destinationDirectoryURL,
            preferredFileName: sourceURL.lastPathComponent
        )

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw CookieLibraryError.copyFailed(error.localizedDescription)
        }

        do {
            try validateCookieFile(at: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return destinationURL
    }

    private func uniqueCookieFileURL(in directoryURL: URL, preferredFileName: String) -> URL {
        let baseName = (preferredFileName as NSString).deletingPathExtension
        let pathExtension = (preferredFileName as NSString).pathExtension
        let normalizedBaseName = baseName.isEmpty ? "cookies" : baseName
        var candidateIndex = 1

        while true {
            let candidateName: String
            if candidateIndex == 1 {
                candidateName = normalizedBaseName
            } else {
                candidateName = "\(normalizedBaseName) \(candidateIndex)"
            }

            let fileName: String
            if pathExtension.isEmpty {
                fileName = candidateName
            } else {
                fileName = "\(candidateName).\(pathExtension)"
            }

            let candidateURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            candidateIndex += 1
        }
    }

    private func validateCookieFile(at fileURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw CookieLibraryError.missingFile(fileURL.lastPathComponent)
        }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw CookieLibraryError.unreadableFile(fileURL.lastPathComponent)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CookieLibraryError.unreadableFile(fileURL.lastPathComponent)
        }

        guard !data.isEmpty else {
            throw CookieLibraryError.emptyFile(fileURL.lastPathComponent)
        }

        let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
        guard let content, isValidCookieFileContent(content) else {
            throw CookieLibraryError.invalidFormat(fileURL.lastPathComponent)
        }
    }

    private func isValidCookieFileContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("# Netscape HTTP Cookie File") {
            return true
        }

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmedLine = String(line).trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            let fields = trimmedLine.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count == 7 {
                return true
            }
        }

        return false
    }
}

private enum CookieLibraryError: LocalizedError {
    case noSelection
    case missingFile(String)
    case unreadableFile(String)
    case emptyFile(String)
    case invalidFormat(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Choose an imported cookie file before starting the download."
        case .missingFile(let fileName):
            return "The selected cookie file is missing: \(fileName)"
        case .unreadableFile(let fileName):
            return "The cookie file could not be read: \(fileName)"
        case .emptyFile(let fileName):
            return "The cookie file is empty: \(fileName)"
        case .invalidFormat(let fileName):
            return "The cookie file is not a valid Netscape cookie file: \(fileName)"
        case .copyFailed(let details):
            return "Failed to copy the cookie file: \(details)"
        }
    }
}
