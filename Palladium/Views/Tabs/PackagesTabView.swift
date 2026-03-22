import SwiftUI

struct PackagesTabView: View {
    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let isRunning: Bool
    let onRefreshVersions: () -> Void
    let onUpdatePackages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("packages.tab_title")
                .font(.title2.bold())

            Text(String(format: String(localized: "packages.status.value"), packageStatusText))
                .font(.subheadline.monospaced())

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(packageStatusText == "updating" ? "packages.status.updating" : "packages.status.checking")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text(versionsText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(updatesSummaryText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(action: onRefreshVersions) {
                    Text(isRunning ? "packages.status.running" : "packages.check_updates")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Button(action: onUpdatePackages) {
                    Text(isRunning ? "packages.status.running" : "packages.update")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || !updatesAvailable)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
