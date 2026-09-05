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
    @AppStorage(DownloadQualityPreferences.overrideFormatListExportKey)
    private var overrideFormatListExport = false

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

                Text("download.formats.source_help")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if overrideFormatListExport {
                    Text("download.formats.export_override_help")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

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
                if !format.note.isEmpty, format.note != format.resolution {
                    Text(format.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if format.hasVideo {
                    formatLine("download.formats.video_label", value: sourceDetails(format))
                    formatLine("download.formats.audio_label", value: selectedAudioDetails(format))
                    formatLine(
                        "download.formats.final_label",
                        value: format.finalVideoExtension(embedThumbnail: embedThumbnail).uppercased(),
                        emphasized: true
                    )
                    if embedThumbnail && (format.resolvedOutputExtension ?? format.fileExtension) == "webm" {
                        Label(
                            format.finalVideoExtension(embedThumbnail: embedThumbnail) == "mkv"
                                ? "download.formats.thumbnail_mkv_help"
                                : "download.formats.webm_thumbnail_warning",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    formatLine("download.formats.audio_label", value: sourceDetails(format))
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatLine(_ title: LocalizedStringKey, value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .fontWeight(.semibold)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(emphasized ? .primary : .secondary)
    }

    private func sizeDescription(_ bytes: Int64?, approximate: Bool) -> String {
        guard let bytes else {
            return String(localized: "download.formats.size_unknown")
        }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
        return approximate ? "≈\(size)" : size
    }

    private func sourceDetails(_ format: YTDLPFormat) -> String {
        [
            format.fileExtension.uppercased(),
            format.hasVideo ? format.videoCodecDisplayName : format.audioCodec,
            sizeDescription(format.fileSize, approximate: format.fileSizeIsApproximate)
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func selectedAudioDetails(_ format: YTDLPFormat) -> String {
        if format.hasAudio {
            return "\(format.audioCodec) · \(String(localized: "download.formats.audio_included"))"
        }
        if let audio = format.selectedAudio {
            return [
                audio.fileExtension.uppercased(),
                audio.codec,
                sizeDescription(audio.fileSize, approximate: audio.fileSizeIsApproximate),
                "#\(audio.id)"
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return String(localized: "download.formats.no_audio")
    }
}
