import SwiftUI

struct UseInterfaceSettingsView: View {
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

    let isRunning: Bool
    private let historyLimitRange = 0...ContentView.maxLinkHistoryLimit

    var body: some View {
        Form {
            Section {
                Picker("settings.ui.modes.normal", selection: $selectedPreset) {
                    ForEach(DownloadPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Picker("settings.ui.modes.share_sheet", selection: $shareSheetDownloadMode) {
                    ForEach(ShareSheetDownloadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Toggle("settings.ui.modes.remember", isOn: $rememberSelectedPreset)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.modes.section")
            } footer: {
                Text("settings.ui.modes.help")
            }

            Section {
                Picker("settings.ui.after_download.picker", selection: $afterDownloadBehavior) {
                    ForEach(AfterDownloadBehavior.allCases) { behavior in
                        Label(behavior.title, systemImage: behavior.icon).tag(behavior)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("settings.ui.after_download.title")
            } footer: {
                Text("settings.ui.after_download.help")
            }

            Section {
                Picker("settings.ui.appearance.picker", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("settings.ui.appearance.section")
            } footer: {
                Text("settings.ui.appearance.help")
            }

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

                Toggle("settings.ui.progress.verbose", isOn: $detailedProgressEnabled)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.progress.section")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings.ui.retry_failed.help")
                    Text("settings.ui.progress.help")
                }
            }

            Section {
                Toggle("settings.ui.history.enable", isOn: $linkHistoryEnabled)
                    .disabled(isRunning)

                Picker("settings.ui.history.limit", selection: $linkHistoryLimit) {
                    ForEach(historyLimitRange, id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning || !linkHistoryEnabled)
            } header: {
                Text("settings.ui.history.section")
            } footer: {
                Text("settings.ui.history.help")
            }

            Section("settings.notifications.title") {
                Toggle("settings.notifications.toggle", isOn: $notificationsEnabled)
                    .disabled(isRunning)
            }
        }
        .navigationTitle("settings.ui.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
