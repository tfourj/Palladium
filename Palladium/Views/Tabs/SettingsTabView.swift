import SwiftUI

struct SettingsTabView: View {
    @Binding var settings: DownloadSettings
    let isRunning: Bool

    var body: some View {
        Form {
            Section("Export") {
                Picker("Container", selection: $settings.container) {
                    ForEach(DownloadContainer.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)

                Picker("Max resolution", selection: $settings.maxResolution) {
                    ForEach(DownloadMaxResolution.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)

                Picker("Audio format", selection: $settings.audioFormat) {
                    ForEach(AudioFormatOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)

                Picker("Audio quality", selection: $settings.audioQuality) {
                    ForEach(AudioQualityOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(isRunning)
            }

            Section("Behavior") {
                Toggle("Single video only (--no-playlist)", isOn: $settings.noPlaylist)
                    .disabled(isRunning)
                Toggle("Embed subtitles when available", isOn: $settings.embedSubtitles)
                    .disabled(isRunning)
            }
        }
    }
}
