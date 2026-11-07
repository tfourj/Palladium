import SwiftUI

struct LinkPreviewCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: LinkPreviewState
    let isInHistory: Bool

    private let thumbnailSize = CGSize(width: 128, height: 72)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("download.preview.loading")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .loaded(_, let preview):
                loadedContent(preview)
            case .failed:
                Label("download.preview.failed", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isInHistory {
                Label("download.preview.already_downloaded", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardElementBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.16), value: state)
    }

    private func loadedContent(_ preview: LinkPreview) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail(preview)

            VStack(alignment: .leading, spacing: 4) {
                if !preview.title.isEmpty {
                    Text(preview.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(3)
                }

                if !preview.sourceText.isEmpty {
                    Text(preview.sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                let details = detailParts(preview)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func thumbnail(_ preview: LinkPreview) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: preview.thumbnailURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: preview.isPlaylist ? "list.and.film" : "play.rectangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .background(cardElementBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let durationText = preview.durationText {
                Text(durationText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
    }

    private func detailParts(_ preview: LinkPreview) -> [String] {
        var parts: [String] = []
        if preview.isPlaylist, let count = preview.entryCount {
            if count == 1 {
                parts.append(String(localized: "download.preview.playlist.one", bundle: .app))
            } else {
                parts.append(String(format: String(localized: "download.preview.playlist.many", bundle: .app), count))
            }
        }
        if let sizeText = preview.fileSizeText {
            parts.append(sizeText)
        }
        return parts
    }

    private var borderColor: Color {
        isInHistory ? Color.orange.opacity(0.45) : Color.blue.opacity(0.28)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var cardElementBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}
