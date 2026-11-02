import SwiftUI
import UniformTypeIdentifiers

struct PackageManagerSettingsView: View {
    @AppStorage(PackageIndexMirror.defaultsKey) private var packageIndexMirror = PackageIndexMirror.defaultValue
    @AppStorage(PackageIndexMirror.customURLDefaultsKey) private var packageIndexCustomURL = ""
    @Binding var checkPackageUpdatesOnLaunch: Bool
    @Binding var autoUpdatePackagesOnLaunch: Bool
    @Binding var packageSourceMode: PackageSourceMode
    @Binding var customPackageSpecsText: String
    let isRunning: Bool
    let onInstallPayloadZip: (_ sourceURL: URL) -> Void

    @State private var showNightlyWarning = false
    @State private var showPayloadBundleImporter = false
    @State private var payloadImportErrorMessage: String?
    @State private var showPayloadImportError = false

    var body: some View {
        Form {
            Section("packages.source.title") {
                Picker("packages.source.picker", selection: packageSourceSelection) {
                    ForEach(PackageSourceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)

                Text(String(format: String(localized: "packages.source.active", bundle: .app), packageSourceMode.title))
                    .font(.caption)
                    .foregroundStyle(packageSourceMode == .nightly ? .orange : .secondary)

                Text(sourceHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if packageSourceMode == .custom {
                Section("packages.source.custom_specs.title") {
                    TextEditor(text: $customPackageSpecsText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                        .disabled(isRunning)

                    Button("packages.source.custom_specs.reset") {
                        customPackageSpecsText = PackageSourceDefaults.customSpecs
                    }
                    .disabled(isRunning)

                    Text("packages.source.custom_specs.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("packages.index.picker", selection: $packageIndexMirror) {
                    ForEach(PackageIndexMirror.allCases) { mirror in
                        Text(mirror.title).tag(mirror)
                    }
                }
                .disabled(isRunning)

                if packageIndexMirror == .custom {
                    TextField("packages.index.custom_url.placeholder", text: $packageIndexCustomURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .disabled(isRunning)
                }

                if let indexURL = packageIndexMirror.indexURL(customURL: packageIndexCustomURL) {
                    Text(indexURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if packageIndexMirror == .custom {
                    Text("packages.index.custom_url.invalid")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("packages.index.title")
            } footer: {
                Text("packages.index.help")
            }

            Section {
                Button {
                    showPayloadBundleImporter = true
                } label: {
                    Label("packages.payload.import", systemImage: "doc.zipper")
                }
                .disabled(isRunning)
            } footer: {
                Text("packages.payload.help")
            }

            Section {
                Toggle("settings.ui.packages.auto_check", isOn: $checkPackageUpdatesOnLaunch)
                    .disabled(isRunning)

                Toggle("settings.ui.packages.auto_update", isOn: $autoUpdatePackagesOnLaunch)
                    .disabled(isRunning || !checkPackageUpdatesOnLaunch)


            } header: {
                Text("settings.packages.update_checks.section")
            } footer: {
                Text("settings.ui.packages.auto_check.help")
                Text("settings.ui.packages.auto_update.help")
            }
        }
        .navigationTitle("settings.packages.manager.title")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showPayloadBundleImporter,
            allowedContentTypes: payloadBundleContentTypes
        ) { result in
            do {
                let sourceURL = try result.get()
                onInstallPayloadZip(sourceURL)
            } catch {
                payloadImportErrorMessage = error.localizedDescription
                showPayloadImportError = true
            }
        }
        .alert("packages.payload.import_failed.title", isPresented: $showPayloadImportError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(payloadImportErrorMessage ?? "")
        }
        .alert("packages.source.nightly.warning.title", isPresented: $showNightlyWarning) {
            Button("common.cancel", role: .cancel) {}
            Button("packages.source.nightly.enable") {
                packageSourceMode = .nightly
            }
        } message: {
            Text("packages.source.nightly.warning.message")
        }
    }

    private var payloadBundleContentTypes: [UTType] {
        if let wheelContentType = UTType(filenameExtension: "whl") {
            return [.zip, wheelContentType, .data]
        }
        return [.zip, .data]
    }

    private var packageSourceSelection: Binding<PackageSourceMode> {
        Binding(
            get: { packageSourceMode },
            set: { newValue in
                guard !isRunning else { return }
                if newValue == .nightly, packageSourceMode != .nightly {
                    showNightlyWarning = true
                } else {
                    packageSourceMode = newValue
                }
            }
        )
    }

    private var sourceHelpText: LocalizedStringKey {
        switch packageSourceMode {
        case .stable:
            return "packages.source.stable.help"
        case .nightly:
            return "packages.source.nightly.help"
        case .custom:
            return "packages.source.custom.help"
        }
    }
}
