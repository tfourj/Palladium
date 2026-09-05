import SwiftUI

struct PostProcessingSettingsView: View {
    @AppStorage(PostProcessingPreferences.enabledKey) private var enabled = false
    @AppStorage(PostProcessingPreferences.methodKey) private var method = VideoPostProcessingMethod.recode
    @AppStorage(PostProcessingPreferences.formatKey) private var format = VideoPostProcessingFormat.mp4

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Toggle("settings.post_processing.enabled", isOn: $enabled)

                if enabled {
                    Picker("settings.post_processing.mode", selection: $method) {
                        ForEach(VideoPostProcessingMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }

                    Picker("settings.post_processing.format", selection: $format) {
                        ForEach(VideoPostProcessingFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                }
            } footer: {
                Text("settings.post_processing.scope")
            }

            Section {
                Label {
                    Text("settings.post_processing.warning")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("settings.post_processing.remux_help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isRunning)
        .navigationTitle("settings.post_processing.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
