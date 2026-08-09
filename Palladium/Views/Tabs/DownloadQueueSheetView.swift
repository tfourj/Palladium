import SwiftUI

struct DownloadQueueSheetView: View {
    let queue: DownloadQueue
    let selectedPreset: DownloadPreset
    let isOperationBusy: Bool
    let onAddLinks: (String) -> Int
    let onStart: () -> Void
    let onPause: () -> Void
    let onRetry: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onMovePending: (IndexSet, Int) -> Void
    let onClearFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var linksText = ""

    var body: some View {
        NavigationStack {
            List {
                addLinksSection

                if queue.items.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "queue.empty.title",
                            systemImage: "list.bullet.rectangle",
                            description: Text("queue.empty.subtitle")
                        )
                    }
                } else {
                    queueControlsSection
                    activeItemsSection
                    pendingItemsSection
                    finishedItemsSection
                }
            }
            .navigationTitle("queue.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if queue.pendingItems.count > 1 {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var addLinksSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if linksText.isEmpty {
                    Text("queue.links.placeholder")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $linksText)
                    .frame(minHeight: 110)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
            }

            if selectedPreset == .images {
                Label("queue.images.unsupported", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Label {
                    Text(
                        String(
                            format: String(localized: "queue.snapshot.value"),
                            selectedPreset.title
                        )
                    )
                } icon: {
                    Image(systemName: "camera.metering.center.weighted")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Button {
                let addedCount = onAddLinks(linksText)
                if addedCount > 0 {
                    linksText = ""
                }
            } label: {
                Label("queue.add", systemImage: "text.badge.plus")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(
                selectedPreset == .images
                    || DownloadQueue.parsedLinks(from: linksText).isEmpty
            )
        } header: {
            Text("queue.links.title")
        } footer: {
            Text("queue.links.help")
        }
    }

    private var queueControlsSection: some View {
        Section {
            if queue.isActive {
                Button(action: onPause) {
                    Label("queue.pause", systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: onStart) {
                    Label(
                        hasPreviouslyStartedItems ? "queue.resume" : "queue.start",
                        systemImage: "play.circle.fill"
                    )
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isOperationBusy || !queue.hasPendingItems)
            }
        } footer: {
            if isOperationBusy, !queue.isActive {
                Text("queue.busy")
            } else if queue.isActive {
                Text("queue.pause.help")
            }
        }
    }

    @ViewBuilder
    private var activeItemsSection: some View {
        let items = queue.items.filter { $0.status.isActive }
        if !items.isEmpty {
            Section("queue.current") {
                ForEach(items) { item in
                    queueItemRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private var pendingItemsSection: some View {
        if !queue.pendingItems.isEmpty {
            Section("queue.pending") {
                ForEach(queue.pendingItems) { item in
                    queueItemRow(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            deleteButton(for: item)
                        }
                }
                .onMove(perform: onMovePending)
            }
        }
    }

    @ViewBuilder
    private var finishedItemsSection: some View {
        let items = queue.items.filter { $0.status.isTerminal }
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    queueItemRow(item)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if item.status == .failed || item.status == .cancelled {
                                Button {
                                    onRetry(item.id)
                                } label: {
                                    Label("queue.retry", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            deleteButton(for: item)
                        }
                }

                Button(role: .destructive, action: onClearFinished) {
                    Label("queue.clear_finished", systemImage: "trash")
                }
            } header: {
                Text("queue.finished")
            }
        }
    }

    private func queueItemRow(_ item: DownloadQueueItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon(for: item.status))
                .foregroundStyle(statusColor(for: item.status))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }

                Text(item.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(item.configuration.preset.title)
                        .font(.caption2.weight(.semibold))

                    Text(statusText(for: item.status))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor(for: item.status))
                }

                if let errorMessage = item.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }

                if item.status == .failed {
                    Button {
                        onRetry(item.id)
                    } label: {
                        Label("queue.retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: item.status == .failed ? .contain : .combine)
    }

    private func deleteButton(for item: DownloadQueueItem) -> some View {
        Button(role: .destructive) {
            onDelete(item.id)
        } label: {
            Label("common.delete", systemImage: "trash")
        }
    }

    private var hasPreviouslyStartedItems: Bool {
        queue.items.contains { $0.status != .pending }
    }

    private func statusText(for status: DownloadQueueItemStatus) -> String {
        switch status {
        case .pending:
            String(localized: "queue.status.pending")
        case .running:
            String(localized: "queue.status.running")
        case .awaitingAction:
            String(localized: "queue.status.awaiting_action")
        case .succeeded:
            String(localized: "queue.status.succeeded")
        case .partial:
            String(localized: "queue.status.partial")
        case .failed:
            String(localized: "queue.status.failed")
        case .cancelled:
            String(localized: "queue.status.cancelled")
        }
    }

    private func statusIcon(for status: DownloadQueueItemStatus) -> String {
        switch status {
        case .pending:
            "clock"
        case .running:
            "arrow.down.circle.fill"
        case .awaitingAction:
            "hand.tap"
        case .succeeded:
            "checkmark.circle.fill"
        case .partial:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        case .cancelled:
            "stop.circle.fill"
        }
    }

    private func statusColor(for status: DownloadQueueItemStatus) -> Color {
        switch status {
        case .pending, .cancelled:
            .secondary
        case .running:
            .blue
        case .awaitingAction:
            .indigo
        case .succeeded:
            .green
        case .partial:
            .orange
        case .failed:
            .red
        }
    }
}
