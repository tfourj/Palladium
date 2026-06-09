import SwiftUI

struct SettingsTabView: View {
    private enum SettingsRoute: Hashable {
        case userInterface
        case downloadSettings
        case downloadModes
        case downloadOptions
        case afterDownload
        case downloadBehavior
        case downloadArguments
        case urlAllowlists
        case cookies
        case appearance
        case downloadsTab
        case history
        case notifications
        case storage
        case packages
        case about
    }

    @Binding var checkPackageUpdatesOnLaunch: Bool
    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var selectedPreset: DownloadPreset
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var detailedProgressEnabled: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var linkHistoryEnabled: Bool
    @Binding var linkHistoryLimit: Int
    @Binding var appAppearanceMode: AppAppearanceMode
    @Binding var showTemporaryDownloads: Bool
    @Binding var selectedCookieFileName: String
    @Binding var defaultDownloadPlaylist: Bool
    @Binding var defaultDownloadSubtitles: Bool
    @Binding var defaultEmbedThumbnail: Bool
    @Binding var defaultUseCookies: Bool
    @Binding var restoreDownloadDefaults: Bool
    let urlAllowlistSources: [URLAllowlistSource]
    let importedCookieFiles: [ImportedCookieFile]

    let storageSummary: StorageManagementSummary
    @Binding var packageSourceMode: PackageSourceMode
    @Binding var customPackageSpecsText: String
    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let availablePackageVersions: [String: [String]]
    let isLoadingPackageVersions: Bool
    let isRunning: Bool
    let isPackageRunning: Bool
    let isRefreshingURLAllowlists: Bool
    let onRefreshVersions: () -> Void
    let onCancelPackages: () -> Void
    let onUpdatePackages: () -> Void
    let onCustomUpdatePackages: (_ ytDlpVersion: String?, _ webkitJSIVersion: String?, _ pipVersion: String?) -> Void
    let onFetchPackageVersions: () -> Void
    let onOpenPackageManager: () -> Void
    let onRefreshStorage: () -> Void
    let onClearDownloadsStorage: () -> Void
    let onClearSavedStorage: () -> Void
    let onClearCacheStorage: () -> Void
    let onPruneDownloadsStorage: (_ window: StoragePruneWindow) -> Void
    let onPruneSavedStorage: (_ window: StoragePruneWindow) -> Void
    let onPruneCacheStorage: (_ window: StoragePruneWindow) -> Void
    let onOpenStorageManager: () -> Void
    let onRefreshCookieFiles: () -> Void
    let onImportCookieFile: (_ sourceURL: URL) throws -> Void
    let onDeleteCookieFile: (_ cookieFile: ImportedCookieFile) throws -> Void
    let onRefreshURLAllowlists: (_ onComplete: ((_ message: String) -> Void)?) -> Void
    let onAddURLAllowlist: (_ urlString: String, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onRemoveURLAllowlist: (_ source: URLAllowlistSource) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("settings.general.section")) {
                    NavigationLink(value: SettingsRoute.userInterface) {
                        settingsRow(
                            title: String(localized: "settings.ui.title"),
                            subtitle: String(localized: "settings.ui.subtitle"),
                            icon: "switch.2",
                            color: .indigo
                        )
                    }

                    NavigationLink(value: SettingsRoute.downloadSettings) {
                        settingsRow(
                            title: String(localized: "settings.download_settings.title"),
                            subtitle: String(localized: "settings.download_settings.subtitle"),
                            icon: "arrow.down.circle.fill",
                            color: .blue
                        )
                    }

                    NavigationLink(value: SettingsRoute.urlAllowlists) {
                        settingsRow(
                            title: String(localized: "allowlists.title"),
                            subtitle: String(format: String(localized: "allowlists.subtitle"), urlAllowlistSources.count),
                            icon: "checkmark.shield.fill",
                            color: .mint
                        )
                    }

                    NavigationLink(value: SettingsRoute.packages) {
                        packagesSettingsRow()
                    }
                }

                Section(header: Text("settings.storage.section")) {
                    NavigationLink(value: SettingsRoute.storage) {
                        settingsRow(
                            title: String(localized: "settings.storage.title"),
                            subtitle: String(format: String(localized: "settings.storage.summary.total"), storageSummary.formattedTotalSize),
                            icon: "internaldrive.fill",
                            color: .teal
                        )
                    }
                }

