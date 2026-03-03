import SwiftUI

struct SettingsTabView: View {
    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var selectedPreset: DownloadPreset

    let isRunning: Bool

    var body: some View {
        Form {
            Section("Custom preset args") {
                TextField("--format best --no-playlist", text: $customArgsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isRunning)

                Text("Used only when Preset is Custom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Extra args for all presets") {
                TextField("--embed-subs --write-subs", text: $extraArgsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isRunning)

                Text("Appended for every run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preset examples") {
                Text("Tap to copy into Custom preset args:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    exampleButton("mp4", value: "--merge-output-format mp4 --remux-video mp4 -S vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac")
                    exampleButton("mp3", value: "-f ba[acodec^=mp3]/ba/b -x --audio-format mp3")
                    exampleButton("aac", value: "-f ba[acodec^=aac]/ba[acodec^=mp4a.40.]/ba/b -x --audio-format aac")
                }
            }
        }
    }

    private func exampleButton(_ title: String, value: String) -> some View {
        Button(title) {
            customArgsText = value
            selectedPreset = .custom
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .disabled(isRunning)
    }
}
