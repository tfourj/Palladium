import SwiftUI
import UniformTypeIdentifiers

struct CookieFilesSettingsView: View {
    let items: [CookieLibraryItem]
    let selectedCookieFileName: String?
    let isBusy: Bool
    let onImport: (URL) -> Void
    let onDelete: (CookieLibraryItem) -> Void
    let onAppear: () -> Void

    @State private var showFileImporter = false

    var body: some View {
        Form {
            Section {
                Button("Import Cookie File") {
                    showFileImporter = true
                }
                .disabled(isBusy)
            } header: {
                Text("Import")
            } footer: {
                Text("Import Netscape-format cookie files into Palladium/Documents/Cookies.")
            }

            Section {
                if items.isEmpty {
                    Text("No cookie files imported yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        cookieRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("Library")
            } footer: {
                Text("You can also manage the imported files from the Files app under On My iPhone > Palladium > Cookies.")
            }

            if isBusy {
                Section {
                    Text("Cookie library changes are disabled while a download or package task is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Cookie Files")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onImport(url)
            }
        }
        .onAppear(perform: onAppear)
    }

    private func cookieRow(_ item: CookieLibraryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                Text(item.modifiedDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.fileName == selectedCookieFileName {
                Text("Selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}
