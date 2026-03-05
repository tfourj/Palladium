import SwiftUI

struct SettingsTabView: View {
    private enum SettingsRoute: Hashable {
        case downloadArguments
        case afterDownload
        case notifications
        case packages
        case about
    }

    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction
    @Binding var notificationsEnabled: Bool

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
                Section(header: Text("Download")) {
                    NavigationLink(value: SettingsRoute.downloadArguments) {
                        settingsRow(
                            title: "Download Arguments",
                            subtitle: "Custom and global yt-dlp args",
                            icon: "slider.horizontal.3",
                            color: .blue
                        )
                    }

                    NavigationLink(value: SettingsRoute.afterDownload) {
                        settingsRow(
                            title: "After Download",
                            subtitle: "What to do when a download finishes",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                    }

                    NavigationLink(value: SettingsRoute.notifications) {
                        settingsRow(
                            title: "Notifications",
                            subtitle: "Download completion alerts",
                            icon: "bell.badge.fill",
                            color: .orange
                        )
                    }
                }

                Section(header: Text("Packages")) {
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
                case .downloadArguments:
                    DownloadArgumentsSettingsView(
                        customArgsText: $customArgsText,
                        extraArgsText: $extraArgsText,
                        isRunning: isRunning
                    )
                case .afterDownload:
                    AfterDownloadSettingsView(
                        askUserAfterDownload: $askUserAfterDownload,
                        selectedPostDownloadAction: $selectedPostDownloadAction,
                        isRunning: isRunning
                    )
                case .notifications:
                    NotificationsSettingsView(
                        notificationsEnabled: $notificationsEnabled,
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
