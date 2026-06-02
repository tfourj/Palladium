import SwiftUI

struct URLAllowlistsSettingsView: View {
    let sources: [URLAllowlistSource]
    let isBusy: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onAdd: (_ urlString: String) -> Void
    let onRemove: (_ source: URLAllowlistSource) -> Void

    @State private var newAllowlistURL = ""
    @State private var showAddAllowlistPrompt = false

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

                Button(action: onRefresh) {
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
                onAdd(trimmed)
                newAllowlistURL = ""
            }
        } message: {
            Text("allowlists.add.message")
        }
    }

    private func sourceTitle(for source: URLAllowlistSource) -> String {
        if source.isDefault, source.displayName == source.displayURL {
            return String(localized: "allowlists.default.title")
        }
        return source.displayName
    }
}
