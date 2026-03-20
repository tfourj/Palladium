import SwiftUI

struct UseInterfaceSettingsView: View {
    @Binding var selectedPreset: DownloadPreset
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var linkHistoryEnabled: Bool
    @Binding var appAppearanceMode: AppAppearanceMode

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Picker("Normal download mode", selection: $selectedPreset) {
                    ForEach(DownloadPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Picker("Share sheet mode", selection: $shareSheetDownloadMode) {
                    ForEach(ShareSheetDownloadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Toggle("Remember picker options", isOn: $rememberSelectedPreset)
                    .disabled(isRunning)
            } header: {
                Text("Download Modes")
            } footer: {
                Text("Normal download mode matches the main picker on the Download tab. If memory is off, it resets to Video when the app launches.")
            }

            Section {
                Picker("After download", selection: $afterDownloadBehavior) {
                    ForEach(AfterDownloadBehavior.allCases) { behavior in
                        Label(behavior.title, systemImage: behavior.icon).tag(behavior)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("After Download")
            } footer: {
                Text("Ask shows the same action picker after each successful download. Other options run automatically.")
            }

            Section {
                Picker("App theme", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System uses the phone setting by default.")
            }

            Section {
                Toggle("Auto download on paste", isOn: $autoDownloadOnPaste)
                    .disabled(isRunning)
            } header: {
                Text("Paste")
            } footer: {
                Text("Starts download immediately after pasting a URL from the Download tab.")
            }

            Section {
                Toggle("Enable link history", isOn: $linkHistoryEnabled)
                    .disabled(isRunning)
            } header: {
                Text("History")
            } footer: {
                Text("Stores up to 10 recent links with mode and title.")
            }

            Section("Notifications") {
                Toggle("Notify when downloads finish in background", isOn: $notificationsEnabled)
                    .disabled(isRunning)
            }
        }
        .navigationTitle("User Interface")
        .navigationBarTitleDisplayMode(.inline)
    }
}
