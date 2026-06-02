import Foundation

struct URLAllowlistSource: Codable, Identifiable, Equatable {
    let id: UUID
    var urlString: String
    var isDefault: Bool
    var lastRefreshDate: Date?
    var statusMessage: String

    init(
        id: UUID = UUID(),
        urlString: String,
        isDefault: Bool = false,
        lastRefreshDate: Date? = nil,
        statusMessage: String = String(localized: "allowlists.status.not_loaded")
    ) {
        self.id = id
        self.urlString = urlString
        self.isDefault = isDefault
        self.lastRefreshDate = lastRefreshDate
        self.statusMessage = statusMessage
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

    static func loadSources() -> [URLAllowlistSource] {
        let customSources = loadCustomSources()
        let defaultStatus = loadSourceStatuses()[defaultAllowlistURLString]
        let defaultSource = URLAllowlistSource(
            id: UUID(uuidString: "2D1D091A-53D0-4978-BDB5-2F831250B263") ?? UUID(),
            urlString: defaultAllowlistURLString,
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
                isDefault: false,
                lastRefreshDate: status?.lastRefreshDate ?? source.lastRefreshDate,
                statusMessage: status?.statusMessage ?? source.statusMessage
            )
        }
    }

    static func loadCachedEntries() -> [URLAllowlistEntry] {
        guard let data = UserDefaults.standard.data(forKey: cachedEntriesDefaultsKey),
              let entries = try? JSONDecoder().decode([URLAllowlistEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func addCustomSource(_ urlString: String) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host?.isEmpty == false else {
            throw URLAllowlistError.invalidSourceURL
        }
        guard trimmed != defaultAllowlistURLString,
              !loadCustomSources().contains(where: { $0.urlString == trimmed }) else {
            throw URLAllowlistError.duplicateSource
        }

        var sources = loadCustomSources()
        sources.append(URLAllowlistSource(urlString: trimmed))
        saveCustomSources(sources)
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
            ($0.urlString, URLAllowlistSourceStatus(lastRefreshDate: $0.lastRefreshDate, statusMessage: $0.statusMessage))
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

        _ = await refreshAllSources()
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
            let entries = try decodeEntries(from: data, source: source)
            return (
                sourceWithStatus(
                    source,
                    status: String(format: String(localized: "allowlists.status.loaded"), entries.count),
                    refreshedAt: Date()
                ),
                entries
            )
        } catch {
            let cached = cachedEntries(for: source)
            let status = cached.isEmpty
                ? String(format: String(localized: "allowlists.status.failed"), error.localizedDescription)
                : String(format: String(localized: "allowlists.status.cached"), cached.count)
            return (sourceWithStatus(source, status: status), cached)
        }
    }

    private static func decodeEntries(from data: Data, source: URLAllowlistSource) throws -> [URLAllowlistEntry] {
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
        return entries
    }

    private static func cachedEntries(for source: URLAllowlistSource) -> [URLAllowlistEntry] {
        loadCachedEntries().filter { $0.sourceID == source.id }
    }

    private static func sourceWithStatus(
        _ source: URLAllowlistSource,
        status: String,
        refreshedAt: Date? = nil
    ) -> URLAllowlistSource {
        URLAllowlistSource(
            id: source.id,
            urlString: source.urlString,
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
