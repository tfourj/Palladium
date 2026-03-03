import SwiftUI

struct PackagesTabView: View {
    let packageStatusText: String
    let versionsText: String
    let isRunning: Bool
    let onRefreshVersions: () -> Void
    let onUpdatePackages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("package manager")
                .font(.title2.bold())

            Text("status: \(packageStatusText)")
                .font(.subheadline.monospaced())

            Text(versionsText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(action: onRefreshVersions) {
                    Text(isRunning ? "Running..." : "Refresh Versions")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button(action: onUpdatePackages) {
                    Text(isRunning ? "Running..." : "Update Packages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
