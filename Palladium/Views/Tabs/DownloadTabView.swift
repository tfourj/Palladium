import SwiftUI
import UIKit

struct DownloadTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var statusText: String
    @Binding var urlText: String
    @Binding var selectedPreset: DownloadPreset
    @Binding var downloadPlaylist: Bool
    @Binding var downloadSubtitles: Bool
    @Binding var subtitleLanguagePattern: String

    let isRunning: Bool
    let progressText: String
    let downloadErrorText: String?
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onPastedURL: (String) -> Void
    let linkHistoryEnabled: Bool
    let historyEntries: [LinkHistoryEntry]
    let onSelectHistoryEntry: (LinkHistoryEntry) -> Void
    let onDeleteHistoryEntry: (LinkHistoryEntry) -> Void
    let onCopyHistoryLink: (String) -> Void
    @State private var showHistorySheet = false

    var body: some View {
        ZStack {
            backgroundGradient
            .ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    VStack(spacing: 4) {
                        Image(logoImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                        Text("Palladium")
                            .font(.title.bold())
                            .foregroundStyle(primaryTextColor)
                    }

                    HStack {
                        Spacer()
                        if linkHistoryEnabled {
                            Button {
                                showHistorySheet = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(primaryTextColor)
                                        .frame(width: 40, height: 40)
                                        .background(cardElementBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    if !historyEntries.isEmpty {
                                        Text("\(historyEntries.count)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .clipShape(Capsule())
                                            .offset(x: 8, y: -8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open link history")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Downloading...")
                                .font(.footnote)
                                .foregroundStyle(primaryTextColor)
                        }

                        Text(progressText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(primaryTextColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                            .background(cardElementBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                if let downloadErrorText, !downloadErrorText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last Error")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)

                        Text(downloadErrorText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(primaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(cardElementBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                }

                VStack(spacing: 10) {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(DownloadPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRunning)

                    VStack(spacing: 8) {
                        downloadOptionToggle(
                            title: "Download playlist",
                            subtitle: "Allow yt-dlp to fetch multiple items",
                            isOn: $downloadPlaylist
                        )

                        downloadOptionToggle(
                            title: "Download subtitles",
                            subtitle: "Save subtitle sidecars with the media",
                            isOn: $downloadSubtitles
                        )

                        if downloadSubtitles {
                            Picker("Subtitle language", selection: $subtitleLanguagePattern) {
                                ForEach(SubtitleLanguageOption.allCases) { option in
                                    Text(option.title).tag(option.subtitlePattern)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(isRunning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(cardElementBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        TextField("Enter video URL", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(primaryTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(cardElementBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button(action: pasteOrClearURL) {
                            Image(systemName: urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 42, height: 42)
                                .background(cardElementBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning)
                    }
                    .padding(8)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button(action: {
                        if isRunning {
                            onCancel()
                        } else {
                            onDownload()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isRunning ? "stop.circle.fill" : "arrow.down.circle.fill")
                            Text(isRunning ? "Cancel" : "Download")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .red : .blue)
                    .disabled(!isRunning && urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.vertical, 14)
        }
        .sheet(isPresented: $showHistorySheet) {
            historySheet
        }
    }

    private func pasteOrClearURL() {
        if urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !paste.isEmpty {
                urlText = paste
                onPastedURL(paste)
            }
            return
        }
        urlText = ""
    }

    private func downloadOptionToggle(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            guard !isRunning else { return }
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? .blue : primaryTextColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    @ViewBuilder
    private func historyRow(_ entry: LinkHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = entry.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)
            }

            Text(entry.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Text(entry.preset.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(presetColor(entry.preset).opacity(0.25))
                    .foregroundStyle(primaryTextColor)
                    .clipShape(Capsule())

                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var historySheet: some View {
        NavigationStack {
            Group {
                if historyEntries.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock",
                        description: Text("Downloaded links will appear here.")
                    )
                } else {
                    List {
                        ForEach(historyEntries) { entry in
                            Button {
                                onSelectHistoryEntry(entry)
                                showHistorySheet = false
                            } label: {
                                historyRow(entry)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(listRowBackground)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    onCopyHistoryLink(entry.url)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDeleteHistoryEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Link History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showHistorySheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var logoImageName: String {
        isDarkMode ? "palladium_dark" : "palladium_light"
    }

    private var backgroundGradient: LinearGradient {
        if isDarkMode {
            return LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.10, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.93, blue: 0.97)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var primaryTextColor: Color {
        isDarkMode ? .white : .primary
    }

    private var cardBackground: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var cardElementBackground: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var listRowBackground: Color {
        isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }

    private func presetColor(_ preset: DownloadPreset) -> Color {
        switch preset {
        case .audio:
            return .green
        case .mute:
            return .orange
        case .custom:
            return .indigo
        case .autoVideo:
            return .blue
        }
    }
}
