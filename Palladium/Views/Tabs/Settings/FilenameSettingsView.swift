import SwiftUI

struct FilenameSettingsView: View {
    @Binding var filenameExportPreset: FilenameExportPreset
    @Binding var customFilenameTemplate: String
    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Picker("download.filename.picker", selection: $filenameExportPreset) {
                    Text("download.filename.default").tag(FilenameExportPreset.default)
                    Text("download.filename.video_id").tag(FilenameExportPreset.videoID)
                    Text("download.filename.custom").tag(FilenameExportPreset.custom)
                }
                .disabled(isRunning)

                if filenameExportPreset == .custom {
                    TextField(
                        "download.filename.custom.placeholder",
                        text: $customFilenameTemplate,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isRunning)

                    Text("download.filename.custom.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("download.filename.help")
            }
        }
        .navigationTitle("settings.filename.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
