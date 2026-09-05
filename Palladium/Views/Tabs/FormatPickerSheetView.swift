//
//  FormatPickerSheetView.swift
//  Palladium
//

import SwiftUI

struct FormatPickerSheetView: View {
    let title: String
    let formats: [YTDLPFormat]
    let embedThumbnail: Bool
    let onSelect: (YTDLPFormat) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(.green)
                    Text("download.formats.photos_compatible")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if !videoFormats.isEmpty {
                    Section("download.formats.video_section") {
                        ForEach(videoFormats) { format in
                            formatPickerRow(format)
                        }
                    }
                }

                if !audioFormats.isEmpty {
                    Section("download.formats.audio_section") {
                        ForEach(audioFormats) { format in
                            formatPickerRow(format)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }

    private var videoFormats: [YTDLPFormat] {
        formats.filter(\.hasVideo).sorted { lhs, rhs in
            let leftQuality = (lhs.displayHeight, lhs.framesPerSecond ?? 0, lhs.videoBitrate ?? 0)
            let rightQuality = (rhs.displayHeight, rhs.framesPerSecond ?? 0, rhs.videoBitrate ?? 0)
            if leftQuality.0 != rightQuality.0 { return leftQuality.0 > rightQuality.0 }
            if leftQuality.1 != rightQuality.1 { return leftQuality.1 > rightQuality.1 }
            return leftQuality.2 > rightQuality.2
        }
    }

    private var audioFormats: [YTDLPFormat] {
        formats
            .filter { $0.hasAudio && !$0.hasVideo }
            .sorted { ($0.audioBitrate ?? 0) > ($1.audioBitrate ?? 0) }
    }

    private func formatPickerRow(_ format: YTDLPFormat) -> some View {
        Button {
            dismiss()
            onSelect(format)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(format.qualityHeading)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if format.isPhotosCompatible {
                        Image(systemName: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .accessibilityLabel("download.formats.photos_compatible")
                    }
                    Spacer()
                    Text(format.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(formatDetails(format))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if embedThumbnail && format.predictedOutputExtension.lowercased() == "webm" {
                    Label("download.formats.webm_thumbnail_warning", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(codecDetails(format))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDetails(_ format: YTDLPFormat) -> String {
        var details = [format.predictedOutputExtension.uppercased()].filter { !$0.isEmpty }
        if let fileSize = format.fileSize {
            details.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        if !format.note.isEmpty, format.note != format.resolution {
            details.append(format.note)
        }
        return details.joined(separator: " · ")
    }

    private func codecDetails(_ format: YTDLPFormat) -> String {
        var codecs: [String] = []
        if format.hasVideo {
            codecs.append("Video: \(format.videoCodecDisplayName)")
            codecs.append(format.hasAudio
                ? "Audio: \(format.audioCodec)"
                : String(localized: "download.formats.best_audio"))
        } else if format.hasAudio {
            codecs.append("Audio: \(format.audioCodec)")
        }
        return codecs.joined(separator: " · ")
    }
}
