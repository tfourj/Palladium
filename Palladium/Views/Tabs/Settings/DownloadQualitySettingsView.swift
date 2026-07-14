import SwiftUI

struct DownloadQualitySettingsView: View {
    @AppStorage(DownloadQualityPreferences.videoQualityKey)
    private var videoQuality = VideoDownloadQuality.best.rawValue

    @AppStorage(DownloadQualityPreferences.videoContainerKey)
    private var videoContainer = VideoDownloadContainer.mp4.rawValue

    @AppStorage(DownloadQualityPreferences.videoCodecKey)
    private var videoCodec = VideoDownloadCodec.photosCompatible.rawValue

    @AppStorage(DownloadQualityPreferences.audioFormatKey)
    private var audioFormat = AudioDownloadFormat.mp3.rawValue

    @AppStorage(DownloadQualityPreferences.audioQualityKey)
    private var audioQuality = AudioDownloadQuality.best.rawValue

    @AppStorage(DownloadQualityPreferences.overrideFormatListExportKey)
    private var overrideFormatListExport = false

    let isRunning: Bool

    var body: some View {
        Form {
            Section {
                Picker("Quality", selection: $videoQuality) {
                    ForEach(VideoDownloadQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }

                Picker("Format", selection: $videoContainer) {
                    ForEach(VideoDownloadContainer.allCases) { container in
                        Text(container.title).tag(container.rawValue)
                    }
                }

                Picker("Codec", selection: $videoCodec) {
                    ForEach(VideoDownloadCodec.allCases) { codec in
                        Text(codec.title).tag(codec.rawValue)
                    }
                }
            } header: {
                Text("Video")
            } footer: {
                Text("H.264 and H.265/HEVC in MP4 are compatible with the Photos app. H.264 is preferred when both are available.")
            }

            Section {
                Picker("Quality", selection: $audioQuality) {
                    ForEach(AudioDownloadQuality.allCases) { quality in
                        Text(quality.title).tag(quality.rawValue)
                    }
                }

                Picker("Format", selection: $audioFormat) {
                    ForEach(AudioDownloadFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("download.quality.audio.best_help")
            }

            Section {
                Toggle(
                    "download.quality.override_format_list_export.title",
                    isOn: $overrideFormatListExport
                )
            } footer: {
                Text("download.quality.override_format_list_export.help")
            }
        }
        .disabled(isRunning)
        .navigationTitle("Download Quality")
        .navigationBarTitleDisplayMode(.inline)
    }
}
