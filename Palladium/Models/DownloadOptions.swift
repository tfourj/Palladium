import Foundation

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
