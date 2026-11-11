import SwiftUI
import UniformTypeIdentifiers

struct PluginsSettingsView: View {
    let isBusy: Bool

    @State private var plugins: [YTDLPPlugin] = []
    @State private var showFileImporter = false
    @State private var showLinkPrompt = false
    @State private var pluginLink = ""
    @State private var isDownloading = false
    @State private var errorMessage: String?

    private static let importContentTypes: [UTType] = [.zip, .folder]
        + ["whl", "egg"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "plugins.path.title", bundle: .app)) {
                    Text("plugins.path.documents")
                        .foregroundStyle(.secondary)
                }

                Button("plugins.import.button") {
                    showFileImporter = true
                }
                .disabled(isBusy || isDownloading)

                Button {
                    pluginLink = ""
                    showLinkPrompt = true
                } label: {
                    HStack {
                        Label("plugins.link.button", systemImage: "link")
                        if isDownloading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isBusy || isDownloading)

                Button("plugins.refresh.button", action: refresh)
                    .disabled(isBusy)
            } footer: {
                Text("plugins.settings.help")
            }

            Section {
                if plugins.isEmpty {
                    ContentUnavailableView(
                        "plugins.empty.title",
                        systemImage: "puzzlepiece.extension",
                        description: Text("plugins.empty.subtitle")
                    )
                } else {
                    ForEach(plugins) { plugin in
                        pluginRow(plugin)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(plugin)
                                } label: {
                                    Label("common.delete", systemImage: "trash")
                                }
                                .disabled(isBusy)
                            }
                    }
                }
            }
        }
        .navigationTitle("settings.plugins.title")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.importContentTypes,
            allowsMultipleSelection: true
        ) { result in
            importPlugins(from: result)
        }
        .alert("plugins.link.title", isPresented: $showLinkPrompt) {
            TextField("plugins.link.placeholder", text: $pluginLink)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("common.cancel", role: .cancel) {}
            Button("plugins.link.import") {
                importPlugin(fromLink: pluginLink)
            }
        }
        .alert(String(localized: "common.result", bundle: .app), isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button(String(localized: "common.ok", bundle: .app), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: refresh)
    }

    private func pluginRow(_ plugin: YTDLPPlugin) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plugin.displayName)
                .font(.subheadline.weight(.semibold))

            if plugin.isRecognized {
                Text(plugin.kinds.map(\.localizedName).formatted(.list(type: .and)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("plugins.kind.unrecognized", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(StorageLocationSummary.byteFormatter.string(fromByteCount: plugin.sizeBytes))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        do {
            plugins = try YTDLPPluginLibrary.plugins(in: YTDLPPluginLibrary.directoryURL())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPlugins(from result: Result<[URL], Error>) {
        do {
            let directory = try YTDLPPluginLibrary.directoryURL()
            var failures: [String] = []
            for url in try result.get() {
                do {
                    try YTDLPPluginLibrary.importPlugin(from: url, into: directory)
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func importPlugin(fromLink link: String) {
        isDownloading = true
        Task {
            do {
                let directory = try YTDLPPluginLibrary.directoryURL()
                try await YTDLPPluginLibrary.importPlugin(fromLink: link, into: directory)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDownloading = false
            refresh()
        }
    }

    private func delete(_ plugin: YTDLPPlugin) {
        do {
            try YTDLPPluginLibrary.delete(plugin)
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
