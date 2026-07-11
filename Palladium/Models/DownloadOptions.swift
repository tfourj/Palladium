import Foundation

enum VideoDownloadQuality: String, CaseIterable, Identifiable {
    case best
    case p2160
    case p1440
    case p1080
    case p720
    case p480

    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: return String(localized: "download.quality.best")
        case .p2160: return "4K"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        }
    }
    var maximumHeight: Int? {
        switch self {
        case .best: return nil
        case .p2160: return 2160
        case .p1440: return 1440
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

enum VideoDownloadContainer: String, CaseIterable, Identifiable {
    case mp4
    case mov
    case mkv

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum VideoDownloadCodec: String, CaseIterable, Identifiable {
    case photosCompatible
    case h264
    case h265
    case av1
    case vp9
    case best

    var id: String { rawValue }
    var title: String {
        switch self {
        case .photosCompatible: return "H.264 / H.265 (Photos)"
        case .h264: return "H.264"
        case .h265: return "H.265 / HEVC"
        case .av1: return "AV1"
        case .vp9: return "VP9"
        case .best: return String(localized: "download.quality.best_available")
        }
    }
    var formatFilter: String? {
        switch self {
        case .photosCompatible: return "vcodec~='^(avc1|avc3|h264|hev1|hvc1|hevc)'"
        case .h264: return "vcodec~='^(avc1|avc3|h264)'"
        case .h265: return "vcodec~='^(hev1|hvc1|hevc)'"
        case .av1: return "vcodec~='^(av01|av1)'"
        case .vp9: return "vcodec~='^(vp09|vp9)'"
        case .best: return nil
        }
    }
}

enum AudioDownloadFormat: String, CaseIterable, Identifiable {
    case mp3
    case m4a
    case opus
    case flac
    case wav

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum AudioDownloadQuality: String, CaseIterable, Identifiable {
    case best
    case kbps320
    case kbps256
    case kbps192
    case kbps128

    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: return String(localized: "download.quality.best")
        case .kbps320: return "320 kbps"
        case .kbps256: return "256 kbps"
        case .kbps192: return "192 kbps"
        case .kbps128: return "128 kbps"
        }
    }
    var ytDLPValue: String? {
        switch self {
        case .best: return nil
        case .kbps320: return "320K"
        case .kbps256: return "256K"
        case .kbps192: return "192K"
        case .kbps128: return "128K"
        }
    }
}

struct DownloadQualityPreferences {
    static let videoQualityKey = "palladium.videoDownloadQuality"
    static let videoContainerKey = "palladium.videoDownloadContainer"
    static let videoCodecKey = "palladium.videoDownloadCodec"
    static let audioFormatKey = "palladium.audioDownloadFormat"
    static let audioQualityKey = "palladium.audioDownloadQuality"

    var videoQuality: VideoDownloadQuality = .best
    var videoContainer: VideoDownloadContainer = .mp4
    var videoCodec: VideoDownloadCodec = .photosCompatible
    var audioFormat: AudioDownloadFormat = .mp3
    var audioQuality: AudioDownloadQuality = .best

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            videoQuality: VideoDownloadQuality(rawValue: defaults.string(forKey: videoQualityKey) ?? "") ?? .best,
            videoContainer: VideoDownloadContainer(rawValue: defaults.string(forKey: videoContainerKey) ?? "") ?? .mp4,
            videoCodec: VideoDownloadCodec(rawValue: defaults.string(forKey: videoCodecKey) ?? "") ?? .photosCompatible,
            audioFormat: AudioDownloadFormat(rawValue: defaults.string(forKey: audioFormatKey) ?? "") ?? .mp3,
            audioQuality: AudioDownloadQuality(rawValue: defaults.string(forKey: audioQualityKey) ?? "") ?? .best
        )
    }

    func presetArguments() -> [String: String] {
        [
            "auto_video": videoArguments(includeAudio: true),
            "mute": videoArguments(includeAudio: false),
            "audio": audioArguments()
        ]
    }

    private func videoArguments(includeAudio: Bool) -> String {
        var filters: [String] = []
        if let codecFilter = videoCodec.formatFilter { filters.append(codecFilter) }
        if let height = videoQuality.maximumHeight { filters.append("height<=\(height)") }
        let filter = filters.map { "[\($0)]" }.joined()
        let fallback = includeAudio ? "b" : "bv/bestvideo"
        let format = includeAudio
            ? "bv*\(filter)+ba/b\(filter)/\(fallback)"
            : "bv\(filter)/\(fallback)"
        let sort = videoCodec == .photosCompatible || videoCodec == .h264
            ? "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac"
            : "lang,quality,res,fps,hdr:12,acodec:aac"
        return "-f \"\(format)\" --merge-output-format \(videoContainer.rawValue) "
            + "--remux-video \(videoContainer.rawValue) -S \"\(sort)\""
    }

    private func audioArguments() -> String {
        var arguments = "-f ba/b -x --audio-format \(audioFormat.rawValue)"
        if let quality = audioQuality.ytDLPValue {
            arguments += " --audio-quality \(quality)"
        }
        return arguments
    }
}

enum DownloadPreset: String, Codable, CaseIterable, Identifiable {
    case autoVideo = "auto_video"
    case mute = "mute"
    case audio = "audio"
    case images = "images"
    case custom = "custom"

    var id: String { rawValue }
    var pythonValue: String { rawValue }

