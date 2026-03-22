import SwiftUI

struct AfterDownloadSettingsView: View {
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction
    let isRunning: Bool

    var body: some View {
        Form {
            Section("settings.after_download.behavior") {
                Toggle("settings.after_download.ask_user", isOn: $askUserAfterDownload)
                    .disabled(isRunning)
            }

            Section("settings.after_download.default_action") {
                Picker("settings.after_download.default_picker", selection: $selectedPostDownloadAction) {
                    ForEach(PostDownloadAction.allCases) { action in
                        Label(action.title, systemImage: action.icon).tag(action)
                    }
                }
                .disabled(isRunning || askUserAfterDownload)

                Text(askUserAfterDownload
                     ? "settings.after_download.disabled_help"
                     : "settings.after_download.enabled_help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.ui.after_download.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
