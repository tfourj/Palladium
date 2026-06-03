import Foundation

struct URLAllowlistSource: Codable, Identifiable, Equatable {
    let id: UUID
    var urlString: String
    var name: String?
    var isDefault: Bool
    var lastRefreshDate: Date?
    var statusMessage: String

    init(
        id: UUID = UUID(),
        urlString: String,
        name: String? = nil,
        isDefault: Bool = false,
        lastRefreshDate: Date? = nil,
        statusMessage: String = String(localized: "allowlists.status.not_loaded")
    ) {
        self.id = id
        self.urlString = urlString
        self.name = name
        self.isDefault = isDefault
        self.lastRefreshDate = lastRefreshDate
        self.statusMessage = statusMessage
    }

    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? displayURL : trimmedName
    }

    var displayURL: String {
        urlString
    }
}

struct URLAllowlistEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var sourceID: UUID
    var sourceURLString: String
    var name: String
    var pattern: String

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        sourceURLString: String,
        name: String,
        pattern: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceURLString = sourceURLString
        self.name = name
        self.pattern = pattern
    }
}

struct URLAllowlistValidationResult {
    let isAllowed: Bool
    let matchedEntryName: String?
    let message: String
}

enum URLAllowlistManager {
    static let defaultAllowlistURLString = "https://al.getpalladium.app/default.json"

    private static let customSourcesDefaultsKey = "palladium.urlAllowlistCustomSources"
    private static let cachedEntriesDefaultsKey = "palladium.urlAllowlistCachedEntries"
    private static let sourceStatusesDefaultsKey = "palladium.urlAllowlistSourceStatuses"
    private static let defaultSourceID = UUID(uuidString: "2D1D091A-53D0-4978-BDB5-2F831250B263") ?? UUID()
    private static let builtInDefaultName = "Palladium's default allowlist"

    static func loadSources() -> [URLAllowlistSource] {
        let customSources = loadCustomSources()
        let defaultStatus = loadSourceStatuses()[defaultAllowlistURLString]
        let defaultSource = URLAllowlistSource(
            id: defaultSourceID,
            urlString: defaultAllowlistURLString,
            name: defaultStatus?.name ?? builtInDefaultName,
            isDefault: true,
            lastRefreshDate: defaultStatus?.lastRefreshDate,
            statusMessage: defaultStatus?.statusMessage ?? String(localized: "allowlists.status.not_loaded")
        )
        return [defaultSource] + customSources
    }

    static func loadCustomSources() -> [URLAllowlistSource] {
        guard let data = UserDefaults.standard.data(forKey: customSourcesDefaultsKey),
              let sources = try? JSONDecoder().decode([URLAllowlistSource].self, from: data) else {
            return []
        }
        let statuses = loadSourceStatuses()
        return sources.compactMap { source in
            let trimmed = source.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed != defaultAllowlistURLString else {
                return nil
            }
            let status = statuses[trimmed]
            return URLAllowlistSource(
                id: source.id,
                urlString: trimmed,
                name: status?.name ?? source.name,
                isDefault: false,
                lastRefreshDate: status?.lastRefreshDate ?? source.lastRefreshDate,
                statusMessage: status?.statusMessage ?? source.statusMessage
            )
        }
    }

    static func loadCachedEntries() -> [URLAllowlistEntry] {
        guard let data = UserDefaults.standard.data(forKey: cachedEntriesDefaultsKey),
              let entries = try? JSONDecoder().decode([URLAllowlistEntry].self, from: data) else {
            return builtInDefaultEntries()
        }
        guard entries.contains(where: { $0.sourceID == defaultSourceID }) else {
            return builtInDefaultEntries() + entries
        }
        return entries
    }

