import SwiftUI

struct DownloadBehaviorSettingsView: View {
    @Binding var autoDownloadOnPaste: Bool
    @Binding var autoRetryFailedDownloads: Bool
    @Binding var saveIncompleteDownloadsToHistory: Bool
    @Binding var detailedProgressEnabled: Bool
    @Binding var backgroundDownloadsEnabled: Bool

    let isRunning: Bool

    @StateObject private var patchedIPABuilder = PatchedIPABuilder()
    @State private var sharePayload: SharePayload?

    var body: some View {
        Form {
            Section {
                Toggle("settings.ui.paste.auto_download", isOn: $autoDownloadOnPaste)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.paste.section")
            } footer: {
                Text("settings.ui.paste.help")
            }

            Section {
                Toggle("settings.ui.retry_failed.toggle", isOn: $autoRetryFailedDownloads)
                    .disabled(isRunning)
            } header: {
                Text("settings.download_behavior.retry_section")
            } footer: {
                Text("settings.ui.retry_failed.help")
            }

            Section {
                Toggle(
                    "settings.download_behavior.incomplete_history.toggle",
                    isOn: $saveIncompleteDownloadsToHistory
                )
                .disabled(isRunning)
            } header: {
                Text("settings.ui.history.section")
            } footer: {
                Text("settings.download_behavior.incomplete_history.help")
            }

            Section {
                Toggle("settings.ui.progress.verbose", isOn: $detailedProgressEnabled)
                    .disabled(isRunning)
            } header: {
                Text("settings.ui.progress.section")
            } footer: {
                Text("settings.ui.progress.help")
            }

            Section {
                Toggle(isOn: $backgroundDownloadsEnabled) {
                    HStack(spacing: 6) {
                        Text("settings.download_behavior.background.toggle")
                        backgroundStatusIcon
                    }
                }
                .disabled(isRunning || !BackgroundDownloadTask.isSupported)

                if showsPatchInstructions {
                    LabeledContent("settings.download_behavior.background.bundle_id") {
                        Text(BackgroundDownloadTask.bundleIdentifier)
                            .textSelection(.enabled)
                    }
                    Button(action: createPatchedIPA) {
                        createPatchedIPALabel
                    }
                    .disabled(patchedIPABuilder.isBusy)
                    Button("settings.download_behavior.background.copy_bundle_id") {
                        UIPasteboard.general.string = BackgroundDownloadTask.bundleIdentifier
                    }
                    Link("settings.download_behavior.background.open_patcher", destination: Self.patcherURL)
                }
            } header: {
                Text("settings.download_behavior.background_section")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.download_behavior.background.help")
                    if showsPatchInstructions {
                        Text("settings.download_behavior.background.patch_help")
                    }
                    if case let .failed(message) = patchedIPABuilder.state {
                        Text(patchFailedText(message))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("settings.download_behavior.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.activityItems)
        }
    }

    private static let patcherURL = URL(string: "https://getpalladium.app/patcher")!

    private var backgroundDownloadsWork: Bool {
        BackgroundDownloadTask.isSupported && BackgroundDownloadTask.isPermittedOnThisInstall
    }

    /// Only installs whose bundle identifier was changed can be fixed by patching the IPA.
    private var showsPatchInstructions: Bool {
        BackgroundDownloadTask.isSupported && !BackgroundDownloadTask.isPermittedOnThisInstall
    }

    @ViewBuilder
    private var createPatchedIPALabel: some View {
        switch patchedIPABuilder.state {
        case let .downloading(version, fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text(patchDownloadingText(version))
                ProgressView(value: fraction)
            }
        case .fetchingRelease:
            HStack {
                Text("settings.download_behavior.background.patch.create")
                Spacer()
                ProgressView()
            }
        case .patching:
            HStack {
                Text("settings.download_behavior.background.patch.patching")
                Spacer()
                ProgressView()
            }
        case .idle, .failed:
            Text("settings.download_behavior.background.patch.create")
        }
    }

    private func patchDownloadingText(_ version: String) -> String {
        let format = String(localized: "settings.download_behavior.background.patch.downloading", bundle: .app)
        return String(format: format, version)
    }

    private func patchFailedText(_ message: String) -> String {
        let format = String(localized: "settings.download_behavior.background.patch.failed", bundle: .app)
        return String(format: format, message)
    }

    private func createPatchedIPA() {
        Task {
            if let url = await patchedIPABuilder.build() {
                sharePayload = SharePayload(activityItems: [url])
            }
        }
    }

    private var backgroundStatusIcon: some View {
        Image(systemName: backgroundDownloadsWork ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(backgroundDownloadsWork ? .green : .red)
            .accessibilityLabel(
                backgroundDownloadsWork
                    ? Text("settings.download_behavior.background.status.available")
                    : Text("settings.download_behavior.background.status.unavailable")
            )
    }
}
