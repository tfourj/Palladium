import SwiftUI

struct DownloadBehaviorSettingsView: View {
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var saveIncompleteDownloadsToHistory: Bool
    @Binding var detailedProgressEnabled: Bool

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
        }
        .navigationTitle("settings.download_behavior.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
