import Foundation

enum DownloadPreset: String, Codable {
    case autoVideo = "auto_video"
    case mute = "mute"
    case audio = "audio"
    case custom = "custom"

    var pythonValue: String { rawValue }
}
