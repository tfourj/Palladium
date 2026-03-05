import SwiftUI

struct AfterDownloadSettingsView: View {
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
