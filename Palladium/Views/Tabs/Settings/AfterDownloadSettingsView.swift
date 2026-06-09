import SwiftUI

struct AfterDownloadSettingsView: View {
    @Binding var afterDownloadBehavior: AfterDownloadBehavior
    let isRunning: Bool

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
        }
        .navigationTitle("settings.ui.after_download.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
