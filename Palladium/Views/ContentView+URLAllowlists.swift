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

    func importLocalURLAllowlist(from sourceURL: URL, onComplete: ((_ message: String) -> Void)? = nil) {
        guard !isRefreshingURLAllowlists else { return }
        isRefreshingURLAllowlists = true
        Task { @MainActor in
            do {
                let source = try URLAllowlistManager.importLocalSource(from: sourceURL)
                urlAllowlistSources = URLAllowlistManager.loadSources()
                onComplete?(String(format: String(localized: "allowlists.status.imported"), source.displayName))
            } catch {
                onComplete?(String(format: String(localized: "allowlists.status.import_failed"), error.localizedDescription))
                alertMessage = error.localizedDescription
                showAlert = true
            }
            isRefreshingURLAllowlists = false
        }
    }

    func addURLAllowlistFromScheme(_ urlString: String) {
        do {
            if let duplicate = try URLAllowlistManager.duplicateCustomSource(for: urlString) {
                if duplicate.isDefault {
                    alertMessage = String(localized: "allowlists.error.duplicate_source")
                    showAlert = true
                    return
                }
                pendingDuplicateAllowlistURL = duplicate.urlString
                showDuplicateAllowlistPrompt = true
                return
            }
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
            return
        }

        addURLAllowlist(urlString) { message in
            showTemporaryToast(message)
        }
    }

    func replaceURLAllowlist(_ urlString: String) {
        guard !isRefreshingURLAllowlists else { return }
        isRefreshingURLAllowlists = true
        Task { @MainActor in
            do {
                let source = try await URLAllowlistManager.replaceCustomSource(urlString)
                urlAllowlistSources = URLAllowlistManager.loadSources()
                let message = String(format: String(localized: "allowlists.status.replaced"), source.displayName)
                showTemporaryToast(message)
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
