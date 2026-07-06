import SwiftUI

struct AdvancedSettingsView: View {
    @Binding var youtubePatchMode: YouTubePatchMode
    let isRunning: Bool
    let onReinstallPackages: () -> Void

    @State private var showReinstallPrompt = false

    var body: some View {
        Form {
            Section {
                Picker("settings.advanced.youtube_patch_mode", selection: $youtubePatchMode) {
                    ForEach(YouTubePatchMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .disabled(isRunning)
                .onChange(of: youtubePatchMode) {
                    showReinstallPrompt = true
                }
            } footer: {
                Text("settings.advanced.youtube_patch_mode.help")
            }
        }
        .navigationTitle("settings.advanced.title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("settings.advanced.reinstall_prompt.title", isPresented: $showReinstallPrompt) {
            Button("common.cancel", role: .cancel) {}
            Button("settings.advanced.reinstall") {
                onReinstallPackages()
            }
        } message: {
            Text("settings.advanced.reinstall_prompt.message")
        }
    }
}
