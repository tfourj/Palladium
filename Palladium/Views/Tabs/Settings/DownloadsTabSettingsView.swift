import SwiftUI

struct DownloadsTabSettingsView: View {
    @Binding var showTemporaryDownloads: Bool

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Toggle("settings.ui.downloads.show_temp", isOn: $showTemporaryDownloads)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.downloads.section")
            } footer: {
                Text("settings.ui.downloads.help")
            }
        }
        .navigationTitle("settings.downloads_tab.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
