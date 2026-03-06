import SwiftUI

struct PackagesSettingsView: View {
    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let isRunning: Bool
    let onRefreshVersions: () -> Void
    let onUpdatePackages: () -> Void
    let onCustomUpdatePackages: (_ ytDlpVersion: String?, _ webkitJSIVersion: String?) -> Void

    @State private var showCustomVersionSheet = false
    @State private var ytDlpCustomVersion = ""
    @State private var webkitJSICustomVersion = ""

    var body: some View {
        Form {
            Section("Status") {
                Text("status: \(packageStatusText)")
                    .font(.subheadline.monospaced())

                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(packageStatusText == "updating" ? "Updating packages..." : "Checking versions...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Installed Versions") {
                Text(versionsText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Update Summary") {
                Text(updatesSummaryText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Actions") {
                Button(action: onRefreshVersions) {
                    Text(isRunning ? "Running..." : "Check for Updates")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Button {
                    guard !isRunning, updatesAvailable else { return }
                    onUpdatePackages()
                } label: {
                    Text(isRunning ? "Running..." : "Update Packages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .opacity((isRunning || !updatesAvailable) ? 0.5 : 1.0)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                        guard !isRunning else { return }
                        prepareCustomVersionEditor()
                        showCustomVersionSheet = true
                    }
                )

                Text("Long press Update Packages to set custom package versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Package Manager")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCustomVersionSheet) {
            customVersionSheet
        }
    }

    private var customVersionSheet: some View {
        NavigationStack {
            Form {
                Section("Target Versions") {
                    TextField("yt-dlp version", text: $ytDlpCustomVersion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("yt-dlp-apple-webkit-jsi version", text: $webkitJSICustomVersion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Leave a field empty to keep the latest available release for that package.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Custom Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showCustomVersionSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        let ytDlp = normalizeVersionInput(ytDlpCustomVersion)
                        let webkit = normalizeVersionInput(webkitJSICustomVersion)
                        onCustomUpdatePackages(ytDlp, webkit)
                        showCustomVersionSheet = false
                    }
                    .disabled(normalizeVersionInput(ytDlpCustomVersion) == nil &&
                              normalizeVersionInput(webkitJSICustomVersion) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func prepareCustomVersionEditor() {
        ytDlpCustomVersion = installedVersion(for: "yt-dlp") ?? ""
        webkitJSICustomVersion = installedVersion(for: "yt-dlp-apple-webkit-jsi") ?? ""
    }

    private func installedVersion(for packageName: String) -> String? {
        let prefix = "\(packageName):"
        for line in versionsText.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix(prefix.lowercased()) {
                return line.replacingOccurrences(of: prefix, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func normalizeVersionInput(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
