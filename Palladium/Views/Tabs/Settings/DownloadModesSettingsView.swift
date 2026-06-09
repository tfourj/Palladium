import SwiftUI

struct DownloadModesSettingsView: View {
    @Binding var selectedPreset: DownloadPreset
    @Binding var rememberSelectedPreset: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode

    let isRunning: Bool

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

                Toggle("settings.ui.modes.remember", isOn: $rememberSelectedPreset)
                    .disabled(isRunning)
            } header: {
                Text("settings.download_modes.main_section")
            } footer: {
                Text("settings.download_modes.main_help")
            }

            Section {
                Picker("settings.ui.modes.share_sheet", selection: $shareSheetDownloadMode) {
                    ForEach(ShareSheetDownloadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("settings.download_modes.share_section")
            } footer: {
                Text("settings.download_modes.share_help")
            }
        }
        .navigationTitle("settings.download_modes.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
