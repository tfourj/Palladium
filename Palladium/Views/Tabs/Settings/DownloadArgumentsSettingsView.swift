import SwiftUI

struct DownloadArgumentsSettingsView: View {
    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    let isRunning: Bool

    var body: some View {
        Form {
            Section("Custom Preset Args") {
                TextField("--format best --no-playlist", text: $customArgsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isRunning)

                Text("Used only when Preset is Custom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global Extra Args") {
                TextField("--embed-subs --write-subs", text: $extraArgsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isRunning)

                Text("Appended for every run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Examples") {
                HStack {
                    exampleButton("mp4", value: DownloadPreset.autoVideo.defaultArguments)
                    exampleButton("mp3", value: DownloadPreset.audio.defaultArguments)
                    exampleButton("mute", value: DownloadPreset.mute.defaultArguments)
                }
            }
        }
        .navigationTitle("Download Arguments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exampleButton(_ title: String, value: String) -> some View {
        Button(title) {
            customArgsText = value
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .disabled(isRunning)
    }
}
