import SwiftUI

struct AppearanceSettingsView: View {
    @Binding var appAppearanceMode: AppAppearanceMode

    let isRunning: Bool

    var body: some View {
        Form {
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
        }
        .navigationTitle("settings.ui.appearance.section")
        .navigationBarTitleDisplayMode(.inline)
    }
}
