import SwiftUI

struct DownloadArgumentsSettingsView: View {
    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    let isRunning: Bool

    var body: some View {
        Form {
            Section("download.args.custom.title") {
                TextField("downloadargs.custom", text: $customArgsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isRunning)

                Text("download.args.custom.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("download.args.global.title") {
                TextField("downloadargs.global", text: $extraArgsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isRunning)

                Text("download.args.global.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("download.args.examples") {
                HStack {
                    exampleButton(String(localized: "download.args.example.mp4"), value: DownloadPreset.autoVideo.defaultArguments)
                    exampleButton(String(localized: "download.args.example.mp3"), value: DownloadPreset.audio.defaultArguments)
                    exampleButton(String(localized: "download.args.example.mute"), value: DownloadPreset.mute.defaultArguments)
                }
            }
        }
        .navigationTitle("settings.download_args.title")
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
