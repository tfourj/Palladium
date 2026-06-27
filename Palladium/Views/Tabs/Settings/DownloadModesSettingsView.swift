import SwiftUI

struct DownloadModesSettingsView: View {
    @Binding var selectedPreset: DownloadPreset
    @Binding var rememberSelectedPreset: Bool
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var downloadPresetSettings: [DownloadPresetSetting]

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Picker("settings.ui.modes.normal", selection: $selectedPreset) {
                    ForEach(DownloadOptions.visiblePresets(from: downloadPresetSettings)) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)

                Toggle("settings.ui.modes.remember", isOn: $rememberSelectedPreset)
                    .disabled(isRunning)

                NavigationLink {
                    DownloadOptionsOrderSettingsView(
                        settings: $downloadPresetSettings,
                        isRunning: isRunning
                    )
                } label: {
                    Text("settings.download_modes.customize_options")
                }
            } header: {
                Text("settings.download_modes.main_section")
            } footer: {
                Text("settings.download_modes.main_help")
            }

            Section {
                Picker("settings.ui.modes.share_sheet", selection: $shareSheetDownloadMode) {
                    ForEach(DownloadOptions.visibleShareSheetModes(from: downloadPresetSettings)) { mode in
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
