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
        case .autoVideo: return "Auto"
        case .mute: return "Mute"
        case .audio: return "Audio"
        case .custom: return "Custom"
        }
    }
}
