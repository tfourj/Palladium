import Foundation

extension ContentView {
    func refreshURLAllowlists(onComplete: ((_ message: String) -> Void)? = nil) {
        guard !isRefreshingURLAllowlists else { return }
        isRefreshingURLAllowlists = true
        Task { @MainActor in
            urlAllowlistSources = await URLAllowlistManager.refreshAllSources()
            isRefreshingURLAllowlists = false
            onComplete?(String(localized: "allowlists.status.refresh_complete"))
        }
    }

    func addURLAllowlist(_ urlString: String, onComplete: ((_ message: String) -> Void)? = nil) {
        guard !isRefreshingURLAllowlists else { return }
        isRefreshingURLAllowlists = true
        Task { @MainActor in
            do {
                let source = try await URLAllowlistManager.addCustomSource(urlString)
                urlAllowlistSources = URLAllowlistManager.loadSources()
                let message = String(format: String(localized: "allowlists.status.added"), source.displayName)
                onComplete?(message)
            } catch {
                onComplete?(String(format: String(localized: "allowlists.status.add_failed"), error.localizedDescription))
                alertMessage = error.localizedDescription
                showAlert = true
            }
            isRefreshingURLAllowlists = false
        }
    }

    func removeURLAllowlist(_ source: URLAllowlistSource) {
        URLAllowlistManager.removeCustomSource(source)
        urlAllowlistSources = URLAllowlistManager.loadSources()
    }
}
