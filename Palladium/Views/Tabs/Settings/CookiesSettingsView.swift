import SwiftUI
import UniformTypeIdentifiers

struct CookiesSettingsView: View {
    @Binding var selectedCookieFileName: String
    let importedCookieFiles: [ImportedCookieFile]
    let isBusy: Bool
    let onRefresh: () -> Void
    let onImport: (_ sourceURL: URL) throws -> Void
    let onDelete: (_ cookieFile: ImportedCookieFile) throws -> Void

    @State private var showFileImporter = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "cookies.path.title")) {
                    Text("cookies.path.documents")
                        .foregroundStyle(.secondary)
                }

                Button("cookies.import.button") {
                    showFileImporter = true
                }
                .disabled(isBusy)

                Button("settings.storage.refresh", action: onRefresh)
                    .disabled(isBusy)
            } footer: {
                Text("cookies.settings.help")
            }

            Section("cookies.selected.title") {
                Picker("download.options.cookies.picker", selection: $selectedCookieFileName) {
                    Text("common.none").tag("")
                    ForEach(importedCookieFiles) { cookieFile in
                        Text(cookieFile.displayName).tag(cookieFile.fileName)
                    }
                }
                .disabled(isBusy || importedCookieFiles.isEmpty)
            }

            Section("settings.cookies.title") {
                if importedCookieFiles.isEmpty {
                    ContentUnavailableView(
                        "cookies.empty.title",
                        systemImage: "lock.doc",
                        description: Text("cookies.empty.subtitle")
                    )
                } else {
                    ForEach(importedCookieFiles) { cookieFile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cookieFile.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(cookieFile.fileURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(
                                String(
                                    format: String(localized: "cookies.file.meta"),
                                    cookieFile.formattedSize,
                                    cookieFile.modifiedAt.formatted(date: .abbreviated, time: .shortened)
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                do {
                                    try onDelete(cookieFile)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                            .disabled(isBusy)
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.cookies.title")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.data]
        ) { result in
            do {
                let url = try result.get()
                try onImport(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(String(localized: "common.result"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: onRefresh)
    }
}
