import SwiftUI

struct BackgroundDownloadSettingsView: View {
    @Binding var backgroundDownloadsEnabled: Bool
    @Binding var backgroundDownloadMode: BackgroundDownloadMode

    let isRunning: Bool

    @StateObject private var patchedIPABuilder = PatchedIPABuilder()
    @State private var sharePayload: SharePayload?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $backgroundDownloadsEnabled) {
                    HStack(spacing: 6) {
                        Text("settings.download_behavior.background.toggle")
                        backgroundStatusIcon
                    }
                }
                .disabled(isRunning || !BackgroundDownloadTask.isSupported(in: backgroundDownloadMode))
            } footer: {
                Text("settings.download_behavior.background.help")
            }

            Section {
                Picker("settings.download_behavior.background.mode", selection: $backgroundDownloadMode) {
                    ForEach(BackgroundDownloadMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .disabled(isRunning)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.download_behavior.background.mode.help")
                    if showsLiveContainerHint {
                        Text("settings.download_behavior.background.mode.livecontainer")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if showsPatchInstructions {
                Section {
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
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.download_behavior.background.patch_help")
                        if case let .failed(message) = patchedIPABuilder.state {
                            Text(patchFailedText(message))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.download_behavior.background.toggle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.activityItems)
        }
    }

    private static let patcherURL = URL(string: "https://getpalladium.app/patcher")!

    private var backgroundDownloadsWork: Bool {
        switch backgroundDownloadMode {
        case .silentAudio:
            return true
        case .systemTask:
            return BackgroundDownloadTask.isSupported
                && BackgroundDownloadTask.isPermittedOnThisInstall
                && !BackgroundDownloadMode.isRunningInLiveContainer
        }
    }

    /// Only installs whose bundle identifier was changed can be fixed by patching the IPA. LiveContainer installs
    /// cannot, since the system checks LiveContainer's own Info.plist.
    private var showsPatchInstructions: Bool {
        backgroundDownloadMode == .systemTask
            && BackgroundDownloadTask.isSupported
            && !BackgroundDownloadTask.isPermittedOnThisInstall
            && !BackgroundDownloadMode.isRunningInLiveContainer
    }

    private var showsLiveContainerHint: Bool {
        backgroundDownloadMode == .systemTask && BackgroundDownloadMode.isRunningInLiveContainer
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
