import SwiftUI

struct PostProcessingSettingsView: View {
    @AppStorage(PostProcessingPreferences.enabledKey) private var enabled = false
    @AppStorage(PostProcessingPreferences.methodKey) private var method = VideoPostProcessingMethod.recode
    @AppStorage(PostProcessingPreferences.formatKey) private var format = VideoPostProcessingFormat.mp4
    @AppStorage(PostProcessingPreferences.codecKey) private var codec = VideoPostProcessingCodec.auto
    @AppStorage(PostProcessingPreferences.encoderKey) private var encoder = VideoPostProcessingEncoder.auto
    @AppStorage(PostProcessingPreferences.qualityKey) private var quality = VideoPostProcessingQuality.high
    @AppStorage(PostProcessingPreferences.hardwareDecodingKey) private var hardwareDecoding = true
    @AppStorage(PostProcessingPreferences.alwaysReencodeKey) private var alwaysReencode = false

    let isRunning: Bool

    private var preferences: PostProcessingPreferences {
        PostProcessingPreferences(enabled: enabled, method: method, format: format, codec: codec, encoder: encoder)
    }

    private var codecOptions: [VideoPostProcessingCodec] {
        [.auto] + format.supportedCodecs
    }

    private var encoderOptions: [VideoPostProcessingEncoder] {
        [.auto] + preferences.resolvedCodec.availableEncoders
    }

    var body: some View {
        Form {
            Section {
                Toggle("settings.post_processing.enabled", isOn: $enabled)

                if enabled {
                    Picker("settings.post_processing.mode", selection: $method) {
                        ForEach(VideoPostProcessingMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }

                    Picker("settings.post_processing.format", selection: $format) {
                        ForEach(VideoPostProcessingFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                }
            } footer: {
                Text("settings.post_processing.scope")
            }

            if enabled && method == .recode {
                encodingSection

                Section {
                    Toggle("settings.post_processing.always_reencode", isOn: $alwaysReencode)
                } footer: {
                    Text("settings.post_processing.always_reencode_help")
                }
            }

            Section {
                Label {
                    Text("settings.post_processing.warning")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("settings.post_processing.remux_help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isRunning)
        .navigationTitle("settings.post_processing.title")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: format) { _, newFormat in
            if !newFormat.supportedCodecs.contains(codec) {
                codec = .auto
            }
        }
        .onChange(of: codec) { _, _ in
            if !encoderOptions.contains(encoder) {
                encoder = .auto
            }
        }
    }

    private var encodingSection: some View {
        Section {
            Picker("settings.post_processing.codec", selection: $codec) {
                ForEach(codecOptions) { codec in
                    Text(codecTitle(codec)).tag(codec)
                }
            }

            Picker("settings.post_processing.encoder", selection: $encoder) {
                ForEach(encoderOptions) { encoder in
                    Text(encoderTitle(encoder)).tag(encoder)
                }
            }

            Picker("settings.post_processing.quality", selection: $quality) {
                ForEach(VideoPostProcessingQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }

            Toggle("settings.post_processing.hardware_decoding", isOn: $hardwareDecoding)
        } header: {
            Text("settings.post_processing.encoding")
        } footer: {
            Text(
                String(
                    format: String(localized: "settings.post_processing.encoding_help", bundle: .app),
                    preferences.resolvedFFmpegEncoder
                )
            )
        }
    }

    private func codecTitle(_ codec: VideoPostProcessingCodec) -> String {
        guard codec == .auto else { return codec.title }
        return "\(codec.title) (\(format.defaultCodec.title))"
    }

    private func encoderTitle(_ encoder: VideoPostProcessingEncoder) -> String {
        guard encoder == .auto else { return encoder.title }
        let resolved = PostProcessingPreferences(format: format, codec: codec).resolvedEncoder
        return "\(encoder.title) (\(resolved.title))"
    }
}
