import Foundation

enum DownloadPreset: String, Codable, CaseIterable, Identifiable {
    case autoVideo = "auto_video"
    case mute = "mute"
    case audio = "audio"
    case custom = "custom"

    var id: String { rawValue }
    var pythonValue: String { rawValue }

    var title: String {
        switch self {
        case .autoVideo: return "Video"
        case .mute: return "Mute"
        case .audio: return "Audio"
        case .custom: return "Custom"
        }
    }

    var defaultArguments: String {
        switch self {
        case .autoVideo:
            return "--merge-output-format mp4 --remux-video mp4 -S vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac"
        case .mute:
            return "-f bv*/bestvideo --merge-output-format mp4 --remux-video mp4 -S vcodec:h264,lang,quality,res,fps,hdr:12"
        case .audio:
            return "-f ba[acodec^=mp3]/ba/b -x --audio-format mp3"
        case .custom:
            return ""
        }
    }
}

enum PostDownloadAction: String, Codable, CaseIterable, Identifiable {
    case saveToPhotos
    case openShareSheet
    case saveToApplicationFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saveToPhotos: return "Save to Photos"
        case .openShareSheet: return "Open Share Sheet"
        case .saveToApplicationFolder: return "Save to App Folder"
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
        case .ask: return "Ask"
        case .openShareSheet: return "Open Share Sheet"
        case .saveToPhotos: return "Save to Photos"
        case .saveToApplicationFolder: return "Save to App Folder"
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask"
        case .autoVideo: return "Video"
        case .audio: return "Audio"
        case .mute: return "Mute"
        case .custom: return "Custom"
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
    case allAvailable = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        case .french:
            return "French"
        case .german:
            return "German"
        case .italian:
            return "Italian"
        case .portuguese:
            return "Portuguese"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .chinese:
            return "Chinese"
        case .arabic:
            return "Arabic"
        case .russian:
            return "Russian"
        case .allAvailable:
            return "All Available"
        }
    }

    var subtitlePattern: String { rawValue }
}
