import SwiftUI
import UniformTypeIdentifiers

struct URLAllowlistsSettingsView: View {
    let sources: [URLAllowlistSource]
    let isBusy: Bool
    let isRefreshing: Bool
    let onRefresh: (_ onComplete: ((_ message: String) -> Void)?) -> Void
    let onAdd: (_ urlString: String, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onImport: (_ sourceURL: URL, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onPaste: (_ json: String, _ onComplete: ((_ message: String) -> Void)?) -> Void
    let onRemove: (_ source: URLAllowlistSource) -> Void

    @State private var newAllowlistURL = ""
    @State private var showAddAllowlistPrompt = false
    @State private var showLocalFileImporter = false
    @State private var showPasteAllowlistSheet = false
    @State private var pastedAllowlistJSON = ""
    @State private var feedbackMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    newAllowlistURL = ""
                    showAddAllowlistPrompt = true
                } label: {
                    Label("allowlists.add.button", systemImage: "plus.circle")
                }
                .disabled(isBusy || isRefreshing)

                Button {
                    pastedAllowlistJSON = ""
                    showPasteAllowlistSheet = true
                } label: {
                    Label("allowlists.paste.button", systemImage: "doc.on.clipboard")
                }
                .disabled(isBusy || isRefreshing)

                Button {
                    showLocalFileImporter = true
                } label: {
                    Label("allowlists.import.button", systemImage: "doc.badge.plus")
                }
                .disabled(isBusy || isRefreshing)

                Button {
                    feedbackMessage = String(localized: "allowlists.status.fetching")
                    onRefresh { message in
                        feedbackMessage = message
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                    : .default,
                                value: isRefreshing
                            )
                        Text("allowlists.refresh.button")
                    }
                }
                .disabled(isBusy || isRefreshing)
            } footer: {
                Text("allowlists.help")
            }

            if isRefreshing || feedbackMessage != nil {
                Section {
                    HStack(spacing: 10) {
                        if isRefreshing {
                            ProgressView()
                        }
                        Text(isRefreshing ? String(localized: "allowlists.status.fetching") : feedbackMessage ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("allowlists.sources.title") {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(sourceTitle(for: source))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if source.isDefault {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if source.isDefault || source.displayName != source.displayURL {
                            Text(source.displayURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(source.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let lastRefreshDate = source.lastRefreshDate {
                            Text(
                                String(
                                    format: String(localized: "allowlists.last_refresh"),
                                    lastRefreshDate.formatted(date: .abbreviated, time: .shortened)
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !source.isDefault {
                            Button(role: .destructive) {
                                onRemove(source)
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
        .navigationTitle("allowlists.title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("allowlists.add.title", isPresented: $showAddAllowlistPrompt) {
            TextField("allowlists.add.placeholder", text: $newAllowlistURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()

            Button("common.cancel", role: .cancel) {
                newAllowlistURL = ""
            }

            Button("common.save") {
                let trimmed = newAllowlistURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                feedbackMessage = String(localized: "allowlists.status.fetching")
                onAdd(trimmed) { message in
                    feedbackMessage = message
                }
                newAllowlistURL = ""
            }
        } message: {
            Text("allowlists.add.message")
        }
        .fileImporter(
            isPresented: $showLocalFileImporter,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let sourceURL = try result.get()
                feedbackMessage = String(localized: "allowlists.status.importing")
                onImport(sourceURL) { message in
                    feedbackMessage = message
                }
            } catch {
                feedbackMessage = String(format: String(localized: "allowlists.status.import_failed"), error.localizedDescription)
            }
        }
        .sheet(isPresented: $showPasteAllowlistSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("allowlists.paste.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $pastedAllowlistJSON)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator, lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                }
                .padding()
                .navigationTitle("allowlists.paste.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") {
                            showPasteAllowlistSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("allowlists.paste.add") {
                            let json = pastedAllowlistJSON
                            pastedAllowlistJSON = ""
                            showPasteAllowlistSheet = false
                            feedbackMessage = String(localized: "allowlists.status.pasting")
                            onPaste(json) { message in
                                feedbackMessage = message
                            }
                        }
                        .disabled(pastedAllowlistJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func sourceTitle(for source: URLAllowlistSource) -> String {
        if source.isDefault, source.displayName == source.displayURL {
            return String(localized: "allowlists.default.title")
        }
        return source.displayName
    }
}
