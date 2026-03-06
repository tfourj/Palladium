import SwiftUI

struct SettingsTabView: View {
    private enum SettingsRoute: Hashable {
        case useInterface
        case downloadArguments
        case packages
        case about
    }

    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode

    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let isRunning: Bool
    let onRefreshVersions: () -> Void
    let onUpdatePackages: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("General")) {
                    NavigationLink(value: SettingsRoute.useInterface) {
                        settingsRow(
                            title: "User interface",
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
                }

                Section(header: Text("Maintenance")) {
                    NavigationLink(value: SettingsRoute.packages) {
                        settingsRow(
                            title: "Package Manager",
                            subtitle: "Check and update yt-dlp packages",
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
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .useInterface:
                    UseInterfaceSettingsView(
                        askUserAfterDownload: $askUserAfterDownload,
                        selectedPostDownloadAction: $selectedPostDownloadAction,
                        notificationsEnabled: $notificationsEnabled,
                        rememberSelectedPreset: $rememberSelectedPreset,
                        autoDownloadOnPaste: $autoDownloadOnPaste,
                        shareSheetDownloadMode: $shareSheetDownloadMode,
                        isRunning: isRunning
                    )
                case .downloadArguments:
                    DownloadArgumentsSettingsView(
                        customArgsText: $customArgsText,
                        extraArgsText: $extraArgsText,
                        isRunning: isRunning
                    )
                case .packages:
                    PackagesSettingsView(
                        packageStatusText: packageStatusText,
                        versionsText: versionsText,
                        updatesSummaryText: updatesSummaryText,
                        updatesAvailable: updatesAvailable,
                        isRunning: isRunning,
                        onRefreshVersions: onRefreshVersions,
                        onUpdatePackages: onUpdatePackages
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
