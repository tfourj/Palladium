import SwiftUI
import UIKit

struct ConsoleTabView: View {
    @ObservedObject var logStore: ConsoleLogStore
    @State private var searchText = ""

    var body: some View {
        let visibleEntries = logStore.filteredEntries
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchedEntries = filteredEntries(from: visibleEntries, matching: trimmedSearch)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("console.title")
                    .font(.title2.bold())
                Spacer()
                Button("common.clear") {
                    logStore.clearAll()
                }
                .buttonStyle(.bordered)
            }

            Picker("console.source.title", selection: $logStore.selectedFilter) {
                ForEach(ConsoleLogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            TextField(String(localized: "console.search.placeholder"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            Text(String(format: String(localized: "console.lines.visible"), searchedEntries.count, logStore.entryCount))
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if visibleEntries.isEmpty {
                    Text("console.empty")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if searchedEntries.isEmpty {
                    Text("console.search.empty")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    SelectableConsoleTextView(entries: searchedEntries)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }

    private func filteredEntries(from entries: [ConsoleLogEntry], matching query: String) -> [ConsoleLogEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

private struct SelectableConsoleTextView: UIViewRepresentable {
    let entries: [ConsoleLogEntry]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.alwaysBounceVertical = true
        textView.showsHorizontalScrollIndicator = false
        textView.textContainer.widthTracksTextView = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedText
        textView.textContainer.size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)

        let lastEntryID = entries.last?.id
        if context.coordinator.lastEntryID != lastEntryID {
            context.coordinator.lastEntryID = lastEntryID
            DispatchQueue.main.async {
                let bottom = NSRange(location: max(textView.attributedText.length - 1, 0), length: 1)
                textView.scrollRangeToVisible(bottom)
            }
        }
    }

    private var attributedText: NSAttributedString {
        let text = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        for (index, entry) in entries.enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "\n"))
            }

            text.append(
                NSAttributedString(
                    string: entry.text,
                    attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: color(for: entry.source),
                        .paragraphStyle: paragraphStyle
                    ]
                )
            )
        }

        return text
    }

    private func color(for source: ConsoleLogSource) -> UIColor {
        switch source {
        case .app:
            return .label
        case .ffmpeg:
            return .systemOrange
        case .download:
            return .systemCyan
        }
    }

    final class Coordinator {
        var lastEntryID: Int?
    }
}
