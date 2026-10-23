import SwiftUI

struct DownloadBehaviorSettingsView: View {
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoPasteLinkEnabled: Bool
    @Binding var autoPasteDownloadMode: ShareSheetDownloadMode
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var saveIncompleteDownloadsToHistory: Bool
    @Binding var detailedProgressEnabled: Bool

    let downloadPresetSettings: [DownloadPresetSetting]
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
                Toggle("settings.download_behavior.auto_paste.toggle", isOn: $autoPasteLinkEnabled)
                    .disabled(isRunning)

                if autoPasteLinkEnabled {
                    Picker("settings.download_behavior.auto_paste.mode", selection: $autoPasteDownloadMode) {
                        ForEach(DownloadOptions.visibleShareSheetModes(from: downloadPresetSettings)) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunning)
                }
            } header: {
                Text("settings.download_behavior.auto_paste.section")
            } footer: {
                Text("settings.download_behavior.auto_paste.help")
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
