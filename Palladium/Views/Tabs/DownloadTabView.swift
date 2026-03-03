import SwiftUI
import UIKit

struct DownloadTabView: View {
    @Binding var statusText: String
    @Binding var urlText: String
    @Binding var selectedPreset: DownloadPreset

    let isRunning: Bool
    let progressText: String
    let onDownload: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.10, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Palladium")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("status: \(statusText)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 10)

                if isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Downloading...")
                                .font(.footnote)
                                .foregroundStyle(.white)
                        }

                        Text(progressText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                            .background(Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                VStack(spacing: 10) {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(DownloadPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRunning)

                    HStack(spacing: 8) {
                        TextField("Enter video URL", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button(action: pasteOrClearURL) {
                            Image(systemName: urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 42, height: 42)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button(action: onDownload) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(isRunning ? "Running..." : "Download")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isRunning || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.vertical, 14)
        }
    }

    private func pasteOrClearURL() {
        if urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !paste.isEmpty {
                urlText = paste
            }
            return
        }
        urlText = ""
    }
}
