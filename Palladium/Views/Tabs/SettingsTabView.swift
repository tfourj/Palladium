import SwiftUI

struct SettingsTabView: View {
    private enum SettingsRoute: Hashable {
        case downloadArguments
        case afterDownload
        case about
    }

    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction

    let isRunning: Bool

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Download")) {
                    NavigationLink(value: SettingsRoute.downloadArguments) {
                        settingsRow(
                            title: "Download Arguments",
                            subtitle: "Custom and global yt-dlp args",
                            icon: "slider.horizontal.3",
                            color: .blue
                        )
                    }

                    NavigationLink(value: SettingsRoute.afterDownload) {
                        settingsRow(
                            title: "After Download",
                            subtitle: "What to do when a download finishes",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                }

                Section(header: Text("About")) {
                    NavigationLink(value: SettingsRoute.about) {
                        settingsRow(
                            title: "About",
                            subtitle: "Version and quick help",
                            icon: "info.circle.fill",
                            color: .orange
                        )
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .downloadArguments:
                    DownloadArgumentsSettingsView(
                        customArgsText: $customArgsText,
                        extraArgsText: $extraArgsText,
                        isRunning: isRunning
                    )
                case .afterDownload:
                    AfterDownloadSettingsView(
                        askUserAfterDownload: $askUserAfterDownload,
                        selectedPostDownloadAction: $selectedPostDownloadAction,
                        isRunning: isRunning
                    )
                case .about:
                    SettingsAboutView()
                }
            }
        }
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DownloadArgumentsSettingsView: View {
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

private struct AfterDownloadSettingsView: View {
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction
    let isRunning: Bool

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Ask user what to do after download", isOn: $askUserAfterDownload)
                    .disabled(isRunning)
            }

            Section("Default Action") {
                Picker("When ask-user is off", selection: $selectedPostDownloadAction) {
                    ForEach(PostDownloadAction.allCases) { action in
                        Label(action.title, systemImage: action.icon).tag(action)
                    }
                }
                .disabled(isRunning || askUserAfterDownload)

                Text(askUserAfterDownload
                     ? "Disabled while ask-user mode is on."
                     : "This action runs automatically after each successful download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("After Download")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Palladium Settings")
                .font(.title3.bold())
            Text("Configure custom yt-dlp arguments and post-download behavior.")
                .foregroundStyle(.secondary)
            Text("Use Ask User mode to choose action per download, or disable it for an automatic default action.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
