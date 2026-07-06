import Foundation

enum YouTubePatchMode: String, CaseIterable, Identifiable {
    case webkit
    case ejs
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webkit:
            return String(localized: "settings.advanced.youtube_patch_mode.webkit")
        case .ejs:
            return String(localized: "settings.advanced.youtube_patch_mode.ejs")
        case .off:
            return String(localized: "settings.advanced.youtube_patch_mode.off")
        }
    }
}
