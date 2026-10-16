import SwiftUI

struct DownloadBehaviorSettingsView: View {
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var saveIncompleteDownloadsToHistory: Bool
    @Binding var detailedProgressEnabled: Bool
    @Binding var backgroundDownloadsEnabled: Bool

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Toggle("settings.ui.paste.auto_download", isOn: $autoDownloadOnPaste)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.paste.section")
            } footer: {
                Text("settings.ui.paste.help")
            }

            Section {
                Toggle("settings.ui.retry_failed.toggle", isOn: $autoRetryFailedDownloads)
                    .disabled(isRunning)
            } header: {
                Text("settings.download_behavior.retry_section")
            } footer: {
                Text("settings.ui.retry_failed.help")
            }

            Section {
                Toggle(
                    "settings.download_behavior.incomplete_history.toggle",
                    isOn: $saveIncompleteDownloadsToHistory
                )
                .disabled(isRunning)
            } header: {
                Text("settings.ui.history.section")
            } footer: {
                Text("settings.download_behavior.incomplete_history.help")
            }

            Section {
                Toggle("settings.ui.progress.verbose", isOn: $detailedProgressEnabled)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.progress.section")
            } footer: {
                Text("settings.ui.progress.help")
            }

            Section {
                Toggle(isOn: $backgroundDownloadsEnabled) {
                    HStack(spacing: 6) {
                        Text("settings.download_behavior.background.toggle")
                        backgroundStatusIcon
                    }
                }
                .disabled(isRunning || !BackgroundDownloadTask.isSupported)

                if showsPatchInstructions {
                    LabeledContent("settings.download_behavior.background.bundle_id") {
                        Text(BackgroundDownloadTask.bundleIdentifier)
                            .textSelection(.enabled)
                    }
                    Button("settings.download_behavior.background.copy_bundle_id") {
                        UIPasteboard.general.string = BackgroundDownloadTask.bundleIdentifier
                    }
                    Link("settings.download_behavior.background.open_patcher", destination: Self.patcherURL)
                }
            } header: {
                Text("settings.download_behavior.background_section")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.download_behavior.background.help")
                    if showsPatchInstructions {
                        Text("settings.download_behavior.background.patch_help")
                    }
                }
            }
        }
        .navigationTitle("settings.download_behavior.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let patcherURL = URL(string: "https://getpalladium.app/patcher")!

    private var backgroundDownloadsWork: Bool {
        BackgroundDownloadTask.isSupported && BackgroundDownloadTask.isPermittedOnThisInstall
    }

    /// Only installs whose bundle identifier was changed can be fixed by patching the IPA.
    private var showsPatchInstructions: Bool {
        BackgroundDownloadTask.isSupported && !BackgroundDownloadTask.isPermittedOnThisInstall
    }

    private var backgroundStatusIcon: some View {
        Image(systemName: backgroundDownloadsWork ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(backgroundDownloadsWork ? .green : .red)
            .accessibilityLabel(
                backgroundDownloadsWork
                    ? Text("settings.download_behavior.background.status.available")
                    : Text("settings.download_behavior.background.status.unavailable")
            )
    }
}