    static func addCustomSource(_ urlString: String) async throws -> URLAllowlistSource {
        let trimmed = normalizedSourceURLString(from: urlString)
        try validateSourceURL(trimmed)
        guard trimmed != defaultAllowlistURLString,
              !loadCustomSources().contains(where: { $0.urlString == trimmed }) else {
            throw URLAllowlistError.duplicateSource
        }

        let source = URLAllowlistSource(urlString: trimmed)
        let refreshed = await refreshSource(source)
        var sources = loadCustomSources()
        sources.append(refreshed.source)
        saveCustomSources(sources)

        var cachedEntries = loadCachedEntries()
        cachedEntries.removeAll { $0.sourceID == source.id }
        cachedEntries.append(contentsOf: refreshed.entries)
        saveCachedEntries(cachedEntries)

        var statuses = loadSourceStatuses()
        statuses[refreshed.source.urlString] = URLAllowlistSourceStatus(
            name: refreshed.source.name,
            lastRefreshDate: refreshed.source.lastRefreshDate,
            statusMessage: refreshed.source.statusMessage
        )
        saveSourceStatuses(statuses)
        return refreshed.source
    }

    static func duplicateCustomSource(for urlString: String) throws -> URLAllowlistSource? {
        let trimmed = normalizedSourceURLString(from: urlString)
        try validateSourceURL(trimmed)
        guard trimmed != defaultAllowlistURLString else {
            return URLAllowlistSource(
                id: defaultSourceID,
                urlString: defaultAllowlistURLString,
                name: builtInDefaultName,
                isDefault: true
            )
        }
        return loadCustomSources().first { $0.urlString == trimmed }
    }

    static func replaceCustomSource(_ urlString: String) async throws -> URLAllowlistSource {
        let trimmed = normalizedSourceURLString(from: urlString)
        try validateSourceURL(trimmed)
        guard trimmed != defaultAllowlistURLString,
              let existingSource = loadCustomSources().first(where: { $0.urlString == trimmed }) else {
            throw URLAllowlistError.invalidSourceURL
        }

        let refreshed = await refreshSource(existingSource)
        let sources = loadCustomSources().map { source in
            source.id == existingSource.id ? refreshed.source : source
        }
        saveCustomSources(sources)

        var cachedEntries = loadCachedEntries()
        cachedEntries.removeAll { $0.sourceID == existingSource.id }
        cachedEntries.append(contentsOf: refreshed.entries)
        saveCachedEntries(cachedEntries)

        var statuses = loadSourceStatuses()
        statuses[refreshed.source.urlString] = URLAllowlistSourceStatus(
            name: refreshed.source.name,
            lastRefreshDate: refreshed.source.lastRefreshDate,
            statusMessage: refreshed.source.statusMessage
        )
        saveSourceStatuses(statuses)
        return refreshed.source
    }

    static func removeCustomSource(_ source: URLAllowlistSource) {
        guard !source.isDefault else { return }
        let remainingSources = loadCustomSources().filter { $0.id != source.id }
        saveCustomSources(remainingSources)

        let remainingEntries = loadCachedEntries().filter { $0.sourceID != source.id }
        saveCachedEntries(remainingEntries)

        var statuses = loadSourceStatuses()
        statuses.removeValue(forKey: source.urlString)
        saveSourceStatuses(statuses)
    }

    static func refreshAllSources() async -> [URLAllowlistSource] {
        var sources = loadSources()
        var cachedEntries = loadCachedEntries()

        for index in sources.indices {
            let source = sources[index]
            let refreshed = await refreshSource(source)
            sources[index] = refreshed.source
            cachedEntries.removeAll { $0.sourceID == source.id }
            cachedEntries.append(contentsOf: refreshed.entries)
        }

        saveCustomSources(sources.filter { !$0.isDefault })
        saveCachedEntries(cachedEntries)
        saveSourceStatuses(Dictionary(uniqueKeysWithValues: sources.map {
            ($0.urlString, URLAllowlistSourceStatus(name: $0.name, lastRefreshDate: $0.lastRefreshDate, statusMessage: $0.statusMessage))
        }))
        return loadSources()
    }

