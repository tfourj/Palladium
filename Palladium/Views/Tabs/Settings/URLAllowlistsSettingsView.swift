import SwiftUI

struct URLAllowlistsSettingsView: View {
    let sources: [URLAllowlistSource]
    let isBusy: Bool
    let onRefresh: () -> Void
    let onAdd: (_ urlString: String) -> Void
    let onRemove: (_ source: URLAllowlistSource) -> Void

    @State private var newAllowlistURL = ""

    var body: some View {
        Form {
            Section {
                TextField("allowlists.add.placeholder", text: $newAllowlistURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .disabled(isBusy)

                Button {
                    let trimmed = newAllowlistURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onAdd(trimmed)
                    newAllowlistURL = ""
                } label: {
                    Label("allowlists.add.button", systemImage: "plus.circle")
                }
                .disabled(isBusy || newAllowlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    onRefresh()
                } label: {
                    Label("allowlists.refresh.button", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
            } footer: {
                Text("allowlists.help")
            }

            Section("allowlists.sources.title") {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(source.isDefault ? String(localized: "allowlists.default.title") : source.displayURL)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if source.isDefault {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if source.isDefault {
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
        .onAppear(perform: onRefresh)
    }
}
