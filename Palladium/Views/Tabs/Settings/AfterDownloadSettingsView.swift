import SwiftUI

struct AfterDownloadSettingsView: View {
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    let isRunning: Bool
    @AppStorage("palladium.savedDownloads.alwaysUseFolder") private var alwaysUseFolder = false
    @AppStorage("palladium.savedDownloads.organizeByService") private var organizeByService = false

    var body: some View {
        Form {
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
                Toggle("settings.saved_downloads.always_folder", isOn: $alwaysUseFolder)
                    .disabled(isRunning)
                Toggle("settings.saved_downloads.organize_by_service", isOn: $organizeByService)
                    .disabled(isRunning)
            } header: {
                Text("settings.saved_downloads.title")
            } footer: {
                Text("settings.saved_downloads.help")
            }
        }
        .navigationTitle("settings.ui.after_download.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
