import SwiftUI

struct NotificationsSettingsView: View {
    @Binding var notificationsEnabled: Bool
    let isRunning: Bool

    var body: some View {
        Form {
            Section("settings.notifications.section") {
                Toggle("settings.notifications.toggle_single", isOn: $notificationsEnabled)
                    .disabled(isRunning)

                Text("settings.notifications.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.notifications.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
