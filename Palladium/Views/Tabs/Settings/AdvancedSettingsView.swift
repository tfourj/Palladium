import SwiftUI

struct AdvancedSettingsView: View {
    @Binding var disableWebKitJSIPatch: Bool
    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Toggle("settings.advanced.disable_webkit_jsi_patch", isOn: $disableWebKitJSIPatch)
                    .disabled(isRunning)
            } footer: {
                Text("settings.advanced.disable_webkit_jsi_patch.help")
            }
        }
        .navigationTitle("settings.advanced.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
