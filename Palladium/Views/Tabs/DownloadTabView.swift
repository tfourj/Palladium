import SwiftUI

struct DownloadTabView: View {
    @Binding var statusText: String
    @Binding var urlText: String
    @Binding var selectedPreset: DownloadPreset

    let isRunning: Bool
    let progressText: String
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Palladium")
                .font(.title2.bold())

            Text("status: \(statusText)")
                .font(.subheadline.monospaced())

            TextField("https://example.com/video", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Picker("Preset", selection: $selectedPreset) {
                ForEach(DownloadPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)

            Button(action: onDownload) {
                Text(isRunning ? "Running..." : "Download")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Downloading...")
                        .font(.footnote)
                }
            }

            Text(progressText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 0)
        }
        .padding()
    }
}
