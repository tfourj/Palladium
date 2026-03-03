import Foundation

enum DownloadPreset: String, Codable {
    case autoVideo = "auto_video"
    case mute = "mute"
    case audio = "audio"

    var pythonValue: String { rawValue }
}

struct DownloadSettings: Codable, Equatable {
    var targetProfile: DownloadTargetProfile = .automatic
    var container: DownloadContainer = .automatic
    var maxResolution: DownloadMaxResolution = .source
    var audioFormat: AudioFormatOption = .automatic
    var audioQuality: AudioQualityOption = .automatic
    var noPlaylist: Bool = true
    var embedSubtitles: Bool = false

    var jsonString: String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

enum DownloadTargetProfile: String, Codable, CaseIterable, Identifiable {
    case automatic
    case mp3
    case aac
    case mp4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "None"
        case .mp3: return "MP3 template"
        case .aac: return "AAC template"
        case .mp4: return "MP4 template"
        }
    }
}

enum DownloadContainer: String, Codable, CaseIterable, Identifiable {
    case automatic
    case avi
    case flv
    case gif
    case mkv
    case mov
    case mp4
    case webm
    case aac
    case aiff
    case alac
    case flac
    case m4a
    case mka
    case mp3
    case ogg
    case opus
    case vorbis
    case wav

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .avi: return "AVI"
        case .flv: return "FLV"
        case .gif: return "GIF"
        case .mkv: return "MKV"
        case .mov: return "MOV"
        case .mp4: return "MP4"
        case .webm: return "WEBM"
        case .aac: return "AAC"
        case .aiff: return "AIFF"
        case .alac: return "ALAC"
        case .flac: return "FLAC"
        case .m4a: return "M4A"
        case .mka: return "MKA"
        case .mp3: return "MP3"
        case .ogg: return "OGG"
        case .opus: return "OPUS"
        case .vorbis: return "VORBIS"
        case .wav: return "WAV"
        }
    }
}

enum DownloadMaxResolution: String, Codable, CaseIterable, Identifiable {
    case source
    case p2160
    case p1440
    case p1080
    case p720
    case p480
    case p360

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .p2160: return "2160p"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        }
    }
}

enum AudioFormatOption: String, Codable, CaseIterable, Identifiable {
    case automatic
    case best
    case aac
    case alac
    case flac
    case m4a
    case mp3
    case opus
    case vorbis
    case wav

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .best: return "Best"
        case .aac: return "AAC"
        case .alac: return "ALAC"
        case .flac: return "FLAC"
        case .m4a: return "M4A"
        case .mp3: return "MP3"
        case .opus: return "OPUS"
        case .vorbis: return "VORBIS"
        case .wav: return "WAV"
        }
    }
}

enum AudioQualityOption: String, Codable, CaseIterable, Identifiable {
    case automatic
    case q0
    case q1
    case q2
    case q3
    case q4
    case q5
    case q6
    case q7
    case q8
    case q9
    case q10
    case k64
    case k96
    case k128
    case k160
    case k192
    case k256
    case k320

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .q0: return "0 (best VBR)"
        case .q1: return "1"
        case .q2: return "2"
        case .q3: return "3"
        case .q4: return "4"
        case .q5: return "5 (default)"
        case .q6: return "6"
        case .q7: return "7"
        case .q8: return "8"
        case .q9: return "9"
        case .q10: return "10 (worst VBR)"
        case .k64: return "64K"
        case .k96: return "96K"
        case .k128: return "128K"
        case .k160: return "160K"
        case .k192: return "192K"
        case .k256: return "256K"
        case .k320: return "320K"
        }
    }
}
