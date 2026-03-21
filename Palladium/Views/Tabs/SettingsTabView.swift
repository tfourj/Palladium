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
                Section(header: Text("General")) {
                    NavigationLink(value: SettingsRoute.useInterface) {
                        settingsRow(
                            title: "User Interface",
                            subtitle: "Download behavior and share sheet flow",
                            icon: "slider.horizontal.3",
                            color: .green
                        )
                    }

                    NavigationLink(value: SettingsRoute.downloadArguments) {
                        settingsRow(
                            title: "Download Arguments",
                            subtitle: "Custom and global yt-dlp args",
                            icon: "terminal",
                            color: .blue
                        )
                    }

                    NavigationLink(value: SettingsRoute.storage) {
                        settingsRow(
                            title: "Download Storage",
                            subtitle: "\(storageSummary.formattedTotalSize) across temp, saved, and cache",
                            icon: "internaldrive.fill",
                            color: .teal
                        )
                    }
                }

                Section(header: Text("Maintenance")) {
                    NavigationLink(value: SettingsRoute.packages) {
                        settingsRow(
                            title: "Package Manager",
                            subtitle: "Check and update yt-dlp and pip",
                            icon: "shippingbox.fill",
                            color: .indigo
                        )
                    }
                }

                Section(header: Text("About")) {
                    NavigationLink(value: SettingsRoute.about) {
                        settingsRow(
                            title: "About",
                            subtitle: "Version and quick help",
                            icon: "info.circle.fill",
                            color: .orange
                        )
                    }
                }
            }
            .navigationTitle("Settings")
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
