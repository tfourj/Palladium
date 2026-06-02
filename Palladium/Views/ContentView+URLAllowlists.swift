import Foundation

extension ContentView {
    func refreshURLAllowlists() {
        guard !isRefreshingURLAllowlists else { return }
        isRefreshingURLAllowlists = true
        Task { @MainActor in
            urlAllowlistSources = await URLAllowlistManager.refreshAllSources()
            isRefreshingURLAllowlists = false
        }
    }

    func addURLAllowlist(_ urlString: String) {
        guard !isRefreshingURLAllowlists else { return }
        isRefreshingURLAllowlists = true
        Task { @MainActor in
            do {
                try await URLAllowlistManager.addCustomSource(urlString)
                urlAllowlistSources = URLAllowlistManager.loadSources()
            } catch {
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
