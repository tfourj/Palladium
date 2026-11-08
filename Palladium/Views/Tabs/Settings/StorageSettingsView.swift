import SwiftUI
import UniformTypeIdentifiers

struct StorageSettingsView: View {
    let summary: StorageManagementSummary
    let isBusy: Bool
    let onRefresh: () -> Void
    let onClearDownloads: () -> Void
    let onClearSaved: () -> Void
    let onClearCache: () -> Void
    let onPruneDownloads: (StoragePruneWindow) -> Void
    let onPruneSaved: (StoragePruneWindow) -> Void
    let onPruneCache: (StoragePruneWindow) -> Void
    let onAppear: () -> Void

    @State private var showClearDownloadsConfirmation = false
    @State private var showClearSavedConfirmation = false
    @State private var showFolderPicker = false
    @State private var folderErrorMessage: String?

    private let locationStore = SavedDownloadLocationStore.shared

    var body: some View {
        Form {
            Section {
                summaryRow(
                    title: String(localized: "settings.storage.downloads.title", bundle: .app),
                    subtitle: summary.downloads.locationLabel,
                    systemImage: "tray.full.fill",
                    accentColor: .blue,
                    location: summary.downloads
                )

                summaryRow(
                    title: String(localized: "settings.storage.saved.title", bundle: .app),
                    subtitle: summary.saved.locationLabel,
                    systemImage: "folder.fill",
                    accentColor: .green,
                    location: summary.saved
                )

                summaryRow(
                    title: String(localized: "settings.storage.cache.title", bundle: .app),
                    subtitle: summary.cache.locationLabel,
                    systemImage: "internaldrive.fill",
                    accentColor: .orange,
                    location: summary.cache
                )

                HStack {
                    Text("settings.storage.total")
                    Spacer()
                    Text(summary.formattedTotalSize)
                        .foregroundStyle(.secondary)
                }

                Button("settings.storage.refresh", action: onRefresh)
                    .disabled(isBusy)
            } header: {
                Text("settings.storage.overview.title")
            } footer: {
                Text("settings.storage.overview.help")
            }

            Section {
                Button("storage.action.clear_downloads", role: .destructive) {
                    showClearDownloadsConfirmation = true
                }
                .disabled(isBusy)

                Menu("storage.prune.title") {
                    ForEach(StoragePruneWindow.allCases) { window in
                        Button(window.title) {
                            onPruneDownloads(window)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("settings.storage.downloads.title")
            } footer: {
                Text("settings.storage.downloads.help")
            }

            Section {
                LabeledContent("settings.storage.saved.location.title") {
                    Menu {
                        Button("settings.storage.saved.location.choose") {
                            showFolderPicker = true
                        }
                        if locationStore.isCustom {
                            Button("settings.storage.saved.location.reset", action: resetSavedLocation)
                        }
                    } label: {
                        Text(savedLocationTitle)
                    }
                }
                .disabled(isBusy)

                Button("storage.action.clear_saved", role: .destructive) {
                    showClearSavedConfirmation = true
                }
                .disabled(isBusy)

                Menu("storage.prune.title") {
                    ForEach(StoragePruneWindow.allCases) { window in
                        Button(window.title) {
                            onPruneSaved(window)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("settings.storage.saved.title")
            } footer: {
                savedSectionFooter
            }

            Section {
                Button("storage.action.clear_cache", role: .destructive, action: onClearCache)
                    .disabled(isBusy)

                Menu("storage.prune.title") {
                    ForEach(StoragePruneWindow.allCases) { window in
                        Button(window.title) {
                            onPruneCache(window)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("settings.storage.cache.title")
            } footer: {
                Text("settings.storage.cache.help")
            }

            if isBusy {
                Section {
                    Text("settings.storage.disabled_help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("settings.storage.title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("storage.confirm.downloads.title", isPresented: $showClearDownloadsConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("common.clear", role: .destructive, action: onClearDownloads)
        } message: {
            Text("storage.confirm.downloads.message")
        }
        .alert("storage.confirm.saved.title", isPresented: $showClearSavedConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("common.clear", role: .destructive, action: onClearSaved)
        } message: {
            savedClearConfirmationMessage
        }
        .alert(
            Text(folderErrorMessage ?? ""),
            isPresented: Binding(
                get: { folderErrorMessage != nil },
                set: { if !$0 { folderErrorMessage = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            handlePickedFolder(result)
        }
        .onAppear(perform: onAppear)
    }

    private var savedLocationTitle: String {
        switch locationStore.state {
        case .appFolder:
            return String(localized: "settings.storage.saved.location.app_folder", bundle: .app)
        case .custom(let folderName):
            return folderName
        case .unavailable:
            return String(localized: "settings.storage.saved.location.unavailable", bundle: .app)
        }
    }

    @ViewBuilder
    private var savedSectionFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .unavailable(let folderName) = locationStore.state {
                Text(
                    String(
                        format: String(localized: "settings.storage.saved.location.unavailable_help", bundle: .app),
                        folderName
                    )
                )
            }
            Text("settings.storage.saved.help")
            Text("settings.storage.saved.location.help")
        }
    }

    private var savedClearConfirmationMessage: Text {
        guard case .custom = locationStore.state else {
            return Text("storage.confirm.saved.message")
        }
        return Text(
            String(
                format: String(localized: "storage.confirm.saved.custom_message", bundle: .app),
                locationStore.displayPath
            )
        )
    }

    private func handlePickedFolder(_ result: Result<URL, Error>) {
        do {
            try locationStore.useFolder(try result.get())
            onRefresh()
        } catch {
            folderErrorMessage = String(
                format: String(localized: "storage.error.choose_folder", bundle: .app),
                error.localizedDescription
            )
        }
    }

    private func resetSavedLocation() {
        locationStore.resetToAppFolder()
        onRefresh()
    }

    private func summaryRow(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color,
        location: StorageLocationSummary
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(location.formattedSize)
                    .foregroundStyle(.primary)
                Text(location.itemDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StorageManagementSummary {
    let downloads: StorageLocationSummary
    let saved: StorageLocationSummary
    let cache: StorageLocationSummary

    static let empty = StorageManagementSummary(
        downloads: .empty(locationLabel: String(localized: "storage.path.temp", bundle: .app)),
        saved: .empty(locationLabel: String(localized: "storage.path.saved", bundle: .app)),
        cache: .empty(locationLabel: String(localized: "storage.path.cache", bundle: .app))
    )

    var totalBytes: Int64 {
        downloads.totalBytes + saved.totalBytes + cache.totalBytes
    }

    var formattedTotalSize: String {
        StorageLocationSummary.byteFormatter.string(fromByteCount: totalBytes)
    }
}

struct StorageLocationSummary {
    let locationLabel: String
    let itemCount: Int
    let totalBytes: Int64

    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func empty(locationLabel: String) -> StorageLocationSummary {
        StorageLocationSummary(locationLabel: locationLabel, itemCount: 0, totalBytes: 0)
    }

    var formattedSize: String {
        Self.byteFormatter.string(fromByteCount: totalBytes)
    }

    var itemDescription: String {
        if itemCount == 1 {
            return String(localized: "storage.items.one", bundle: .app)
        }
        return String(format: String(localized: "storage.items.many", bundle: .app), itemCount)
    }
}

enum StoragePruneWindow: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case thirtyDays
    case ninetyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:
            return String(localized: "storage.prune.day_1", bundle: .app)
        case .sevenDays:
            return String(localized: "storage.prune.day_7", bundle: .app)
        case .thirtyDays:
            return String(localized: "storage.prune.day_30", bundle: .app)
        case .ninetyDays:
            return String(localized: "storage.prune.day_90", bundle: .app)
        }
    }

    var cutoffDate: Date {
        let now = Date()
        switch self {
        case .oneDay:
            return now.addingTimeInterval(-86_400)
        case .sevenDays:
            return now.addingTimeInterval(-(86_400 * 7))
        case .thirtyDays:
            return now.addingTimeInterval(-(86_400 * 30))
        case .ninetyDays:
            return now.addingTimeInterval(-(86_400 * 90))
        }
    }
}
