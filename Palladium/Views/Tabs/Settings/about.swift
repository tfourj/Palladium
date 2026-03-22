import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let githubURL = URL(string: "https://github.com/TfourJ")
    private let discordURL = URL(string: "https://getnickel.app/discord")
    private let licenseURL = URL(string: "https://github.com/TfourJ/Palladium/blob/main/LICENSE")
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let rawFinalValue = Bundle.main.object(forInfoDictionaryKey: "APP_FINAL")
        let normalizedFinalValue = String(describing: rawFinalValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isFinal = normalizedFinalValue == "true"
        return isFinal ? "v\(version)" : "v\(version)-b\(build)"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(colorScheme == .dark ? "palladium_dark" : "palladium_light")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)

                    Text("Palladium")
                        .font(.title2.bold())
                    
                    Text(appVersion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Powered by yt-dlp and ffmpeg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Developer") {
                HStack {
                    Text("Developer")
                    Spacer()
                    Text("TfourJ")
                        .foregroundStyle(.secondary)
                }
                
                if let githubURL {
                    Link(destination: githubURL) {
                        linkRow("GitHub")
                    }
                }
            }

            Section("Links") {
                if let discordURL {
                    Link(destination: discordURL) {
                        linkRow("Discord")
                    }
                }
                if let licenseURL {
                    Link(destination: licenseURL) {
                        linkRow("License")
                    }
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.blue)
        }
    }
}
