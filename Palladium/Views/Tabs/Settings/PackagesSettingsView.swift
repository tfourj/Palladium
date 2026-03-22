import SwiftUI

struct PackagesSettingsView: View {
    private static let latestSelectionToken = "__latest__"

    let packageStatusText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let availablePackageVersions: [String: [String]]
    let isLoadingPackageVersions: Bool
    let isRunning: Bool
    let onRefreshVersions: () -> Void
    let onCancel: () -> Void
    let onUpdatePackages: () -> Void
    let onCustomUpdatePackages: (_ ytDlpVersion: String?, _ webkitJSIVersion: String?, _ pipVersion: String?) -> Void
    let onFetchPackageVersions: () -> Void
    let onAppear: () -> Void

    @State private var showCustomVersionSheet = false
    @State private var ytDlpSelectedVersion = Self.latestSelectionToken
    @State private var webkitJSISelectedVersion = Self.latestSelectionToken
    @State private var pipSelectedVersion = Self.latestSelectionToken

    var body: some View {
        Form {
            Section("packages.status.title") {
                Text(String(format: String(localized: "packages.status.value"), packageStatusText))
                    .font(.subheadline.monospaced())

                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(progressStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("packages.installed.title") {
                Text(versionsText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("packages.summary.title") {
                Text(updatesSummaryText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("packages.actions.title") {
                if isRunning {
                    Button(action: onCancel) {
                        Text("common.cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: onRefreshVersions) {
                        Text("packages.check_updates")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    guard !isRunning, updatesAvailable else { return }
                    onUpdatePackages()
                } label: {
                    Text(isRunning ? "packages.status.running" : "packages.update")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .opacity((isRunning || !updatesAvailable) ? 0.5 : 1.0)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                        guard !isRunning else { return }
                        prepareCustomVersionEditor()
                        showCustomVersionSheet = true
                        onFetchPackageVersions()
                    }
                )

                Text("packages.update.long_press_help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.packages.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: onAppear)
        .sheet(isPresented: $showCustomVersionSheet) {
            customVersionSheet
        }
    }

    private var customVersionSheet: some View {
        NavigationStack {
            Form {
                Section("packages.custom_update.targets") {
                    packageVersionPicker(
                        title: "yt-dlp",
                        packageName: "yt-dlp",
                        selection: $ytDlpSelectedVersion
                    )
                    packageVersionPicker(
                        title: "yt-dlp-apple-webkit-jsi",
                        packageName: "yt-dlp-apple-webkit-jsi",
                        selection: $webkitJSISelectedVersion
                    )
                    packageVersionPicker(
                        title: "pip",
                        packageName: "pip",
                        selection: $pipSelectedVersion
                    )
                }

                Section("packages.custom_update.source") {
                    Button(action: onFetchPackageVersions) {
                        HStack {
                            if isLoadingPackageVersions {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoadingPackageVersions ? "packages.loading_versions" : "packages.reload_versions")
                        }
                    }
                    .disabled(isRunning || isLoadingPackageVersions)

                    if !isLoadingPackageVersions {
                        Text("packages.custom_update.source_help")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("packages.custom_update.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("packages.custom_update.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        showCustomVersionSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.apply") {
                        let ytDlp = normalizeSelection(ytDlpSelectedVersion)
                        let webkit = normalizeSelection(webkitJSISelectedVersion)
                        let pip = normalizeSelection(pipSelectedVersion)
                        onCustomUpdatePackages(ytDlp, webkit, pip)
                        showCustomVersionSheet = false
                    }
                    .disabled(normalizeSelection(ytDlpSelectedVersion) == nil &&
                              normalizeSelection(webkitJSISelectedVersion) == nil &&
                              normalizeSelection(pipSelectedVersion) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func prepareCustomVersionEditor() {
        ytDlpSelectedVersion = Self.latestSelectionToken
        webkitJSISelectedVersion = Self.latestSelectionToken
        pipSelectedVersion = Self.latestSelectionToken
    }

    private func installedVersion(for packageName: String) -> String? {
        let prefix = "\(packageName):"
        for line in versionsText.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix(prefix.lowercased()) {
                let value = line.replacingOccurrences(of: prefix, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let lowered = value.lowercased()
                if value.isEmpty || lowered == "not installed" || lowered == "unknown" {
                    return nil
                }
                return value
            }
        }
        return nil
    }

    private func normalizeSelection(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.latestSelectionToken {
            return nil
        }
        return trimmed
    }

    @ViewBuilder
    private func packageVersionPicker(
        title: String,
        packageName: String,
        selection: Binding<String>
    ) -> some View {
        let options = availableVersions(for: packageName)
        Picker(title, selection: selection) {
            Text("packages.latest")
                .tag(Self.latestSelectionToken)
            ForEach(options, id: \.self) { version in
                Text(version).tag(version)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: availablePackageVersions[packageName]?.count ?? 0, initial: false) {
            let current = selection.wrappedValue
            if current == Self.latestSelectionToken {
                return
            }
            if !options.contains(current) {
                selection.wrappedValue = Self.latestSelectionToken
            }
        }
    }

    private func availableVersions(for packageName: String) -> [String] {
        var values = availablePackageVersions[packageName] ?? []
        if let installed = installedVersion(for: packageName),
           !installed.isEmpty,
           installed.lowercased() != "not installed",
           !values.contains(installed) {
            values.insert(installed, at: 0)
        }
        return values
    }

    private var progressStatusMessage: String {
        if packageStatusText == "updating" {
            return String(localized: "packages.status.updating")
        }
        if packageStatusText == "indexing" {
            return String(localized: "packages.status.loading_index")
        }
        return String(localized: "packages.status.checking")
    }
}