    var shareSheetMode: ShareSheetDownloadMode {
        switch self {
        case .autoVideo: return .autoVideo
        case .mute: return .mute
        case .audio: return .audio
        case .images: return .images
        case .custom: return .custom
        }
    }

    static var defaultSettings: [DownloadPresetSetting] {
        allCases.map { DownloadPresetSetting(preset: $0, isVisible: $0 != .custom) }
    }

    var title: String {
        switch self {
        case .autoVideo: return String(localized: "download.preset.video")
        case .mute: return String(localized: "download.preset.mute")
        case .audio: return String(localized: "download.preset.audio")
        case .images: return String(localized: "download.preset.images")
        case .custom: return String(localized: "common.custom")
        }
    }

    var defaultArguments: String {
        switch self {
        case .autoVideo:
            return "--merge-output-format mp4 --remux-video mp4 -S vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac"
        case .mute:
            return "-f bv/bestvideo --merge-output-format mp4 --remux-video mp4 -S vcodec:h264,lang,quality,res,fps,hdr:12"
        case .audio:
            return "-f ba[acodec^=mp3]/ba/b -x --audio-format mp3"
        case .images:
            return ""
        case .custom:
            return ""
        }
    }
}

struct DownloadPresetSetting: Codable, Identifiable, Equatable {
    let preset: DownloadPreset
    var isVisible: Bool

    var id: String { preset.rawValue }
}

enum DownloadOptions {
    static func visiblePresets(from settings: [DownloadPresetSetting]) -> [DownloadPreset] {
        let visible = settings.filter { $0.isVisible }.map { $0.preset }
        return visible.isEmpty ? [.autoVideo] : visible
    }

    static func visibleShareSheetModes(from settings: [DownloadPresetSetting]) -> [ShareSheetDownloadMode] {
        [.ask] + visiblePresets(from: settings).map { $0.shareSheetMode }
    }
}

enum PostDownloadAction: String, Codable, CaseIterable, Identifiable {
    case saveToPhotos
    case openShareSheet
    case saveToApplicationFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveToPhotos: return String(localized: "photos.action.save")
        case .openShareSheet: return String(localized: "post_download.action.share.title")
        case .saveToApplicationFolder: return String(localized: "post_download.action.save_folder.title")
        }
    }

    var icon: String {
        switch self {
        case .saveToPhotos: return "photo.on.rectangle"
        case .openShareSheet: return "square.and.arrow.up"
        case .saveToApplicationFolder: return "folder"
        }
    }
}

enum AfterDownloadBehavior: String, Codable, CaseIterable, Identifiable {
    case ask
    case openShareSheet
    case saveToPhotos
    case saveToApplicationFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return String(localized: "common.ask")
        case .openShareSheet: return String(localized: "post_download.action.share.title")
        case .saveToPhotos: return String(localized: "photos.action.save")
        case .saveToApplicationFolder: return String(localized: "post_download.action.save_folder.title")
        }
    }

    var icon: String {
        switch self {
        case .ask: return "questionmark.circle"
        case .openShareSheet: return "square.and.arrow.up"
        case .saveToPhotos: return "photo.on.rectangle"
        case .saveToApplicationFolder: return "folder"
        }
    }

    var postDownloadAction: PostDownloadAction? {
        switch self {
        case .ask:
            return nil
        case .openShareSheet:
            return .openShareSheet
        case .saveToPhotos:
            return .saveToPhotos
        case .saveToApplicationFolder:
            return .saveToApplicationFolder
        }
    }
}

enum ShareSheetDownloadMode: String, Codable, CaseIterable, Identifiable {
    case ask
    case autoVideo = "auto_video"
    case audio
    case mute
    case custom
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return String(localized: "common.ask")
        case .autoVideo: return String(localized: "download.preset.video")
        case .audio: return String(localized: "download.preset.audio")
        case .mute: return String(localized: "download.preset.mute")
        case .custom: return String(localized: "common.custom")
        case .images: return String(localized: "download.preset.images")
        }
    }

    var preset: DownloadPreset? {
        switch self {
        case .ask:
            return nil
        case .autoVideo:
            return .autoVideo
        case .audio:
            return .audio
        case .mute:
            return .mute
        case .custom:
            return .custom
        case .images:
            return .images
        }
    }
}

enum SubtitleLanguageOption: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es.*"
    case french = "fr.*"
    case german = "de.*"
    case italian = "it.*"
    case portuguese = "pt.*"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh.*"
    case arabic = "ar.*"
    case russian = "ru.*"
    case custom = "__custom__"
    case allAvailable = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return String(localized: "subtitle.language.english")
        case .spanish:
            return String(localized: "subtitle.language.spanish")
        case .french:
            return String(localized: "subtitle.language.french")
        case .german:
            return String(localized: "subtitle.language.german")
        case .italian:
            return String(localized: "subtitle.language.italian")
        case .portuguese:
            return String(localized: "subtitle.language.portuguese")
        case .japanese:
            return String(localized: "subtitle.language.japanese")
        case .korean:
            return String(localized: "subtitle.language.korean")
        case .chinese:
            return String(localized: "subtitle.language.chinese")
        case .arabic:
            return String(localized: "subtitle.language.arabic")
        case .russian:
            return String(localized: "subtitle.language.russian")
        case .custom:
            return String(localized: "common.custom")
        case .allAvailable:
            return String(localized: "subtitle.language.all")
        }
    }

    var subtitlePattern: String { rawValue }
}
