import Foundation

struct QueuedDownloadConfiguration: Codable, Equatable {
    let presetRawValue: String
    let presetArgumentsJSON: String
    let extraArguments: String
    let downloadPlaylist: Bool
    let downloadSubtitles: Bool
    let embedThumbnail: Bool
    let autoRetryFailedDownloads: Bool
    let subtitleLanguagePattern: String
    let useCookies: Bool
    let cookieFileName: String
    let afterDownloadBehaviorRawValue: String

    var preset: DownloadPreset {
        DownloadPreset(rawValue: presetRawValue) ?? .autoVideo
    }

    var afterDownloadBehavior: AfterDownloadBehavior {
        AfterDownloadBehavior(rawValue: afterDownloadBehaviorRawValue) ?? .ask
    }
}

enum DownloadQueueItemStatus: String, Codable, Equatable {
    case pending
    case running
    case awaitingAction
    case succeeded
    case partial
    case failed
    case cancelled

    var isOutstanding: Bool {
        self == .pending || self == .running || self == .awaitingAction
    }

    var isActive: Bool {
        self == .running || self == .awaitingAction
    }

    var isTerminal: Bool {
        !isOutstanding
    }
}

struct DownloadQueueItem: Codable, Identifiable, Equatable {
    let id: UUID
    let url: String
    let configuration: QueuedDownloadConfiguration
    let createdAt: Date
    var status: DownloadQueueItemStatus
    var title: String?
    var errorMessage: String?
    var completedAt: Date?
}

struct DownloadQueue: Codable, Equatable {
    private(set) var items: [DownloadQueueItem]
    private(set) var isActive: Bool

    init(items: [DownloadQueueItem] = [], isActive: Bool = false) {
        self.items = items
        self.isActive = isActive
    }

    var outstandingCount: Int {
        items.filter { $0.status.isOutstanding }.count
    }

    var currentItem: DownloadQueueItem? {
        items.first(where: { $0.status.isActive })
    }

    var nextPendingItem: DownloadQueueItem? {
        items.first(where: { $0.status == .pending })
    }

    var pendingItems: [DownloadQueueItem] {
        items.filter { $0.status == .pending }
    }

    var hasPendingItems: Bool {
        nextPendingItem != nil
    }

    var hasTerminalItems: Bool {
        items.contains(where: { $0.status.isTerminal })
    }

    static func parsedLinks(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    mutating func append(
        linksText: String,
        configuration: QueuedDownloadConfiguration,
        now: Date = Date()
    ) -> [DownloadQueueItem] {
        let newItems = Self.parsedLinks(from: linksText).map { link in
            DownloadQueueItem(
                id: UUID(),
                url: link,
                configuration: configuration,
                createdAt: now,
                status: .pending
            )
        }
        items.append(contentsOf: newItems)
        return newItems
    }

    mutating func start() {
        guard hasPendingItems else {
            isActive = false
            return
        }
        isActive = true
    }

    mutating func pause() {
        isActive = false
    }

    mutating func markRunning(_ id: UUID) {
        guard currentItem == nil,
              let index = index(of: id),
              items[index].status == .pending else {
            return
        }
        items[index].status = .running
        items[index].errorMessage = nil
        items[index].completedAt = nil
    }

    mutating func markAwaitingAction(_ id: UUID, title: String? = nil) {
        guard let index = index(of: id), items[index].status == .running else { return }
        items[index].status = .awaitingAction
        items[index].title = title
    }

    mutating func markCompleted(
        _ id: UUID,
        partial: Bool,
        title: String? = nil,
        now: Date = Date()
    ) {
        guard let index = index(of: id), items[index].status.isActive else { return }
        items[index].status = partial ? .partial : .succeeded
        items[index].title = title ?? items[index].title
        items[index].errorMessage = nil
        items[index].completedAt = now
        stopIfFinished()
    }

    mutating func markFailed(
        _ id: UUID,
        errorMessage: String?,
        now: Date = Date()
    ) {
        guard let index = index(of: id), items[index].status.isActive else { return }
        items[index].status = .failed
        items[index].errorMessage = errorMessage
        items[index].completedAt = now
        stopIfFinished()
    }

    mutating func markCancelled(_ id: UUID, now: Date = Date()) {
        guard let index = index(of: id), items[index].status.isActive else { return }
        items[index].status = .cancelled
        items[index].completedAt = now
        isActive = false
    }

    @discardableResult
    mutating func restart(_ id: UUID) -> DownloadQueueItem? {
        guard let index = index(of: id),
              currentItem == nil,
              items[index].status == .failed || items[index].status == .cancelled else {
            return nil
        }
        items[index].status = .running
        items[index].errorMessage = nil
        items[index].completedAt = nil
        return items[index]
    }

    mutating func retry(_ id: UUID) {
        guard let index = index(of: id),
              items[index].status == .failed || items[index].status == .cancelled else {
            return
        }
        items[index].status = .pending
        items[index].errorMessage = nil
        items[index].completedAt = nil
    }

    mutating func remove(_ id: UUID) {
        guard let index = index(of: id), !items[index].status.isActive else { return }
        items.remove(at: index)
        stopIfFinished()
    }

    mutating func clearTerminalItems() {
        items.removeAll(where: { $0.status.isTerminal })
    }

    mutating func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        var pending = pendingItems
        guard source.allSatisfy({ pending.indices.contains($0) }),
              destination >= 0,
              destination <= pending.count else {
            return
        }

        let moving = source.sorted().map { pending[$0] }
        for index in source.sorted(by: >) {
            pending.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        pending.insert(contentsOf: moving, at: adjustedDestination)

        var pendingIterator = pending.makeIterator()
        for index in items.indices where items[index].status == .pending {
            if let nextItem = pendingIterator.next() {
                items[index] = nextItem
            }
        }
    }

    func restoredPaused() -> DownloadQueue {
        let restoredItems = items.compactMap { item -> DownloadQueueItem? in
            switch item.status {
            case .succeeded, .partial:
                return nil
            case .running, .awaitingAction:
                var restored = item
                restored.status = .pending
                restored.title = nil
                restored.errorMessage = nil
                restored.completedAt = nil
                return restored
            case .pending, .failed, .cancelled:
                return item
            }
        }
        return DownloadQueue(items: restoredItems, isActive: false)
    }

    func persistableState() -> DownloadQueue {
        DownloadQueue(
            items: items.filter { $0.status != .succeeded && $0.status != .partial },
            isActive: false
        )
    }

    private func index(of id: UUID) -> Int? {
        items.firstIndex(where: { $0.id == id })
    }

    private mutating func stopIfFinished() {
        if !hasPendingItems && currentItem == nil {
            isActive = false
        }
    }
}

enum DownloadQueuePersistence {
    static let defaultsKey = "palladium.downloadQueue"

    static func load(from defaults: UserDefaults = .standard) -> DownloadQueue {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(DownloadQueue.self, from: data) else {
            return DownloadQueue()
        }
        return decoded.restoredPaused()
    }

    static func save(_ queue: DownloadQueue, to defaults: UserDefaults = .standard) {
        let state = queue.persistableState()
        guard !state.items.isEmpty else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
