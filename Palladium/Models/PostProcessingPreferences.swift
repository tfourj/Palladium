import Foundation

enum VideoPostProcessingMethod: String, Codable, CaseIterable, Identifiable {
    case recode
    case remux

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recode: return String(localized: "settings.post_processing.recode")
        case .remux: return String(localized: "settings.post_processing.remux")
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

}

struct PostProcessingPreferences: Codable, Equatable {
    static let enabledKey = "palladium.postProcessingEnabled"
    static let methodKey = "palladium.postProcessingMethod"
    static let formatKey = "palladium.postProcessingFormat"

    var enabled = false
    var method: VideoPostProcessingMethod = .recode
    var format: VideoPostProcessingFormat = .mp4

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            enabled: defaults.bool(forKey: enabledKey),
            method: VideoPostProcessingMethod(rawValue: defaults.string(forKey: methodKey) ?? "") ?? .recode,
            format: VideoPostProcessingFormat(rawValue: defaults.string(forKey: formatKey) ?? "") ?? .mp4
        )
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
