import SwiftUI

struct SettingsTabView: View {
    private enum SettingsRoute: Hashable {
        case userInterface
        case downloadSettings
        case downloadModes
        case shareSheet
        case downloadQuality
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
        case packageManager
        case customizeDownloadOptions
        case advanced
        case about
    }

    private struct SearchableSetting: Identifiable {
        let route: SettingsRoute
        let title: String
        let subtitle: String
        let icon: String
        let color: Color

        var id: SettingsRoute { route }
    }

    private struct SearchableControlSetting: Identifiable {
        let id: String
        let menu: SettingsRoute
        let title: String
        let subtitle: String
        let keywords: [String]
        let makeControl: () -> AnyView

        func matches(_ query: String) -> Bool {
            ([title, subtitle] + keywords).contains { value in
                value.localizedStandardContains(query)
            }
        }
    }

    private struct SearchableControlGroup: Identifiable {
        let route: SettingsRoute
        let title: String
        let settings: [SearchableControlSetting]

        var id: SettingsRoute { route }
    }

    @State private var searchText = ""
    @State private var showPatchReinstallPrompt = false
    @State private var showNightlyPackageWarning = false

    @Binding var checkPackageUpdatesOnLaunch: Bool
    @Binding var autoUpdatePackagesOnLaunch: Bool
    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var selectedPreset: DownloadPreset
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var detailedProgressEnabled: Bool
    @Binding var downloadPresetSettings: [DownloadPresetSetting]
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var showShareSheetFormatButton: Bool
    @Binding var showShareSheetFillURLButton: Bool
    @Binding var linkHistoryEnabled: Bool
    @Binding var linkHistoryLimit: Int
    @Binding var hideHistoryCount: Bool
    @Binding var appAppearanceMode: AppAppearanceMode
    @Binding var showTemporaryDownloads: Bool
    @Binding var useCookies: Bool
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
    @Binding var lockedPackageVersions: [String: String]
    @Binding var youtubePatchMode: YouTubePatchMode
    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let runtimePackagesMissing: Bool
    let availablePackageVersions: [String: [String]]
    let isLoadingPackageVersions: Bool
    let isRunning: Bool
    let isPackageRunning: Bool
    let isRefreshingURLAllowlists: Bool
    let onRefreshVersions: () -> Void
    let onCancelPackages: () -> Void
    let onUpdatePackages: () -> Void
    let onInstallPackagePayloadZip: (_ sourceURL: URL) -> Void
    let onRestorePipPackages: () -> Void
    let onReinstallPackages: () -> Void
    let onCustomUpdatePackages: (_ versions: [String: String]) -> Void
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
    let onPasteCookieFile: (_ rawText: String) throws -> Void
    let onDeleteCookieFile: (_ cookieFile: ImportedCookieFile) throws -> Void
    let onRefreshURLAllowlists: (_ onComplete: ((_ message: String) -> Void)?) -> Void
    let onAddURLAllowlist: (_ urlString: String, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onImportURLAllowlist: (_ sourceURL: URL, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onPasteURLAllowlist: (_ json: String, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onRemoveURLAllowlist: (_ source: URLAllowlistSource) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    settingsList
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("tab.settings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("settings.search.prompt")
            )
            .onAppear(perform: onRefreshStorage)
            .alert("settings.advanced.reinstall_prompt.title", isPresented: $showPatchReinstallPrompt) {
                Button("common.cancel", role: .cancel) {}
                Button("settings.advanced.reinstall") {
                    onReinstallPackages()
                }
            } message: {
                Text("settings.advanced.reinstall_prompt.message")
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
        }
    }

    private var settingsList: some View {
        List {
            Section(header: Text("settings.general.section")) {
                settingsNavigationLink(for: .userInterface)
                settingsNavigationLink(for: .downloadSettings)
                if FeatureFlags.isURLAllowlistEnabled {
                    settingsNavigationLink(for: .urlAllowlists)
                }
                settingsNavigationLink(for: .packages)
                settingsNavigationLink(for: .advanced)
            }

            Section(header: Text("settings.storage.section")) {
                settingsNavigationLink(for: .storage)
            }

            Section(header: Text("settings.about.title")) {
                settingsNavigationLink(for: .about)
            }
        }
    }

    private var searchResultsList: some View {
        List {
            if filteredControlSettings.isEmpty, filteredSettings.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }

            ForEach(filteredControlGroups) { group in
                Section(group.title) {
                    ForEach(group.settings) { setting in
                        searchableControlRow(for: setting)
                    }
                }
            }

            if !filteredSettings.isEmpty {
                Section("settings.search.destinations.section") {
                    ForEach(filteredSettings) { setting in
                        settingsNavigationLink(for: setting)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .userInterface:
            userInterfaceSettingsList()
        case .downloadSettings:
            downloadSettingsList()
        case .downloadModes:
            DownloadModesSettingsView(
                selectedPreset: $selectedPreset,
                rememberSelectedPreset: $rememberSelectedPreset,
                downloadPresetSettings: $downloadPresetSettings,
                isRunning: isRunning
            )
        case .shareSheet:
            ShareSheetSettingsView(
                shareSheetDownloadMode: $shareSheetDownloadMode,
                showFormatButton: $showShareSheetFormatButton,
                showFillURLButton: $showShareSheetFillURLButton,
                downloadPresetSettings: downloadPresetSettings,
                isRunning: isRunning
            )
        case .downloadQuality:
            DownloadQualitySettingsView(isRunning: isRunning)
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
                onImport: onImportURLAllowlist,
                onPaste: onPasteURLAllowlist,
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
                hideHistoryCount: $hideHistoryCount,
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
                useCookies: $useCookies,
                selectedCookieFileName: $selectedCookieFileName,
                defaultUseCookies: $defaultUseCookies,
                importedCookieFiles: importedCookieFiles,
                isBusy: isRunning || isPackageRunning,
                onRefresh: onRefreshCookieFiles,
                onImport: onImportCookieFile,
                onPaste: onPasteCookieFile,
                onDelete: onDeleteCookieFile
            )
        case .packages:
            PackagesSettingsView(
                packageStatusText: packageStatusText,
                checkPackageUpdatesOnLaunch: $checkPackageUpdatesOnLaunch,
                autoUpdatePackagesOnLaunch: $autoUpdatePackagesOnLaunch,
                packageSourceMode: $packageSourceMode,
                customPackageSpecsText: $customPackageSpecsText,
                lockedPackageVersions: $lockedPackageVersions,
                versionsText: versionsText,
                updatesSummaryText: updatesSummaryText,
                updatesAvailable: updatesAvailable,
                runtimePackagesMissing: runtimePackagesMissing,
                availablePackageVersions: availablePackageVersions,
                isLoadingPackageVersions: isLoadingPackageVersions,
                isRunning: isPackageRunning,
                onRefreshVersions: onRefreshVersions,
                onCancel: onCancelPackages,
                onUpdatePackages: onUpdatePackages,
                onInstallPayloadZip: onInstallPackagePayloadZip,
                onRestorePipPackages: onRestorePipPackages,
                onCustomUpdatePackages: onCustomUpdatePackages,
                onFetchPackageVersions: onFetchPackageVersions,
                onAppear: onOpenPackageManager
            )
        case .packageManager:
            PackageManagerSettingsView(
                checkPackageUpdatesOnLaunch: $checkPackageUpdatesOnLaunch,
                autoUpdatePackagesOnLaunch: $autoUpdatePackagesOnLaunch,
                packageSourceMode: $packageSourceMode,
                customPackageSpecsText: $customPackageSpecsText,
                isRunning: isPackageRunning,
                onInstallPayloadZip: onInstallPackagePayloadZip
            )
        case .customizeDownloadOptions:
            DownloadOptionsOrderSettingsView(
                settings: $downloadPresetSettings,
                isRunning: isRunning
            )
        case .advanced:
            AdvancedSettingsView(
                youtubePatchMode: $youtubePatchMode,
                isRunning: isRunning || isPackageRunning,
                onReinstallPackages: onReinstallPackages
            )
        case .about:
            SettingsAboutView()
        }
    }

    private func userInterfaceSettingsList() -> some View {
        List {
            settingsNavigationLink(for: .appearance)
            settingsNavigationLink(for: .downloadsTab)
            settingsNavigationLink(for: .history)
            settingsNavigationLink(for: .notifications)
        }
        .navigationTitle("settings.ui.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func downloadSettingsList() -> some View {
        List {
            settingsNavigationLink(for: .downloadModes)
            settingsNavigationLink(for: .shareSheet)
            settingsNavigationLink(for: .downloadQuality)
            settingsNavigationLink(for: .afterDownload)
            settingsNavigationLink(for: .downloadBehavior)
            settingsNavigationLink(for: .downloadArguments)
            settingsNavigationLink(for: .cookies)
        }
        .navigationTitle("settings.download_settings.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredSettings: [SearchableSetting] {
        searchableSettings.filter { setting in
            setting.title.localizedStandardContains(searchText)
                || setting.subtitle.localizedStandardContains(searchText)
        }
    }

    private var filteredControlSettings: [SearchableControlSetting] {
        searchableControlSettings.filter { $0.matches(searchText) }
    }

    private var filteredControlGroups: [SearchableControlGroup] {
        searchableSettings.compactMap { menu in
            let settings = filteredControlSettings.filter { $0.menu == menu.route }
            guard !settings.isEmpty else { return nil }
            return SearchableControlGroup(
                route: menu.route,
                title: menu.title,
                settings: settings
            )
        }
    }

    private var searchableControlSettings: [SearchableControlSetting] {
        var settings = baseSearchableControlSettings
        let customizeHelp = String(localized: "settings.download_modes.customize_options.footer")
        let customizeTitle = String(localized: "settings.download_modes.customize_options.title")

        settings.insert(
            contentsOf: downloadPresetSettings.map { setting in
                let title = setting.preset.title
                return SearchableControlSetting(
                    id: "downloadPresetVisibility.\(setting.id)",
                    menu: .customizeDownloadOptions,
                    title: title,
                    subtitle: customizeHelp,
                    keywords: [customizeTitle, String(localized: "settings.download_modes.title")],
                    makeControl: {
                        AnyView(
                            searchToggle(
                                title,
                                isOn: presetVisibilityBinding(for: setting.id),
                                disabled: isPresetVisibilityDisabled(for: setting.id)
                            )
                        )
                    }
                )
            },
            at: 7
        )
        return settings
    }

    private var baseSearchableControlSettings: [SearchableControlSetting] {
        [
            controlSetting(
                id: "appearance",
                menu: .appearance,
                title: "settings.ui.appearance.picker",
                subtitle: "settings.ui.appearance.help",
                keywords: AppAppearanceMode.allCases.map(\.title)
            ) { title in
                AnyView(
                    Picker(title, selection: $appAppearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning)
                )
            },
            controlSetting(
                id: "showTemporaryDownloads",
                menu: .downloadsTab,
                title: "settings.ui.downloads.show_temp",
                subtitle: "settings.ui.downloads.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $showTemporaryDownloads, disabled: isRunning))
            },
            controlSetting(
                id: "historyEnabled",
                menu: .history,
                title: "settings.ui.history.enable",
                subtitle: "settings.ui.history.help",
                keywords: [String(localized: "settings.ui.history.section")]
            ) { title in
                AnyView(searchToggle(title, isOn: $linkHistoryEnabled, disabled: isRunning))
            },
            controlSetting(
                id: "historyLimit",
                menu: .history,
                title: "settings.ui.history.limit",
                subtitle: "settings.ui.history.help"
            ) { title in
                AnyView(
                    Stepper(value: $linkHistoryLimit, in: 0...ContentView.maxLinkHistoryLimit) {
                        LabeledContent(title, value: String(linkHistoryLimit))
                    }
                    .disabled(isRunning || !linkHistoryEnabled)
                )
            },
            controlSetting(
                id: "hideHistoryCount",
                menu: .history,
                title: "settings.ui.history.hide_count",
                subtitle: "settings.ui.history.help"
            ) { title in
                AnyView(
                    searchToggle(
                        title,
                        isOn: $hideHistoryCount,
                        disabled: isRunning || !linkHistoryEnabled
                    )
                )
            },
            controlSetting(
                id: "notificationsEnabled",
                menu: .notifications,
                title: "settings.notifications.toggle_single",
                subtitle: "settings.notifications.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $notificationsEnabled, disabled: isRunning))
            },
            controlSetting(
                id: "normalDownloadMode",
                menu: .downloadModes,
                title: "settings.ui.modes.normal",
                subtitle: "settings.ui.modes.help",
                keywords: DownloadPreset.allCases.map(\.title)
            ) { title in
                AnyView(
                    Picker(title, selection: $selectedPreset) {
                        ForEach(DownloadOptions.visiblePresets(from: downloadPresetSettings)) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning)
                )
            },
            controlSetting(
                id: "shareSheetDownloadMode",
                menu: .shareSheet,
                title: "settings.ui.modes.share_sheet",
                subtitle: "settings.download_modes.share_help",
                keywords: ShareSheetDownloadMode.allCases.map(\.title)
            ) { title in
                AnyView(
                    Picker(title, selection: $shareSheetDownloadMode) {
                        ForEach(DownloadOptions.visibleShareSheetModes(from: downloadPresetSettings)) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning)
                )
            },
            controlSetting(
                id: "showShareSheetFormatButton",
                menu: .shareSheet,
                title: "settings.share_sheet.show_format",
                subtitle: "settings.share_sheet.buttons_help"
            ) { title in
                AnyView(
                    searchToggle(
                        title,
                        isOn: $showShareSheetFormatButton,
                        disabled: isRunning
                    )
                )
            },
            controlSetting(
                id: "showShareSheetFillURLButton",
                menu: .shareSheet,
                title: "settings.share_sheet.show_fill_url",
                subtitle: "settings.share_sheet.buttons_help"
            ) { title in
                AnyView(
                    searchToggle(
                        title,
                        isOn: $showShareSheetFillURLButton,
                        disabled: isRunning
                    )
                )
            },
            controlSetting(
                id: "rememberDownloadMode",
                menu: .downloadModes,
                title: "settings.ui.modes.remember",
                subtitle: "settings.ui.modes.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $rememberSelectedPreset, disabled: isRunning))
            },
            controlSetting(
                id: "defaultPlaylist",
                menu: .downloadOptions,
                title: "settings.download_defaults.playlist.default",
                subtitle: "download.options.summary.default"
            ) { title in
                AnyView(searchToggle(title, isOn: $defaultDownloadPlaylist, disabled: isRunning))
            },
            controlSetting(
                id: "defaultSubtitles",
                menu: .downloadOptions,
                title: "settings.download_defaults.subtitles.default",
                subtitle: "download.options.summary.default"
            ) { title in
                AnyView(searchToggle(title, isOn: $defaultDownloadSubtitles, disabled: isRunning))
            },
            controlSetting(
                id: "defaultThumbnail",
                menu: .downloadOptions,
                title: "settings.download_defaults.thumbnail.default",
                subtitle: "download.options.summary.default"
            ) { title in
                AnyView(searchToggle(title, isOn: $defaultEmbedThumbnail, disabled: isRunning))
            },
            controlSetting(
                id: "defaultCookies",
                menu: .downloadOptions,
                title: "settings.download_defaults.cookies.default",
                subtitle: "download.options.summary.default"
            ) { title in
                AnyView(searchToggle(title, isOn: $defaultUseCookies, disabled: isRunning))
            },
            controlSetting(
                id: "restoreDownloadDefaults",
                menu: .downloadOptions,
                title: "settings.download_defaults.restore",
                subtitle: "settings.download_defaults.restore.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $restoreDownloadDefaults, disabled: isRunning))
            },
            controlSetting(
                id: "afterDownload",
                menu: .afterDownload,
                title: "settings.ui.after_download.picker",
                subtitle: "settings.ui.after_download.help",
                keywords: AfterDownloadBehavior.allCases.map(\.title)
            ) { title in
                AnyView(
                    Picker(title, selection: $afterDownloadBehavior) {
                        ForEach(AfterDownloadBehavior.allCases) { behavior in
                            Label(behavior.title, systemImage: behavior.icon).tag(behavior)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning)
                )
            },
            controlSetting(
                id: "autoDownloadOnPaste",
                menu: .downloadBehavior,
                title: "settings.ui.paste.auto_download",
                subtitle: "settings.ui.paste.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $autoDownloadOnPaste, disabled: isRunning))
            },
            controlSetting(
                id: "retryFailedDownloads",
                menu: .downloadBehavior,
                title: "settings.ui.retry_failed.toggle",
                subtitle: "settings.ui.retry_failed.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $autoRetryFailedDownloads, disabled: isRunning))
            },
            controlSetting(
                id: "detailedProgress",
                menu: .downloadBehavior,
                title: "settings.ui.progress.verbose",
                subtitle: "settings.ui.progress.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $detailedProgressEnabled, disabled: isRunning))
            },
            controlSetting(
                id: "customArguments",
                menu: .downloadArguments,
                title: "download.args.custom.title",
                subtitle: "download.args.custom.help"
            ) { title in
                AnyView(searchTextField(title, text: $customArgsText))
            },
            controlSetting(
                id: "globalArguments",
                menu: .downloadArguments,
                title: "download.args.global.title",
                subtitle: "download.args.global.help"
            ) { title in
                AnyView(searchTextField(title, text: $extraArgsText))
            },
            controlSetting(
                id: "selectedCookieFile",
                menu: .cookies,
                title: "download.options.cookies.picker",
                subtitle: "cookies.settings.help",
                keywords: importedCookieFiles.map(\.displayName)
            ) { title in
                AnyView(
                    Picker(title, selection: $selectedCookieFileName) {
                        Text("common.none").tag("")
                        ForEach(importedCookieFiles) { cookieFile in
                            Text(cookieFile.displayName).tag(cookieFile.fileName)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning || isPackageRunning || importedCookieFiles.isEmpty)
                )
            },
            controlSetting(
                id: "packageSource",
                menu: .packageManager,
                title: "packages.source.picker",
                subtitle: "settings.packages.subtitle",
                keywords: PackageSourceMode.allCases.map(\.title)
            ) { title in
                AnyView(
                    Picker(title, selection: packageSourceSearchBinding) {
                        ForEach(PackageSourceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isPackageRunning)
                    .alert("packages.source.nightly.warning.title", isPresented: $showNightlyPackageWarning) {
                        Button("common.cancel", role: .cancel) {}
                        Button("packages.source.nightly.enable") {
                            packageSourceMode = .nightly
                        }
                    } message: {
                        Text("packages.source.nightly.warning.message")
                    }
                )
            },
            controlSetting(
                id: "customPackageSpecs",
                menu: .packageManager,
                title: "packages.source.custom_specs.title",
                subtitle: "packages.source.custom_specs.help"
            ) { title in
                AnyView(
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                        TextField(title, text: $customPackageSpecsText, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .disabled(isPackageRunning || packageSourceMode != .custom)
                )
            },
            controlSetting(
                id: "packageUpdateChecks",
                menu: .packageManager,
                title: "settings.ui.packages.auto_check",
                subtitle: "settings.ui.packages.auto_check.help"
            ) { title in
                AnyView(searchToggle(title, isOn: $checkPackageUpdatesOnLaunch, disabled: isPackageRunning))
            },
            controlSetting(
                id: "automaticPackageUpdates",
                menu: .packageManager,
                title: "settings.ui.packages.auto_update",
                subtitle: "settings.ui.packages.auto_update.help"
            ) { title in
                AnyView(
                    searchToggle(
                        title,
                        isOn: $autoUpdatePackagesOnLaunch,
                        disabled: isPackageRunning || !checkPackageUpdatesOnLaunch
                    )
                )
            },
            controlSetting(
                id: "youtubePatchMode",
                menu: .advanced,
                title: "settings.advanced.youtube_patch_mode",
                subtitle: "settings.advanced.youtube_patch_mode.help",
                keywords: YouTubePatchMode.allCases.map(\.title) + [String(localized: "settings.advanced.title")]
            ) { title in
                AnyView(
                    Picker(title, selection: $youtubePatchMode) {
                        ForEach(YouTubePatchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning || isPackageRunning)
                    .onChange(of: youtubePatchMode) {
                        showPatchReinstallPrompt = true
                    }
                )
            }
        ]
    }

    private func controlSetting(
        id: String,
        menu: SettingsRoute,
        title: String.LocalizationValue,
        subtitle: String.LocalizationValue,
        keywords: [String] = [],
        makeControl: @escaping (_ title: String) -> AnyView
    ) -> SearchableControlSetting {
        let localizedTitle = String(localized: title)
        return SearchableControlSetting(
            id: id,
            menu: menu,
            title: localizedTitle,
            subtitle: String(localized: subtitle),
            keywords: keywords,
            makeControl: { makeControl(localizedTitle) }
        )
    }

    private func searchableControlRow(for setting: SearchableControlSetting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            setting.makeControl()

            Text(setting.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func searchToggle(
        _ title: String,
        isOn: Binding<Bool>,
        disabled: Bool
    ) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .disabled(disabled)
    }

    private func searchTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextField(title, text: text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .disabled(isRunning)
        }
    }

    private func presetVisibilityBinding(for presetID: String) -> Binding<Bool> {
        Binding(
            get: {
                downloadPresetSettings.first(where: { $0.id == presetID })?.isVisible ?? false
            },
            set: { isVisible in
                guard let index = downloadPresetSettings.firstIndex(where: { $0.id == presetID }) else {
                    return
                }
                downloadPresetSettings[index].isVisible = isVisible
            }
        )
    }

    private var packageSourceSearchBinding: Binding<PackageSourceMode> {
        Binding(
            get: { packageSourceMode },
            set: { newValue in
                guard !isPackageRunning else { return }
                if newValue == .nightly, packageSourceMode != .nightly {
                    showNightlyPackageWarning = true
                } else {
                    packageSourceMode = newValue
                }
            }
        )
    }

    private func isPresetVisibilityDisabled(for presetID: String) -> Bool {
        guard let setting = downloadPresetSettings.first(where: { $0.id == presetID }) else {
            return true
        }
        let visibleCount = downloadPresetSettings.filter(\.isVisible).count
        return isRunning || (setting.isVisible && visibleCount <= 1)
    }

    private var searchableSettings: [SearchableSetting] {
        let routes: [SettingsRoute] = [
            .userInterface,
            .appearance,
            .downloadsTab,
            .history,
            .notifications,
            .downloadSettings,
            .downloadModes,
            .shareSheet,
            .downloadQuality,
            .customizeDownloadOptions,
            .downloadOptions,
            .afterDownload,
            .downloadBehavior,
            .downloadArguments,
            .cookies,
            .urlAllowlists,
            .packages,
            .packageManager,
            .advanced,
            .storage,
            .about
        ]

        return routes
            .filter { FeatureFlags.isURLAllowlistEnabled || $0 != .urlAllowlists }
            .map { setting(for: $0) }
    }

    private func setting(for route: SettingsRoute) -> SearchableSetting {
        switch route {
        case .userInterface:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.ui.title"),
                subtitle: String(localized: "settings.ui.subtitle"),
                icon: "switch.2",
                color: .indigo
            )
        case .downloadSettings:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.download_settings.title"),
                subtitle: String(localized: "settings.download_settings.subtitle"),
                icon: "arrow.down.circle.fill",
                color: .blue
            )
        case .downloadModes:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.download_modes.title"),
                subtitle: String(localized: "settings.download_modes.subtitle"),
                icon: "arrow.down.circle.fill",
                color: .blue
            )
        case .shareSheet:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.share_sheet.title"),
                subtitle: String(localized: "settings.share_sheet.subtitle"),
                icon: "square.and.arrow.up.fill",
                color: .teal
            )
        case .downloadQuality:
            return SearchableSetting(
                route: route,
                title: "Download Quality",
                subtitle: "Default video and audio formats, codecs, and quality",
                icon: "4k.tv.fill",
                color: .purple
            )
        case .customizeDownloadOptions:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.download_modes.customize_options.title"),
                subtitle: String(localized: "settings.download_modes.customize_options.footer"),
                icon: "line.3.horizontal.decrease",
                color: .blue
            )
        case .downloadOptions:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.download_defaults.title"),
                subtitle: String(localized: "download.options.summary.default"),
                icon: "slider.horizontal.3",
                color: .blue
            )
        case .afterDownload:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.ui.after_download.title"),
                subtitle: String(localized: "settings.after_download.subtitle"),
                icon: "checkmark.circle.fill",
                color: .green
            )
        case .downloadBehavior:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.download_behavior.title"),
                subtitle: String(localized: "settings.download_behavior.subtitle"),
                icon: "bolt.fill",
                color: .yellow
            )
        case .downloadArguments:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.download_args.title"),
                subtitle: String(localized: "settings.download_args.subtitle"),
                icon: "terminal",
                color: .blue
            )
        case .urlAllowlists:
            return SearchableSetting(
                route: route,
                title: String(localized: "allowlists.title"),
                subtitle: String(
                    format: String(localized: "allowlists.subtitle"),
                    urlAllowlistSources.count
                ),
                icon: "checkmark.shield.fill",
                color: .mint
            )
        case .cookies:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.cookies.title"),
                subtitle: importedCookieFiles.isEmpty
                    ? String(localized: "settings.cookies.subtitle_empty")
                    : String(
                        format: String(localized: "settings.cookies.subtitle_count"),
                        importedCookieFiles.count
                    ),
                icon: "lock.doc.fill",
                color: .brown
            )
        case .appearance:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.ui.appearance.section"),
                subtitle: String(localized: "settings.appearance.subtitle"),
                icon: "paintbrush.fill",
                color: .purple
            )
        case .downloadsTab:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.downloads_tab.title"),
                subtitle: String(localized: "settings.downloads_tab.subtitle"),
                icon: "tray.and.arrow.down.fill",
                color: .teal
            )
        case .history:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.ui.history.section"),
                subtitle: String(localized: "settings.history.subtitle"),
                icon: "clock.arrow.circlepath",
                color: .orange
            )
        case .notifications:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.notifications.title"),
                subtitle: String(localized: "settings.notifications.subtitle"),
                icon: "bell.badge.fill",
                color: .red
            )
        case .storage:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.storage.title"),
                subtitle: String(
                    format: String(localized: "settings.storage.summary.total"),
                    storageSummary.formattedTotalSize
                ),
                icon: "internaldrive.fill",
                color: .teal
            )
        case .packages:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.packages.title"),
                subtitle: updatesAvailable
                    ? String(localized: "settings.packages.subtitle.updates_available")
                    : String(localized: "settings.packages.subtitle"),
                icon: "shippingbox.fill",
                color: updatesAvailable ? .red : .indigo
            )
        case .packageManager:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.packages.manager.title"),
                subtitle: String(localized: "settings.packages.subtitle"),
                icon: "gearshape.fill",
                color: .indigo
            )
        case .advanced:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.advanced.title"),
                subtitle: String(localized: "settings.advanced.subtitle"),
                icon: "gearshape.2.fill",
                color: .gray
            )
        case .about:
            return SearchableSetting(
                route: route,
                title: String(localized: "settings.about.title"),
                subtitle: String(localized: "settings.about.subtitle"),
                icon: "info.circle.fill",
                color: .orange
            )
        }
    }

    private func settingsNavigationLink(for route: SettingsRoute) -> some View {
        settingsNavigationLink(for: setting(for: route))
    }

    private func settingsNavigationLink(for setting: SearchableSetting) -> some View {
        NavigationLink(value: setting.route) {
            settingsRow(for: setting)
        }
    }

    private func settingsRow(for setting: SearchableSetting) -> some View {
        HStack {
            settingsRow(
                title: setting.title,
                subtitle: setting.subtitle,
                icon: setting.icon,
                color: setting.color
            )
            if setting.route == .packages, updatesAvailable {
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
