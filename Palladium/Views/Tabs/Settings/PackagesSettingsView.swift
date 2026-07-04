import SwiftUI

struct PackagesSettingsView: View {
    private static let latestSelectionToken = "__latest__"
    private static let customUpdatePackageNames = [
        "yt-dlp",
        "yt-dlp-apple-webkit-jsi",
        "curl-cffi",
        "gallery-dl",
        "pip"
    ]

    let packageStatusText: String
    @Binding var checkPackageUpdatesOnLaunch: Bool
    @Binding var autoUpdatePackagesOnLaunch: Bool
    @Binding var packageSourceMode: PackageSourceMode
    @Binding var customPackageSpecsText: String
    let versionsText: String
    let updatesSummaryText: String
    let updatesAvailable: Bool
    let runtimePackagesMissing: Bool
    let availablePackageVersions: [String: [String]]
    let isLoadingPackageVersions: Bool
    let isRunning: Bool
    let onRefreshVersions: () -> Void
    let onCancel: () -> Void
    let onUpdatePackages: () -> Void
    let onInstallPayloadZip: (_ sourceURL: URL) -> Void
    let onCustomUpdatePackages: (_ versions: [String: String]) -> Void
    let onFetchPackageVersions: () -> Void
    let onAppear: () -> Void

    @State private var showCustomVersionSheet = false
    @State private var selectedPackageVersions: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PackageManagerSettingsView(
                        checkPackageUpdatesOnLaunch: $checkPackageUpdatesOnLaunch,
                        autoUpdatePackagesOnLaunch: $autoUpdatePackagesOnLaunch,
                        packageSourceMode: $packageSourceMode,
                        customPackageSpecsText: $customPackageSpecsText,
                        isRunning: isRunning,
                        onInstallPayloadZip: onInstallPayloadZip
                    )
                } label: {
                    Label("settings.packages.manager.title", systemImage: "gearshape")
                }
            }

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
                    guard canRequestPackageUpdate else { return }
                    onUpdatePackages()
                } label: {
                    Text(isRunning ? "packages.status.running" : "packages.update")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .opacity(canRequestPackageUpdate ? 1.0 : 0.5)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                        guard !isRunning, packageSourceMode != .custom else { return }
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

    private var canRequestPackageUpdate: Bool {
        guard !isRunning else { return false }
        return updatesAvailable || runtimePackagesMissing || packageSourceMode == .custom
    }

    private var customVersionSheet: some View {
        NavigationStack {
            Form {
                Section("packages.custom_update.targets") {
                    ForEach(Self.customUpdatePackageNames, id: \.self) { packageName in
                        packageVersionPicker(
                            title: packageName,
                            packageName: packageName,
                            selection: selectedVersionBinding(for: packageName)
                        )
                    }
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
                        onCustomUpdatePackages(selectedCustomVersions())
                        showCustomVersionSheet = false
                    }
                    .disabled(selectedCustomVersions().isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func prepareCustomVersionEditor() {
        selectedPackageVersions = [:]
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

    private func selectedVersionBinding(for packageName: String) -> Binding<String> {
        Binding(
            get: { selectedPackageVersions[packageName] ?? Self.latestSelectionToken },
            set: { selectedPackageVersions[packageName] = $0 }
        )
    }

    private func selectedCustomVersions() -> [String: String] {
        var versions: [String: String] = [:]
        for packageName in Self.customUpdatePackageNames {
            let selection = selectedPackageVersions[packageName] ?? Self.latestSelectionToken
            if let version = normalizeSelection(selection) {
                versions[packageName] = version
            }
        }
        return versions
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
        if packageStatusText == "installing" {
            return String(localized: "packages.status.installing")
        }
        if packageStatusText == "indexing" {
            return String(localized: "packages.status.loading_index")
        }
        return String(localized: "packages.status.checking")
    }
}
