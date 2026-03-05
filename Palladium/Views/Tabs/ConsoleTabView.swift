import SwiftUI

struct ConsoleTabView: View {
    @ObservedObject var logStore: ConsoleLogStore

    var body: some View {
        let visibleEntries = logStore.filteredEntries

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("console")
                    .font(.title2.bold())
                Spacer()
                Button("Clear") {
                    logStore.clearAll()
                }
                .buttonStyle(.bordered)
            }

            Picker("Source", selection: $logStore.selectedFilter) {
                ForEach(ConsoleLogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Text("showing \(visibleEntries.count) of \(logStore.entryCount) lines")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if visibleEntries.isEmpty {
                            Text("No logs yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(visibleEntries) { entry in
                                Text(entry.text)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(color(for: entry.source))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                    }
                    .textSelection(.enabled)
                }
                .onChange(of: visibleEntries.last?.id) { lastID in
                    guard let lastID else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }

    private func color(for source: ConsoleLogSource) -> Color {
        switch source {
        case .app:
            return .primary
        case .ffmpeg:
            return .orange
        case .download:
            return .cyan
        }
    }
}
