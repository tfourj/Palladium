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
    let onUpdatePackages: () -> Void
    let onCustomUpdatePackages: (_ ytDlpVersion: String?, _ webkitJSIVersion: String?, _ pipVersion: String?) -> Void
    let onFetchPackageVersions: () -> Void
    let onAppear: () -> Void

    @State private var showCustomVersionSheet = false
    @State private var ytDlpSelectedVersion = "__latest__"
    @State private var webkitJSISelectedVersion = "__latest__"
    @State private var pipSelectedVersion = "__latest__"

    var body: some View {
        Form {
            Section("Status") {
                Text("status: \(packageStatusText)")
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

            Section("Installed Versions") {
                Text(versionsText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Update Summary") {
                Text(updatesSummaryText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Actions") {
                Button(action: onRefreshVersions) {
                    Text(isRunning ? "Running..." : "Check for Updates")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Button {
                    guard !isRunning, updatesAvailable else { return }
                    onUpdatePackages()
                } label: {
                    Text(isRunning ? "Running..." : "Update Packages")
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

                Text("Long press Update Packages to set custom package versions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Package Manager")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: onAppear)
        .sheet(isPresented: $showCustomVersionSheet) {
            customVersionSheet
        }
    }

    private var customVersionSheet: some View {
        NavigationStack {
            Form {
                Section("Target Versions") {
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

                Section("Version Source") {
                    Button(action: onFetchPackageVersions) {
                        HStack {
                            if isLoadingPackageVersions {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoadingPackageVersions ? "Loading versions..." : "Reload Available Versions")
                        }
                    }
                    .disabled(isRunning || isLoadingPackageVersions)

                    if !isLoadingPackageVersions {
                        Text("Uses pip index versions for each package.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Select a version to pin for update or downgrade. Choose Latest available to skip pinning a package.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Custom Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showCustomVersionSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
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
            Text("Latest available")
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
            return "Updating packages..."
        }
        if packageStatusText == "indexing" {
            return "Loading package versions..."
        }
        return "Checking versions..."
    }
}
