import SwiftUI

struct DownloadOptionsSettingsView: View {
    @Binding var defaultDownloadPlaylist: Bool
    @Binding var defaultDownloadSubtitles: Bool
    @Binding var defaultEmbedThumbnail: Bool
    @Binding var defaultUseCookies: Bool
    @Binding var restoreDownloadDefaults: Bool

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Toggle("settings.download_defaults.playlist.default", isOn: $defaultDownloadPlaylist)
                    .disabled(isRunning)

                Toggle("settings.download_defaults.subtitles.default", isOn: $defaultDownloadSubtitles)
                    .disabled(isRunning)

                Toggle("settings.download_defaults.thumbnail.default", isOn: $defaultEmbedThumbnail)
                    .disabled(isRunning)

                Toggle("settings.download_defaults.cookies.default", isOn: $defaultUseCookies)
                    .disabled(isRunning)
            } header: {
                Text("settings.download_defaults.defaults.section")
            }

            Section {
                Toggle("settings.download_defaults.restore", isOn: $restoreDownloadDefaults)
                    .disabled(isRunning)
            } header: {
                Text("settings.download_defaults.restore.section")
            } footer: {
                Text("settings.download_defaults.restore.help")
            }
        }
        .navigationTitle("settings.download_defaults.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
