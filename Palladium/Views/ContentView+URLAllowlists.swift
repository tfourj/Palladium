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
        do {
            try URLAllowlistManager.addCustomSource(urlString)
            urlAllowlistSources = URLAllowlistManager.loadSources()
            refreshURLAllowlists()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    func removeURLAllowlist(_ source: URLAllowlistSource) {
        URLAllowlistManager.removeCustomSource(source)
        urlAllowlistSources = URLAllowlistManager.loadSources()
    }
}
