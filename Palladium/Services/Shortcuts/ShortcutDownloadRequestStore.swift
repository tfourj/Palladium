import Foundation

struct PendingShortcutDownloadRequest: Codable {
    let id: UUID
    let url: String
    let preset: ShortcutDownloadPreset
    let destination: ShortcutSaveDestination
    let createdAt: Date

    init(
        id: UUID = UUID(),
        url: String,
        preset: ShortcutDownloadPreset,
        destination: ShortcutSaveDestination,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.preset = preset
        self.destination = destination
        self.createdAt = createdAt
    }
}

enum ShortcutDownloadRequestStore {
    private static let defaultsKey = "palladium.pendingShortcutDownloadRequest"
    private static let staleLifetime: TimeInterval = 60 * 60

    static func savePendingRequest(_ request: PendingShortcutDownloadRequest) {
        guard let encoded = try? JSONEncoder().encode(request) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }

    static func loadPendingRequest(now: Date = Date()) -> PendingShortcutDownloadRequest? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let request = try? JSONDecoder().decode(PendingShortcutDownloadRequest.self, from: data) else {
            return nil
        }

        guard isFresh(request, now: now) else {
            clearPendingRequest()
            return nil
        }

        return request
    }

    static func consumePendingRequest(now: Date = Date()) -> PendingShortcutDownloadRequest? {
        guard let request = loadPendingRequest(now: now) else {
            return nil
        }
        clearPendingRequest()
        return request
    }

    static func clearStaleRequest(now: Date = Date()) {
        guard let request = loadRawPendingRequest() else {
            return
        }
        guard !isFresh(request, now: now) else {
            return
        }
        clearPendingRequest()
    }

    private static func loadRawPendingRequest() -> PendingShortcutDownloadRequest? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PendingShortcutDownloadRequest.self, from: data)
    }

    private static func clearPendingRequest() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func isFresh(_ request: PendingShortcutDownloadRequest, now: Date) -> Bool {
        now.timeIntervalSince(request.createdAt) <= staleLifetime
    }
}
