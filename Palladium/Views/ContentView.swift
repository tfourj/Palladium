//
//  ContentView.swift
//  Palladium
//
//  Created by TfourJ on 3. 3. 26.
//

import SwiftUI
import OSLog
import Foundation

struct ContentView: View {
    enum AppTab: Hashable {
        case download
        case settings
        case console
    }

    enum PhotosMediaType {
        case video
        case image
    }

    enum PhotosCompatibilityState: Equatable {
        case checking
        case compatible(PhotosMediaType)
        case incompatible(String)

        var isCompatible: Bool {
            if case .compatible = self {
                return true
            }
            return false
        }
    }

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium",
        category: "python"
    )

    static let presetDefaultsKey = "palladium.selectedPreset"
    static let customArgsDefaultsKey = "palladium.customArgs"
    static let extraArgsDefaultsKey = "palladium.extraArgs"
    static let afterDownloadBehaviorDefaultsKey = "palladium.afterDownloadBehavior"
    static let askUserAfterDownloadDefaultsKey = "palladium.askUserAfterDownload"
    static let selectedPostDownloadActionDefaultsKey = "palladium.selectedPostDownloadAction"
    static let notificationsEnabledDefaultsKey = "palladium.notificationsEnabled"
    static let rememberSelectedPresetDefaultsKey = "palladium.rememberSelectedPreset"
    static let autoDownloadOnPasteDefaultsKey = "palladium.autoDownloadOnPaste"
    static let shareSheetDownloadModeDefaultsKey = "palladium.shareSheetDownloadMode"
    static let downloadPlaylistDefaultsKey = "palladium.downloadPlaylist"
    static let downloadSubtitlesDefaultsKey = "palladium.downloadSubtitles"
    static let embedThumbnailDefaultsKey = "palladium.embedThumbnail"
    static let detailedProgressEnabledDefaultsKey = "palladium.detailedProgressEnabled"
    static let subtitleLanguagePatternDefaultsKey = "palladium.subtitleLanguagePattern"
    static let customSubtitleLanguagePatternDefaultsKey = "palladium.customSubtitleLanguagePattern"
    static let useCookiesDefaultsKey = "palladium.useCookies"
    static let selectedCookieFileNameDefaultsKey = "palladium.selectedCookieFileName"
    static let linkHistoryEnabledDefaultsKey = "palladium.linkHistoryEnabled"
    static let linkHistoryLimitDefaultsKey = "palladium.linkHistoryLimit"
    static let linkHistoryEntriesDefaultsKey = "palladium.linkHistoryEntries"
    static let appAppearanceModeDefaultsKey = "palladium.appAppearanceMode"
    static let packageVersionsTextDefaultsKey = "palladium.packageVersionsText"
    static let defaultLinkHistoryLimit = 10
    static let maxLinkHistoryLimit = 50

    @Environment(\.scenePhase) var scenePhase
    @State var isRunning = false
    @State var statusText = "idle"
    @State var urlText: String
    @State var progressText = String(localized: "download.prompt.idle")
    @State var downloadErrorText: String?
    @State var selectedPreset: DownloadPreset
    @State var customArgsText: String
    @State var extraArgsText: String
    @State var afterDownloadBehavior: AfterDownloadBehavior
    @State var notificationsEnabled: Bool
    @State var rememberSelectedPreset: Bool
    @State var autoDownloadOnPaste: Bool
    @State var shareSheetDownloadMode: ShareSheetDownloadMode
    @State var downloadPlaylist: Bool
    @State var downloadSubtitles: Bool
    @State var embedThumbnail: Bool
    @State var detailedProgressEnabled: Bool
    @State var subtitleLanguagePattern: String
    @State var customSubtitleLanguagePattern: String
    @State var useCookies: Bool
    @State var selectedCookieFileName: String
    @State var importedCookieFiles: [ImportedCookieFile]
    @State var linkHistoryEnabled: Bool
    @State var linkHistoryLimit: Int
    @State var linkHistoryEntries: [LinkHistoryEntry]
    @State var appAppearanceMode: AppAppearanceMode
    @State var selectedTab: AppTab = .download
    @State var packageStatusText = "idle"
    @State var versionsText: String
    @State var packageUpdatesAvailable = false
    @State var packageUpdatesSummaryText = String(localized: "packages.summary.idle")
    @State var availablePackageVersions: [String: [String]] = [:]
    @State var isLoadingPackageVersions = false
    @State var isPackageRunning = false
    @State var hasLoadedPackageStatus = false
    @State var storageSummary: StorageManagementSummary = .empty
    @StateObject var consoleLogStore: ConsoleLogStore
    @State var completedDownloadResult: CompletedDownloadResult?
    @State var completedPhotosCompatibility: PhotosCompatibilityState = .checking
    @State var showDownloadActionSheet = false
    @State var alertMessage: String?
    @State var showAlert = false
    @State var reopenDownloadActionAfterAlert = false
    @State var toastMessage: String?
    @State var showToastMessage = false
    @State var sharePayload: SharePayload?
    @State var currentDownloadTask: Task<Void, Never>?
    @State var currentPackageTask: Task<Void, Never>?
    @State var cancelMarkerURL: URL?
    @State var downloadCancelRequested = false
    @State var lastDownloadProgressPercent: Double?
    @State var ffmpegProgressDurationSeconds: Double?
    @State var pendingDownloadProgressLine = ""
    @State var isInstallingPackagesDuringDownload = false
    @State var pendingConsoleChunks = ""
    @State var isConsoleFlushScheduled = false
    @State var keyboardDismissTapInstalled = false
    @State var showShareSheetDownloadPicker = false
    @State var shareSheetURL = ""

    init() {
        let rememberPreset = Self.loadRememberSelectedPreset()
        _urlText = State(initialValue: Self.isDebuggerAttached() ? "https://www.youtube.com/watch?v=jNQXAC9IVRw" : "")
        _selectedPreset = State(initialValue: Self.loadSelectedPreset(rememberSelection: rememberPreset))
        _customArgsText = State(initialValue: Self.loadCustomArgs())
        _extraArgsText = State(initialValue: Self.loadExtraArgs())
        _afterDownloadBehavior = State(initialValue: Self.loadAfterDownloadBehavior())
        _notificationsEnabled = State(initialValue: Self.loadNotificationsEnabled())
        _rememberSelectedPreset = State(initialValue: rememberPreset)
        _autoDownloadOnPaste = State(initialValue: Self.loadAutoDownloadOnPaste())
        _shareSheetDownloadMode = State(initialValue: Self.loadShareSheetDownloadMode())
        _downloadPlaylist = State(initialValue: Self.loadDownloadPlaylist())
        _downloadSubtitles = State(initialValue: Self.loadDownloadSubtitles())
        _embedThumbnail = State(initialValue: Self.loadEmbedThumbnail())
        _detailedProgressEnabled = State(initialValue: Self.loadDetailedProgressEnabled())
        _subtitleLanguagePattern = State(initialValue: Self.loadSubtitleLanguagePattern())
        _customSubtitleLanguagePattern = State(initialValue: Self.loadCustomSubtitleLanguagePattern())
        _useCookies = State(initialValue: Self.loadUseCookies())
        _selectedCookieFileName = State(initialValue: Self.loadSelectedCookieFileName())
        _importedCookieFiles = State(initialValue: [])
        _linkHistoryEnabled = State(initialValue: Self.loadLinkHistoryEnabled())
        let linkHistoryLimit = Self.loadLinkHistoryLimit()
        _linkHistoryLimit = State(initialValue: linkHistoryLimit)
        _linkHistoryEntries = State(initialValue: Self.loadLinkHistoryEntries(limit: linkHistoryLimit))
        _appAppearanceMode = State(initialValue: Self.loadAppAppearanceMode())
        _versionsText = State(initialValue: Self.loadCachedPackageVersionsText())
        _consoleLogStore = StateObject(wrappedValue: ConsoleLogStore())
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                DownloadTabView(
                    statusText: $statusText,
                    urlText: $urlText,
                    selectedPreset: $selectedPreset,
                    downloadPlaylist: $downloadPlaylist,
                    downloadSubtitles: $downloadSubtitles,
                    embedThumbnail: $embedThumbnail,
                    subtitleLanguagePattern: $subtitleLanguagePattern,
                    customSubtitleLanguagePattern: $customSubtitleLanguagePattern,
                    useCookies: $useCookies,
                    selectedCookieFileName: $selectedCookieFileName,
                    importedCookieFiles: importedCookieFiles,
                    isRunning: isRunning,
                    progressText: progressText,
                    downloadErrorText: downloadErrorText,
                    onDownload: { runDownloadFlow() },
                    onCancel: cancelDownloadFlow,
                    onPastedURL: handlePastedURL,
                    linkHistoryEnabled: linkHistoryEnabled,
                    historyEntries: linkHistoryEntries,
                    onSelectHistoryEntry: handleHistoryEntrySelection,
                    onDeleteHistoryEntry: removeHistoryEntry,
                    onCopyHistoryLink: copyHistoryLink
                )
                .tabItem {
                    Label(String(localized: "tab.download"), systemImage: "arrow.down.circle")
                }
                .tag(AppTab.download)

                SettingsTabView(
                    customArgsText: $customArgsText,
                    extraArgsText: $extraArgsText,
                    selectedPreset: $selectedPreset,
                    afterDownloadBehavior: $afterDownloadBehavior,
                    notificationsEnabled: $notificationsEnabled,
                    rememberSelectedPreset: $rememberSelectedPreset,
                    autoDownloadOnPaste: $autoDownloadOnPaste,
                    detailedProgressEnabled: $detailedProgressEnabled,
                    shareSheetDownloadMode: $shareSheetDownloadMode,
                    linkHistoryEnabled: $linkHistoryEnabled,
                    linkHistoryLimit: $linkHistoryLimit,
                    appAppearanceMode: $appAppearanceMode,
                    selectedCookieFileName: $selectedCookieFileName,
                    importedCookieFiles: importedCookieFiles,
                    storageSummary: storageSummary,
                    packageStatusText: packageStatusText,
                    versionsText: versionsText,
                    updatesSummaryText: packageUpdatesSummaryText,
                    updatesAvailable: packageUpdatesAvailable,
                    availablePackageVersions: availablePackageVersions,
                    isLoadingPackageVersions: isLoadingPackageVersions,
                    isRunning: isRunning,
                    isPackageRunning: isPackageRunning,
                    onRefreshVersions: refreshPackageVersions,
                    onCancelPackages: cancelPackageFlow,
                    onUpdatePackages: updatePackages,
                    onCustomUpdatePackages: updatePackagesWithCustomVersions,
                    onFetchPackageVersions: fetchPackageIndexVersions,
                    onOpenPackageManager: loadPackageStatusIfNeeded,
                    onRefreshStorage: refreshStorageSummary,
                    onClearDownloadsStorage: clearTemporaryDownloadsStorage,
                    onClearSavedStorage: clearSavedDownloadsStorage,
                    onClearCacheStorage: clearYtDlpCacheStorage,
                    onPruneDownloadsStorage: pruneTemporaryDownloadsStorage,
                    onPruneSavedStorage: pruneSavedDownloadsStorage,
                    onPruneCacheStorage: pruneYtDlpCacheStorage,
                    onOpenStorageManager: refreshStorageSummary,
                    onRefreshCookieFiles: refreshImportedCookieFiles,
                    onImportCookieFile: importCookieFile,
                    onDeleteCookieFile: deleteImportedCookieFile
                )
                .tabItem {
                    Label(String(localized: "tab.settings"), systemImage: "slider.horizontal.3")
                }
                .tag(AppTab.settings)

                ConsoleTabView(logStore: consoleLogStore)
                    .tabItem {
                        Label(String(localized: "tab.console"), systemImage: "terminal")
                    }
                    .tag(AppTab.console)
            }

            if showToastMessage, let toastMessage {
                Text(toastMessage)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 18)
                    .transition(.opacity)
            }
        }
        .onChange(of: selectedPreset, initial: false) {
            persistPreferences()
        }
        .onChange(of: rememberSelectedPreset, initial: false) { _, isEnabled in
            if !isEnabled {
                UserDefaults.standard.removeObject(forKey: Self.presetDefaultsKey)
            }
            persistPreferences()
        }
        .onChange(of: customArgsText, initial: false) {
            persistPreferences()
        }
        .onChange(of: extraArgsText, initial: false) {
            persistPreferences()
        }
        .onChange(of: afterDownloadBehavior, initial: false) {
            persistPreferences()
        }
        .onChange(of: notificationsEnabled, initial: false) {
            persistPreferences()
            debugNotification("setting changed notificationsEnabled=\(notificationsEnabled)")
            if notificationsEnabled {
                requestNotificationAuthorizationIfNeeded()
            }
        }
        .onChange(of: autoDownloadOnPaste, initial: false) {
            persistPreferences()
        }
        .onChange(of: detailedProgressEnabled, initial: false) {
            persistPreferences()
        }
        .onChange(of: shareSheetDownloadMode, initial: false) {
            persistPreferences()
        }
        .onChange(of: downloadPlaylist, initial: false) {
            persistPreferences()
        }
        .onChange(of: downloadSubtitles, initial: false) {
            persistPreferences()
        }
        .onChange(of: embedThumbnail, initial: false) {
            persistPreferences()
        }
        .onChange(of: subtitleLanguagePattern, initial: false) {
            persistPreferences()
        }
        .onChange(of: customSubtitleLanguagePattern, initial: false) {
            persistPreferences()
        }
        .onChange(of: useCookies, initial: false) {
            persistPreferences()
        }
        .onChange(of: selectedCookieFileName, initial: false) {
            persistPreferences()
        }
        .onChange(of: linkHistoryEnabled, initial: false) {
            persistPreferences()
        }
        .onChange(of: linkHistoryLimit, initial: false) {
            trimLinkHistoryEntriesIfNeeded()
            persistPreferences()
        }
        .onChange(of: appAppearanceMode, initial: false) {
            persistPreferences()
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.activityItems)
        }
        .sheet(isPresented: $showShareSheetDownloadPicker) {
            shareSheetModePickerSheet
        }
        .sheet(isPresented: $showDownloadActionSheet) {
            downloadCompleteActionSheet
                .interactiveDismissDisabled(true)
        }
        .alert(String(localized: "common.result"), isPresented: $showAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {
                if reopenDownloadActionAfterAlert, completedDownloadResult != nil {
                    reopenDownloadActionAfterAlert = false
                    showDownloadActionSheet = true
                } else {
                    reopenDownloadActionAfterAlert = false
                }
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            installKeyboardDismissTapIfNeeded()
            refreshImportedCookieFiles()
        }
        .onOpenURL { incomingURL in
            handleIncomingDownloadURL(incomingURL)
        }
        .preferredColorScheme(appAppearanceMode.preferredColorScheme)
    }
}

#Preview {
    ContentView()
}
