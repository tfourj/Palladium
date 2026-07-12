import SwiftUI

struct ShareSheetSettingsView: View {
    @Binding var shareSheetDownloadMode: ShareSheetDownloadMode
    @Binding var showFormatButton: Bool
    @Binding var showFillURLButton: Bool

    let downloadPresetSettings: [DownloadPresetSetting]
    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Picker("settings.ui.modes.share_sheet", selection: $shareSheetDownloadMode) {
                    ForEach(DownloadOptions.visibleShareSheetModes(from: downloadPresetSettings)) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isRunning)
            } header: {
                Text("settings.share_sheet.mode_section")
            } footer: {
                Text("settings.download_modes.share_help")
            }

            Section {
                Toggle("settings.share_sheet.show_format", isOn: $showFormatButton)
                    .disabled(isRunning)

                Toggle("settings.share_sheet.show_fill_url", isOn: $showFillURLButton)
                    .disabled(isRunning)
            } header: {
                Text("settings.share_sheet.buttons_section")
            } footer: {
                Text("settings.share_sheet.buttons_help")
            }
        }
        .navigationTitle("settings.share_sheet.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
