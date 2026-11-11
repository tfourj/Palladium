import Foundation

/// Lists, imports, and removes yt-dlp plugins in `Documents/Plugins`, which Python passes to `--plugin-dirs`.
nonisolated enum YTDLPPluginLibrary {
    enum ImportError: LocalizedError, Equatable {
        case unsupportedFile
        case notPlugin
        case unreadableArchive

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                return String(localized: "plugins.error.unsupported_file", bundle: .app)
            case .notPlugin:
                return String(localized: "plugins.error.not_plugin", bundle: .app)
            case .unreadableArchive:
                return String(localized: "plugins.error.unreadable_archive", bundle: .app)
            }
        }
    }

    static let directoryName = "Plugins"
    static let environmentKey = "PALLADIUM_PLUGINS_DIR"
    /// Archive formats yt-dlp reads from a plugin folder.
    static let archiveExtensions: Set<String> = ["zip", "whl", "egg"]

    private static let packageDirectoryName = "yt_dlp_plugins"
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50

    static func directoryURL(fileManager: FileManager = .default) throws -> URL {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func plugins(in directory: URL, fileManager: FileManager = .default) throws -> [YTDLPPlugin] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let isFolder = values.isDirectory == true
            guard isFolder || archiveExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return YTDLPPlugin(
                fileName: url.lastPathComponent,
                fileURL: url,
                isFolder: isFolder,
                kinds: (try? kinds(at: url, isFolder: isFolder, fileManager: fileManager)) ?? [],
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: isFolder ? folderSize(at: url, fileManager: fileManager) : Int64(values.fileSize ?? 0)
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Copies a plugin archive or folder into `directory`, replacing a plugin with the same name.
    @discardableResult
    static func importPlugin(
        from sourceURL: URL,
        into directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let isFolder = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        guard isFolder || archiveExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw ImportError.unsupportedFile
        }
        guard try !kinds(at: sourceURL, isFolder: isFolder, fileManager: fileManager).isEmpty else {
            throw ImportError.notPlugin
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: isFolder)
        guard destinationURL.standardizedFileURL != sourceURL.standardizedFileURL else { return destinationURL }

        let stagingURL = directory.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: isFolder)
        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
        return destinationURL
    }

    static func delete(_ plugin: YTDLPPlugin, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: plugin.fileURL)
    }

    /// Plugin types found under a top-level `yt_dlp_plugins` folder, as yt-dlp requires.
    static func kinds(inEntryNames names: [String]) -> [YTDLPPlugin.Kind] {
        let found = Set(names.compactMap { name -> YTDLPPlugin.Kind? in
            let components = name.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count >= 3,
                  components[0] == Substring(packageDirectoryName),
                  name.hasSuffix(".py")
            else {
                return nil
            }
            return YTDLPPlugin.Kind(rawValue: String(components[1]))
        })
        return YTDLPPlugin.Kind.allCases.filter(found.contains)
    }

    /// Reads entry names from a ZIP central directory without extracting the archive.
    static func archiveEntryNames(in data: Data) throws -> [String] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ImportError.unreadableArchive }
        let lowestOffset = max(0, bytes.count - 22 - 0xffff)
        guard let endOffset = stride(from: bytes.count - 22, through: lowestOffset, by: -1)
            .first(where: { uint32(bytes, at: $0) == endOfCentralDirectorySignature })
        else {
            throw ImportError.unreadableArchive
        }

        let count = Int(uint16(bytes, at: endOffset + 10))
        var position = Int(uint32(bytes, at: endOffset + 16))
        guard position < endOffset else { throw ImportError.unreadableArchive }

        var names: [String] = []
        for _ in 0..<count {
            guard position + 46 <= endOffset, uint32(bytes, at: position) == centralHeaderSignature else {
                throw ImportError.unreadableArchive
            }
            let nameLength = Int(uint16(bytes, at: position + 28))
            let extraLength = Int(uint16(bytes, at: position + 30))
            let commentLength = Int(uint16(bytes, at: position + 32))
            guard position + 46 + nameLength <= endOffset else { throw ImportError.unreadableArchive }
            names.append(String(decoding: bytes[position + 46..<position + 46 + nameLength], as: UTF8.self))
            position += 46 + nameLength + extraLength + commentLength
        }
        return names
    }

    private static func kinds(at url: URL, isFolder: Bool, fileManager: FileManager) throws -> [YTDLPPlugin.Kind] {
        if isFolder {
            return kinds(inEntryNames: folderEntryNames(at: url, fileManager: fileManager))
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return kinds(inEntryNames: try archiveEntryNames(in: data))
    }

    private static func folderEntryNames(at url: URL, fileManager: FileManager) -> [String] {
        let packagePath = url.appendingPathComponent(packageDirectoryName, isDirectory: true).path
        let subpaths = (try? fileManager.subpathsOfDirectory(atPath: packagePath)) ?? []
        return subpaths.map { "\(packageDirectoryName)/\($0)" }
    }

    private static func folderSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return enumerator.reduce(into: Int64(0)) { total, item in
            guard let itemURL = item as? URL,
                  let size = try? itemURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else {
                return
            }
            total += Int64(size)
        }
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
