import SwiftUI

struct SettingsTabView: View {
    private enum SettingsRoute: Hashable {
        case useInterface
        case downloadArguments
        case storage
        case packages
        case about
    }

    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var selectedPreset: DownloadPreset
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var detailedProgressEnabled: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var linkHistoryEnabled: Bool
    @Binding var appAppearanceMode: AppAppearanceMode

    let storageSummary: StorageManagementSummary
    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let availablePackageVersions: [String: [String]]
    let isLoadingPackageVersions: Bool
    let isRunning: Bool
    let isPackageRunning: Bool
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

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("settings.general.section")) {
                    NavigationLink(value: SettingsRoute.useInterface) {
                        settingsRow(
                            title: String(localized: "settings.ui.title"),
                            subtitle: String(localized: "settings.ui.subtitle"),
                            icon: "slider.horizontal.3",
                            color: .green
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

                    NavigationLink(value: SettingsRoute.storage) {
                        settingsRow(
                            title: String(localized: "settings.storage.title"),
                            subtitle: String(format: String(localized: "settings.storage.summary.total"), storageSummary.formattedTotalSize),
                            icon: "internaldrive.fill",
                            color: .teal
                        )
                    }
                }

                Section(header: Text("settings.maintenance.section")) {
                    NavigationLink(value: SettingsRoute.packages) {
                        settingsRow(
                            title: String(localized: "settings.packages.title"),
                            subtitle: String(localized: "settings.packages.subtitle"),
                            icon: "shippingbox.fill",
                            color: .indigo
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
                case .useInterface:
                    UseInterfaceSettingsView(
                        selectedPreset: $selectedPreset,
                        afterDownloadBehavior: $afterDownloadBehavior,
                        notificationsEnabled: $notificationsEnabled,
                        rememberSelectedPreset: $rememberSelectedPreset,
                        autoDownloadOnPaste: $autoDownloadOnPaste,
                        detailedProgressEnabled: $detailedProgressEnabled,
                        shareSheetDownloadMode: $shareSheetDownloadMode,
                        linkHistoryEnabled: $linkHistoryEnabled,
                        appAppearanceMode: $appAppearanceMode,
                        isRunning: isRunning
                    )
                case .downloadArguments:
                    DownloadArgumentsSettingsView(
                        customArgsText: $customArgsText,
                        extraArgsText: $extraArgsText,
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
                case .packages:
                    PackagesSettingsView(
                        packageStatusText: packageStatusText,
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
