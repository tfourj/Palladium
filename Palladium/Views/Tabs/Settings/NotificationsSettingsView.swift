import SwiftUI

struct NotificationsSettingsView: View {
    @Binding var notificationsEnabled: Bool
    let isRunning: Bool

    var body: some View {
        Form {
            Section("Download Notifications") {
                Toggle("Notify when download completes in background", isOn: $notificationsEnabled)
                    .disabled(isRunning)

                Text("A notification is sent when a download finishes and the app is not active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
