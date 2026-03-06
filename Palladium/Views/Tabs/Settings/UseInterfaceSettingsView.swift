import SwiftUI

struct UseInterfaceSettingsView: View {
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction
    @Binding var notificationsEnabled: Bool
    @Binding var rememberSelectedPreset: Bool
    @Binding var autoDownloadOnPaste: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var linkHistoryEnabled: Bool

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Remember selected mode", isOn: $rememberSelectedPreset)
                    .disabled(isRunning)

                Toggle("Ask what to do after download", isOn: $askUserAfterDownload)
                    .disabled(isRunning)

                Picker("Default action when ask is off", selection: $selectedPostDownloadAction) {
                    ForEach(PostDownloadAction.allCases) { action in
                        Label(action.title, systemImage: action.icon).tag(action)
                    }
                }
                .disabled(isRunning || askUserAfterDownload)
            } header: {
                Text("Download Behavior")
            } footer: {
                Text(askUserAfterDownload
                     ? "Default action is disabled while ask mode is enabled. If mode memory is off, the app starts with Auto every launch."
                     : "Selected action runs automatically after each successful download. If mode memory is off, the app starts with Auto every launch.")
            }

            Section {
                Picker("Selected mode for share sheet", selection: $shareSheetDownloadMode) {
                    ForEach(ShareSheetDownloadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                    .disabled(isRunning)
            } header: {
                Text("Share Sheet")
            } footer: {
                Text("Ask opens a picker. Other options start downloads directly with that mode.")
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
        .navigationTitle("User interface")
        .navigationBarTitleDisplayMode(.inline)
    }
}
