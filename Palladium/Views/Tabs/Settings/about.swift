import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let githubURL = URL(string: "https://github.com/TfourJ")
    private let websiteURL = URL(string: "https://getpalladium.app")
    private let contactURL = URL(string: "https://getpalladium.app/contact")
    private let discordURL = URL(string: "https://discord.tfourj.com")
    private let licenseURL = URL(string: "https://github.com/TfourJ/Palladium/blob/main/LICENSE")
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let commitID = Bundle.main.infoDictionary?["GIT_COMMIT_ID"] as? String ?? "Unknown"
        let rawFinalValue = Bundle.main.object(forInfoDictionaryKey: "APP_FINAL")
        let normalizedFinalValue = String(describing: rawFinalValue ?? false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isFinal = normalizedFinalValue == "true" || normalizedFinalValue == "1"
        return isFinal ? "v\(version)" : "v\(version) (\(commitID))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(colorScheme == .dark ? "palladium_dark" : "palladium_light")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)

                    Text("app.name")
                        .font(.title2.bold())
                    
                    Text(appVersion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("about.powered_by")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("about.developer.title") {
                if let githubURL {
                    Link(destination: githubURL) {
                        HStack(spacing: 14) {
                            AsyncImage(url: URL(string: "https://github.com/TfourJ.png?size=128")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                initialBadge("T", size: 52)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("about.developer.name")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("about.developer.title")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("about.contributors.title") {
                creditBadge(name: "francescofugazzi", initial: "F")
            }

            Section("about.translators.title") {
                creditBadge(name: "so-5699", initial: "S", language: "about.translators.japanese")
            }

            Section("about.links.title") {
                if let websiteURL {
                    Link(destination: websiteURL) {
                        linkRow("Website")
                    }
                }
                if let contactURL {
                    Link(destination: contactURL) {
                        linkRow("Contact")
                    }
                }
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
        .navigationTitle("settings.about.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func initialBadge(_ initial: String, size: CGFloat) -> some View {
        Text(verbatim: initial)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }

    private func creditBadge(name: String, initial: String, language: LocalizedStringKey? = nil) -> some View {
        HStack(spacing: 8) {
            initialBadge(initial, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let language {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if language != nil {
                Text(verbatim: "🇯🇵")
                    .font(.footnote)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .accessibilityElement(children: .combine)
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
