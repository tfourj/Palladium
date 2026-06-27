import SwiftUI

struct DownloadOptionsOrderSettingsView: View {
    @Binding var settings: [DownloadPresetSetting]

    let isRunning: Bool

    private var visibleCount: Int {
        settings.filter { $0.isVisible }.count
    }

    var body: some View {
        List {
            Section {
                ForEach($settings) { $setting in
                    Toggle(isOn: $setting.isVisible) {
                        Text(setting.preset.title)
                    }
                    .disabled(isRunning || (setting.isVisible && visibleCount <= 1))
                }
                .onMove { indices, newOffset in
                    settings.move(fromOffsets: indices, toOffset: newOffset)
                }
            } footer: {
                Text("settings.download_modes.customize_options.footer")
            }
        }
        .environment(\.editMode, .constant(isRunning ? .inactive : .active))
        .navigationTitle("settings.download_modes.customize_options.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
