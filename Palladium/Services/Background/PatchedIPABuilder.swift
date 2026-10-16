import Combine
import Foundation

/// Downloads the latest stable Palladium release and patches it so background downloads work under the bundle
/// identifier this install runs with.
final class PatchedIPABuilder: ObservableObject {
    enum State: Equatable {
        case idle
        case fetchingRelease
        case downloading(version: String, fraction: Double)
        case patching
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var isBusy: Bool {
        switch state {
        case .fetchingRelease, .downloading, .patching:
            return true
        case .idle, .failed:
            return false
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/tfourj/Palladium/releases/latest")!

    /// Builds the patched .ipa in the temporary directory and returns its location, or nil when building failed.
    func build() async -> URL? {
        guard !isBusy else { return nil }
        state = .fetchingRelease
        do {
            let release = try await fetchLatestRelease()
            guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") }) else {
                throw ReleaseError()
            }

            state = .downloading(version: release.tagName, fraction: 0)
            let downloadedURL = try await download(asset.browserDownloadUrl, version: release.tagName)

            state = .patching
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(asset.name.replacingOccurrences(of: ".ipa", with: "-patched.ipa"))
            let identifier = BackgroundDownloadTask.permittedIdentifierPattern
            try await Self.patch(downloadedURL, to: outputURL, permitting: identifier)

            state = .idle
            return outputURL
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Release.self, from: data)
    }

    private func download(_ url: URL, version: String) async throws -> URL {
        let delegate = DownloadProgressDelegate { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(version: version, fraction: fraction)
            }
        }
        let (temporaryURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw URLError(.badServerResponse)
        }

        let downloadedURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ipa")
        try FileManager.default.moveItem(at: temporaryURL, to: downloadedURL)
        return downloadedURL
    }

    /// Patches off the main actor, since the archive is tens of megabytes.
    private nonisolated static func patch(
        _ inputURL: URL,
        to outputURL: URL,
        permitting identifier: String
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: inputURL) }
            let archive = try Data(contentsOf: inputURL, options: .alwaysMapped)
            let result = try IPABackgroundPatcher.patch(archive, permitting: identifier)
            try result.archive.write(to: outputURL, options: .atomic)
        }.value
    }
}

nonisolated private struct Release: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }

    let tagName: String
    let assets: [Asset]
}

nonisolated private struct ReleaseError: LocalizedError {
    var errorDescription: String? {
        String(localized: "settings.download_behavior.background.patch.no_release_ipa", bundle: .app)
    }
}

/// Reports download progress in whole percent steps, so the UI isn't refreshed for every received chunk.
nonisolated private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastPercent = -1

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let percent = Int(progress.fractionCompleted * 100)
            guard percent != self.lastPercent else { return }
            self.lastPercent = percent
            self.onProgress(progress.fractionCompleted)
        }
    }
}