    static func validateDownloadURL(_ urlString: String) async -> URLAllowlistValidationResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            return URLAllowlistValidationResult(
                isAllowed: false,
                matchedEntryName: nil,
                message: String(localized: "allowlists.blocked.invalid_url")
            )
        }

        let entries = loadCachedEntries()
        guard !entries.isEmpty else {
            return URLAllowlistValidationResult(
                isAllowed: false,
                matchedEntryName: nil,
                message: String(localized: "allowlists.blocked.no_entries")
            )
        }

        for entry in entries {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern) else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return URLAllowlistValidationResult(
                    isAllowed: true,
                    matchedEntryName: entry.name,
                    message: String(format: String(localized: "allowlists.allowed.by"), entry.name)
                )
            }
        }

        return URLAllowlistValidationResult(
            isAllowed: false,
            matchedEntryName: nil,
            message: String(localized: "allowlists.blocked.not_allowed")
        )
    }

    private static func refreshSource(_ source: URLAllowlistSource) async -> (source: URLAllowlistSource, entries: [URLAllowlistEntry]) {
        guard let url = URL(string: source.urlString) else {
            return (
                sourceWithStatus(source, status: String(localized: "allowlists.status.invalid_source")),
                cachedEntries(for: source)
            )
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw URLAllowlistError.httpStatus(httpResponse.statusCode)
            }
            let document = try decodeDocument(from: data, source: source)
            return (
                sourceWithStatus(
                    source,
                    name: document.name,
                    status: String(format: String(localized: "allowlists.status.loaded"), document.entries.count),
                    refreshedAt: Date()
                ),
                document.entries
            )
        } catch {
            let cached = cachedEntries(for: source)
            if source.isDefault, cached.isEmpty {
                let entries = builtInDefaultEntries()
                return (
                    sourceWithStatus(
                        source,
                        name: builtInDefaultName,
                        status: String(format: String(localized: "allowlists.status.built_in"), entries.count)
                    ),
                    entries
                )
            }
            let status = cached.isEmpty
                ? String(format: String(localized: "allowlists.status.failed"), error.localizedDescription)
                : String(format: String(localized: "allowlists.status.cached"), cached.count)
            return (sourceWithStatus(source, status: status), cached)
        }
    }

    private static func decodeDocument(from data: Data, source: URLAllowlistSource) throws -> (name: String?, entries: [URLAllowlistEntry]) {
        let document = try JSONDecoder().decode(URLAllowlistDocument.self, from: data)
        guard document.version == 1 else {
            throw URLAllowlistError.unsupportedVersion
        }

        var entries: [URLAllowlistEntry] = []
        for (index, rawEntry) in document.entries.enumerated() {
            if rawEntry.enabled == false { continue }
            let pattern = rawEntry.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            _ = try NSRegularExpression(pattern: pattern)
            let name = rawEntry.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(URLAllowlistEntry(
                sourceID: source.id,
                sourceURLString: source.urlString,
                name: name?.isEmpty == false ? name! : String(format: String(localized: "allowlists.entry.fallback_name"), index + 1),
                pattern: pattern
            ))
        }

        guard !entries.isEmpty else {
            throw URLAllowlistError.emptyDocument
        }
        let name = document.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false ? name : nil, entries)
    }

    private static func cachedEntries(for source: URLAllowlistSource) -> [URLAllowlistEntry] {
        if source.isDefault {
            let entries = rawCachedEntries().filter { $0.sourceID == source.id }
            return entries.isEmpty ? builtInDefaultEntries() : entries
        }
        return rawCachedEntries().filter { $0.sourceID == source.id }
    }

    private static func rawCachedEntries() -> [URLAllowlistEntry] {
        guard let data = UserDefaults.standard.data(forKey: cachedEntriesDefaultsKey),
              let entries = try? JSONDecoder().decode([URLAllowlistEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private static func builtInDefaultEntries() -> [URLAllowlistEntry] {
        [
            URLAllowlistEntry(
                id: UUID(uuidString: "B4A16D19-A49E-4563-8A23-46D5973F3435") ?? UUID(),
                sourceID: defaultSourceID,
                sourceURLString: defaultAllowlistURLString,
                name: "Vimeo",
                pattern: "^https?://(www\\.)?vimeo\\.com/.+$"
            ),
            URLAllowlistEntry(
                id: UUID(uuidString: "4A26E825-7D75-497C-94E3-11C124F77727") ?? UUID(),
                sourceID: defaultSourceID,
                sourceURLString: defaultAllowlistURLString,
                name: "Internet Archive",
                pattern: "^https?://(www\\.)?archive\\.org/.+$"
            ),
            URLAllowlistEntry(
                id: UUID(uuidString: "703D7C38-70E5-42F7-8A9A-16B026C71A5B") ?? UUID(),
                sourceID: defaultSourceID,
                sourceURLString: defaultAllowlistURLString,
                name: "PeerTube",
                pattern: "^https?://([a-zA-Z0-9-]+\\.)?peertube\\.[a-zA-Z]{2,}/.+$"
            )
        ]
    }

    private static func sourceWithStatus(
        _ source: URLAllowlistSource,
        name: String? = nil,
        status: String,
        refreshedAt: Date? = nil
    ) -> URLAllowlistSource {
        URLAllowlistSource(
            id: source.id,
            urlString: source.urlString,
            name: name ?? source.name,
            isDefault: source.isDefault,
            lastRefreshDate: refreshedAt ?? source.lastRefreshDate,
            statusMessage: status
        )
    }

    private static func saveCustomSources(_ sources: [URLAllowlistSource]) {
        let cleaned = sources.map {
            URLAllowlistSource(
                id: $0.id,
                urlString: $0.urlString,
                name: $0.name,
                isDefault: false,
                lastRefreshDate: $0.lastRefreshDate,
                statusMessage: $0.statusMessage
            )
        }
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        UserDefaults.standard.set(data, forKey: customSourcesDefaultsKey)
    }

    private static func saveCachedEntries(_ entries: [URLAllowlistEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: cachedEntriesDefaultsKey)
    }

    private static func loadSourceStatuses() -> [String: URLAllowlistSourceStatus] {
        guard let data = UserDefaults.standard.data(forKey: sourceStatusesDefaultsKey),
              let statuses = try? JSONDecoder().decode([String: URLAllowlistSourceStatus].self, from: data) else {
            return [:]
        }
        return statuses
    }

    private static func saveSourceStatuses(_ statuses: [String: URLAllowlistSourceStatus]) {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        UserDefaults.standard.set(data, forKey: sourceStatusesDefaultsKey)
    }

    private static func normalizedSourceURLString(from urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) == nil else {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static func validateSourceURL(_ urlString: String) throws {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host?.isEmpty == false else {
            throw URLAllowlistError.invalidSourceURL
        }
    }
}

private struct URLAllowlistDocument: Codable {
    let version: Int
    let name: String?
    let entries: [URLAllowlistDocumentEntry]
}

private struct URLAllowlistDocumentEntry: Codable {
    let name: String?
    let pattern: String
    let enabled: Bool?
}

private struct URLAllowlistSourceStatus: Codable {
    let name: String?
    let lastRefreshDate: Date?
    let statusMessage: String
}

enum URLAllowlistError: LocalizedError {
    case invalidSourceURL
    case duplicateSource
    case unsupportedVersion
    case emptyDocument
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            return String(localized: "allowlists.error.invalid_source")
        case .duplicateSource:
            return String(localized: "allowlists.error.duplicate_source")
        case .unsupportedVersion:
            return String(localized: "allowlists.error.unsupported_version")
        case .emptyDocument:
            return String(localized: "allowlists.error.empty_document")
        case .httpStatus(let statusCode):
            return String(format: String(localized: "allowlists.error.http_status"), statusCode)
        }
    }
}
