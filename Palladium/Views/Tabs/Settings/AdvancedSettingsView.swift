import SwiftUI

struct AdvancedSettingsView: View {
    @Binding var disableWebKitJSIPatch: Bool
    let isRunning: Bool
    let onReinstallPackages: () -> Void

    @State private var showReinstallPrompt = false

    var body: some View {
        Form {
            Section {
                Toggle("settings.advanced.disable_webkit_jsi_patch", isOn: $disableWebKitJSIPatch)
                    .disabled(isRunning)
                    .onChange(of: disableWebKitJSIPatch) {
                        showReinstallPrompt = true
                    }
            } footer: {
                Text("settings.advanced.disable_webkit_jsi_patch.help")
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