                Section(header: Text("settings.about.title")) {
                    NavigationLink(value: SettingsRoute.about) {
                        settingsRow(
                            title: String(localized: "settings.about.title"),
                            subtitle: String(localized: "settings.about.subtitle"),
                            icon: "info.circle.fill",
                            color: .orange
                        )
                    }
                }
            }
            .navigationTitle("tab.settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: onRefreshStorage)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .userInterface:
                    userInterfaceSettingsList()
                case .downloadSettings:
                    downloadSettingsList()
                case .downloadModes:
                    DownloadModesSettingsView(
                        selectedPreset: $selectedPreset,
                        rememberSelectedPreset: $rememberSelectedPreset,
                        shareSheetDownloadMode: $shareSheetDownloadMode,
                        isRunning: isRunning
                    )
                case .downloadOptions:
                    DownloadOptionsSettingsView(
                        defaultDownloadPlaylist: $defaultDownloadPlaylist,
                        defaultDownloadSubtitles: $defaultDownloadSubtitles,
                        defaultEmbedThumbnail: $defaultEmbedThumbnail,
                        defaultUseCookies: $defaultUseCookies,
                        restoreDownloadDefaults: $restoreDownloadDefaults,
                        isRunning: isRunning
                    )
                case .afterDownload:
                    AfterDownloadSettingsView(
                        afterDownloadBehavior: $afterDownloadBehavior,
                        isRunning: isRunning
                    )
                case .downloadBehavior:
                    DownloadBehaviorSettingsView(
                        autoDownloadOnPaste: $autoDownloadOnPaste,
                        autoRetryFailedDownloads: $autoRetryFailedDownloads,
                        detailedProgressEnabled: $detailedProgressEnabled,
                        isRunning: isRunning
                    )
                case .downloadArguments:
                    DownloadArgumentsSettingsView(
                        customArgsText: $customArgsText,
                        extraArgsText: $extraArgsText,
                        isRunning: isRunning
                    )
                case .urlAllowlists:
                    URLAllowlistsSettingsView(
                        sources: urlAllowlistSources,
                        isBusy: isRunning || isPackageRunning,
                        isRefreshing: isRefreshingURLAllowlists,
                        onRefresh: onRefreshURLAllowlists,
                        onAdd: onAddURLAllowlist,
                        onRemove: onRemoveURLAllowlist
                    )
                case .appearance:
                    AppearanceSettingsView(
                        appAppearanceMode: $appAppearanceMode,
                        isRunning: isRunning
                    )
                case .downloadsTab:
                    DownloadsTabSettingsView(
                        showTemporaryDownloads: $showTemporaryDownloads,
                        isRunning: isRunning
                    )
                case .history:
                    HistorySettingsView(
                        linkHistoryEnabled: $linkHistoryEnabled,
                        linkHistoryLimit: $linkHistoryLimit,
                        isRunning: isRunning
                    )
                case .notifications:
                    NotificationsSettingsView(
                        notificationsEnabled: $notificationsEnabled,
                        isRunning: isRunning
                    )
                case .storage:
                    StorageSettingsView(
                        summary: storageSummary,
                        isBusy: isRunning || isPackageRunning,
                        onRefresh: onRefreshStorage,
                        onClearDownloads: onClearDownloadsStorage,
                        onClearSaved: onClearSavedStorage,
                        onClearCache: onClearCacheStorage,
                        onPruneDownloads: onPruneDownloadsStorage,
                        onPruneSaved: onPruneSavedStorage,
                        onPruneCache: onPruneCacheStorage,
                        onAppear: onOpenStorageManager
                    )
                case .cookies:
                    CookiesSettingsView(
                        selectedCookieFileName: $selectedCookieFileName,
                        importedCookieFiles: importedCookieFiles,
                        isBusy: isRunning || isPackageRunning,
                        onRefresh: onRefreshCookieFiles,
                        onImport: onImportCookieFile,
                        onDelete: onDeleteCookieFile
                    )
                case .packages:
                    PackagesSettingsView(
                        packageStatusText: packageStatusText,
                        checkPackageUpdatesOnLaunch: $checkPackageUpdatesOnLaunch,
                        packageSourceMode: $packageSourceMode,
                        customPackageSpecsText: $customPackageSpecsText,
                        versionsText: versionsText,
                        updatesSummaryText: updatesSummaryText,
                        updatesAvailable: updatesAvailable,
                        availablePackageVersions: availablePackageVersions,
                        isLoadingPackageVersions: isLoadingPackageVersions,
                        isRunning: isPackageRunning,
                        onRefreshVersions: onRefreshVersions,
                        onCancel: onCancelPackages,
                        onUpdatePackages: onUpdatePackages,
                        onCustomUpdatePackages: onCustomUpdatePackages,
                        onFetchPackageVersions: onFetchPackageVersions,
                        onAppear: onOpenPackageManager
                    )
                case .about:
                    SettingsAboutView()
                }
            }
        }
    }

    private func userInterfaceSettingsList() -> some View {
        List {
            NavigationLink(value: SettingsRoute.appearance) {
                settingsRow(
                    title: String(localized: "settings.ui.appearance.section"),
                    subtitle: String(localized: "settings.appearance.subtitle"),
                    icon: "paintbrush.fill",
                    color: .purple
                )
            }

            NavigationLink(value: SettingsRoute.downloadsTab) {
                settingsRow(
                    title: String(localized: "settings.downloads_tab.title"),
                    subtitle: String(localized: "settings.downloads_tab.subtitle"),
                    icon: "tray.and.arrow.down.fill",
                    color: .teal
                )
            }

            NavigationLink(value: SettingsRoute.history) {
                settingsRow(
                    title: String(localized: "settings.ui.history.section"),
                    subtitle: String(localized: "settings.history.subtitle"),
                    icon: "clock.arrow.circlepath",
                    color: .orange
                )
            }

            NavigationLink(value: SettingsRoute.notifications) {
                settingsRow(
                    title: String(localized: "settings.notifications.title"),
                    subtitle: String(localized: "settings.notifications.subtitle"),
                    icon: "bell.badge.fill",
                    color: .red
                )
            }
        }
        .navigationTitle("settings.ui.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func downloadSettingsList() -> some View {
        List {
            NavigationLink(value: SettingsRoute.downloadModes) {
                settingsRow(
                    title: String(localized: "settings.download_modes.title"),
                    subtitle: String(localized: "settings.download_modes.subtitle"),
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )
            }

            NavigationLink(value: SettingsRoute.afterDownload) {
                settingsRow(
                    title: String(localized: "settings.ui.after_download.title"),
                    subtitle: String(localized: "settings.after_download.subtitle"),
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            }

            NavigationLink(value: SettingsRoute.downloadBehavior) {
                settingsRow(
                    title: String(localized: "settings.download_behavior.title"),
                    subtitle: String(localized: "settings.download_behavior.subtitle"),
                    icon: "bolt.fill",
                    color: .yellow
                )
            }

            NavigationLink(value: SettingsRoute.downloadArguments) {
                settingsRow(
                    title: String(localized: "settings.download_args.title"),
                    subtitle: String(localized: "settings.download_args.subtitle"),
                    icon: "terminal",
                    color: .blue
                )
            }

            NavigationLink(value: SettingsRoute.cookies) {
                settingsRow(
                    title: String(localized: "settings.cookies.title"),
                    subtitle: importedCookieFiles.isEmpty
                        ? String(localized: "settings.cookies.subtitle_empty")
                        : String(format: String(localized: "settings.cookies.subtitle_count"), importedCookieFiles.count),
                    icon: "lock.doc.fill",
                    color: .brown
                )
            }
        }
        .navigationTitle("settings.download_settings.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func packagesSettingsRow() -> some View {
        HStack {
            settingsRow(
                title: String(localized: "settings.packages.title"),
                subtitle: updatesAvailable
                    ? String(localized: "settings.packages.subtitle.updates_available")
                    : String(localized: "settings.packages.subtitle"),
                icon: "shippingbox.fill",
                color: updatesAvailable ? .red : .indigo
            )
            if updatesAvailable {
                Spacer()
                Text(verbatim: "!")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.red)
                    .clipShape(Circle())
            }
        }
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
