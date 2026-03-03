import SwiftUI

struct SettingsTabView: View {
    @Binding var customArgsText: String
    @Binding var extraArgsText: String
    @Binding var askUserAfterDownload: Bool
    @Binding var selectedPostDownloadAction: PostDownloadAction

    let isRunning: Bool

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("General")) {
                    NavigationLink {
                        DownloadArgumentsSettingsView(
                            customArgsText: $customArgsText,
                            extraArgsText: $extraArgsText,
                            isRunning: isRunning
                        )
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Download Arguments")
                        }
                    }

                    NavigationLink {
                        AfterDownloadSettingsView(
                            askUserAfterDownload: $askUserAfterDownload,
                            selectedPostDownloadAction: $selectedPostDownloadAction,
                            isRunning: isRunning
                        )
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text("After Download")
                        }
                    }

                    NavigationLink {
                        SettingsAboutView()
                    } label: {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("About")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
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
