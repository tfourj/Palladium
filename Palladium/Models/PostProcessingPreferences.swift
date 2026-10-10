import Foundation

enum VideoPostProcessingMethod: String, Codable, CaseIterable, Identifiable {
    case recode
    case remux

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recode: return String(localized: "settings.post_processing.recode", bundle: .app)
        case .remux: return String(localized: "settings.post_processing.remux", bundle: .app)
        }
    }
}

enum VideoPostProcessingFormat: String, Codable, CaseIterable, Identifiable {
    case mp4
    case webm
    case avi
    case mkv
    case mov

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var supportedCodecs: [VideoPostProcessingCodec] {
        switch self {
        case .mp4: return [.h264, .hevc, .vp9, .mpeg4]
        case .mov: return [.h264, .hevc, .prores, .mpeg4]
        case .mkv: return [.h264, .hevc, .vp9, .vp8, .prores, .mpeg4]
        case .webm: return [.vp9, .vp8]
        case .avi: return [.mpeg4, .h264]
        }
    }

    var defaultCodec: VideoPostProcessingCodec {
        switch self {
        case .webm: return .vp9
        case .avi: return .mpeg4
        case .mp4, .mkv, .mov: return .h264
        }
    }
}

enum VideoPostProcessingCodec: String, Codable, CaseIterable, Identifiable {
    case auto
    case h264
    case hevc
    case vp9
    case vp8
    case mpeg4
    case prores

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return String(localized: "settings.post_processing.auto", bundle: .app)
        case .h264: return "H.264"
        case .hevc: return "H.265 (HEVC)"
        case .vp9: return "VP9"
        case .vp8: return "VP8"
        case .mpeg4: return "MPEG-4"
        case .prores: return "ProRes"
        }
    }

    /// Concrete encoders bundled in the iOS FFmpeg framework, hardware first.
    var availableEncoders: [VideoPostProcessingEncoder] {
        switch self {
        case .auto: return []
        case .h264, .hevc: return [.hardware]
        case .prores: return [.hardware, .software]
        case .vp9, .vp8, .mpeg4: return [.software]
        }
    }

    func ffmpegEncoder(_ encoder: VideoPostProcessingEncoder) -> String? {
        switch (self, encoder) {
        case (.h264, .hardware): return "h264_videotoolbox"
        case (.hevc, .hardware): return "hevc_videotoolbox"
        case (.prores, .hardware): return "prores_videotoolbox"
        case (.prores, .software): return "prores_ks"
        case (.vp9, .software): return "libvpx-vp9"
        case (.vp8, .software): return "libvpx"
        case (.mpeg4, .software): return "mpeg4"
        default: return nil
        }
    }
}

enum VideoPostProcessingEncoder: String, Codable, CaseIterable, Identifiable {
    case auto
    case hardware
    case software

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return String(localized: "settings.post_processing.auto", bundle: .app)
        case .hardware: return String(localized: "settings.post_processing.encoder.hardware", bundle: .app)
        case .software: return String(localized: "settings.post_processing.encoder.software", bundle: .app)
        }
    }
}

enum VideoPostProcessingQuality: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return String(localized: "settings.post_processing.quality.low", bundle: .app)
        case .medium: return String(localized: "settings.post_processing.quality.medium", bundle: .app)
        case .high: return String(localized: "settings.post_processing.quality.high", bundle: .app)
        case .maximum: return String(localized: "settings.post_processing.quality.maximum", bundle: .app)
        }
    }
}

struct PostProcessingPreferences: Codable, Equatable {
    static let enabledKey = "palladium.postProcessingEnabled"
    static let methodKey = "palladium.postProcessingMethod"
    static let formatKey = "palladium.postProcessingFormat"
    static let codecKey = "palladium.postProcessingCodec"
    static let encoderKey = "palladium.postProcessingEncoder"
    static let qualityKey = "palladium.postProcessingQuality"
    static let hardwareDecodingKey = "palladium.postProcessingHardwareDecoding"
    static let alwaysReencodeKey = "palladium.postProcessingAlwaysReencode"

    var enabled = false
    var method: VideoPostProcessingMethod = .recode
    var format: VideoPostProcessingFormat = .mp4
    var codec: VideoPostProcessingCodec = .auto
    var encoder: VideoPostProcessingEncoder = .auto
    var quality: VideoPostProcessingQuality = .high
    var hardwareDecoding = true
    var alwaysReencode = false

    init(
        enabled: Bool = false,
        method: VideoPostProcessingMethod = .recode,
        format: VideoPostProcessingFormat = .mp4,
        codec: VideoPostProcessingCodec = .auto,
        encoder: VideoPostProcessingEncoder = .auto,
        quality: VideoPostProcessingQuality = .high,
        hardwareDecoding: Bool = true,
        alwaysReencode: Bool = false
    ) {
        self.enabled = enabled
        self.method = method
        self.format = format
        self.codec = codec
        self.encoder = encoder
        self.quality = quality
        self.hardwareDecoding = hardwareDecoding
        self.alwaysReencode = alwaysReencode
    }

    // Queued downloads persist this snapshot, so fields added later must decode as defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        method = try container.decodeIfPresent(VideoPostProcessingMethod.self, forKey: .method) ?? .recode
        format = try container.decodeIfPresent(VideoPostProcessingFormat.self, forKey: .format) ?? .mp4
        codec = try container.decodeIfPresent(VideoPostProcessingCodec.self, forKey: .codec) ?? .auto
        encoder = try container.decodeIfPresent(VideoPostProcessingEncoder.self, forKey: .encoder) ?? .auto
        quality = try container.decodeIfPresent(VideoPostProcessingQuality.self, forKey: .quality) ?? .high
        hardwareDecoding = try container.decodeIfPresent(Bool.self, forKey: .hardwareDecoding) ?? true
        alwaysReencode = try container.decodeIfPresent(Bool.self, forKey: .alwaysReencode) ?? false
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            enabled: defaults.bool(forKey: enabledKey),
            method: VideoPostProcessingMethod(rawValue: defaults.string(forKey: methodKey) ?? "") ?? .recode,
            format: VideoPostProcessingFormat(rawValue: defaults.string(forKey: formatKey) ?? "") ?? .mp4,
            codec: VideoPostProcessingCodec(rawValue: defaults.string(forKey: codecKey) ?? "") ?? .auto,
            encoder: VideoPostProcessingEncoder(rawValue: defaults.string(forKey: encoderKey) ?? "") ?? .auto,
            quality: VideoPostProcessingQuality(rawValue: defaults.string(forKey: qualityKey) ?? "") ?? .high,
            hardwareDecoding: defaults.object(forKey: hardwareDecodingKey) as? Bool ?? true,
            alwaysReencode: defaults.bool(forKey: alwaysReencodeKey)
        )
    }

    /// The codec used for the selected format, replacing choices the container cannot hold.
    var resolvedCodec: VideoPostProcessingCodec {
        format.supportedCodecs.contains(codec) ? codec : format.defaultCodec
    }

    /// The encoder used for the resolved codec. Auto prefers Apple's hardware encoder.
    var resolvedEncoder: VideoPostProcessingEncoder {
        let available = resolvedCodec.availableEncoders
        if available.contains(encoder) {
            return encoder
        }
        return available.first ?? .software
    }

    var resolvedFFmpegEncoder: String {
        resolvedCodec.ffmpegEncoder(resolvedEncoder) ?? ""
    }

    func configurationJSON(for preset: DownloadPreset) -> String {
        guard enabled, preset != .audio, preset != .images,
              let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
