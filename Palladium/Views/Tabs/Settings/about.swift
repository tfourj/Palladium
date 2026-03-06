import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let discordURL = URL(string: "https://getnickel.app/discord")
    private let licenseURL = URL(string: "https://github.com/TfourJ/Palladium/blob/main/LICENSE")

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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Author") {
                HStack {
                    Text("Author")
                    Spacer()
                    Text("TfourJ")
                        .foregroundStyle(.secondary)
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
