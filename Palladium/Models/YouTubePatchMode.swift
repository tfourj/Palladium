import Foundation

enum YouTubePatchMode: String, CaseIterable, Identifiable {
    case ejs
    case webkit
    case both
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ejs:
            return String(localized: "settings.advanced.youtube_patch_mode.ejs")
        case .webkit:
            return String(localized: "settings.advanced.youtube_patch_mode.webkit")
        case .both:
            return String(localized: "settings.advanced.youtube_patch_mode.both")
        case .off:
            return String(localized: "settings.advanced.youtube_patch_mode.off")
        }
    }
}
