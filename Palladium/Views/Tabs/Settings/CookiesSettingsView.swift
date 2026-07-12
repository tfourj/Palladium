import SwiftUI
import UniformTypeIdentifiers

struct CookiesSettingsView: View {
    @Binding var useCookies: Bool
    @Binding var selectedCookieFileName: String
    @Binding var defaultUseCookies: Bool
    let importedCookieFiles: [ImportedCookieFile]
    let isBusy: Bool
    let onRefresh: () -> Void
    let onImport: (_ sourceURL: URL) throws -> Void
    let onPaste: (_ rawText: String) throws -> Void
    let onDelete: (_ cookieFile: ImportedCookieFile) throws -> Void

    @State private var showFileImporter = false
    @State private var showPasteCookiesSheet = false
    @State private var pastedCookiesText = ""
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

                Button {
                    pastedCookiesText = ""
                    showPasteCookiesSheet = true
                } label: {
                    Label("cookies.paste.button", systemImage: "doc.on.clipboard")
                }
                .disabled(isBusy)

                Button("settings.storage.refresh", action: onRefresh)
                    .disabled(isBusy)
            } footer: {
                Text("cookies.settings.help")
            }

            Section {
                if importedCookieFiles.isEmpty {
                    ContentUnavailableView(
                        "cookies.empty.title",
                        systemImage: "lock.doc",
                        description: Text("cookies.empty.subtitle")
                    )
                } else {
                    ForEach(importedCookieFiles) { cookieFile in
                        Toggle(isOn: cookieEnabledBinding(for: cookieFile)) {
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
                        }
                        .disabled(isBusy)
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
            } header: {
                Text("settings.cookies.title")
            } footer: {
                Text("cookies.switch.help")
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
        .sheet(isPresented: $showPasteCookiesSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("cookies.paste.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $pastedCookiesText)
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
                .navigationTitle("cookies.paste.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") {
                            showPasteCookiesSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("cookies.paste.add") {
                            let rawText = pastedCookiesText
                            pastedCookiesText = ""
                            showPasteCookiesSheet = false
                            do {
                                try onPaste(rawText)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(pastedCookiesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
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

    private func cookieEnabledBinding(for cookieFile: ImportedCookieFile) -> Binding<Bool> {
        Binding(
            get: {
                defaultUseCookies && selectedCookieFileName == cookieFile.fileName
            },
            set: { isEnabled in
                if isEnabled {
                    selectedCookieFileName = cookieFile.fileName
                    defaultUseCookies = true
                    useCookies = true
                } else if selectedCookieFileName == cookieFile.fileName {
                    defaultUseCookies = false
                    useCookies = false
                }
            }
        )
    }
}
