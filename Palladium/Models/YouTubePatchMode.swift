import Foundation

enum YouTubePatchMode: String, CaseIterable, Identifiable {
    case webkit
    case ejs
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webkit:
            return String(localized: "settings.advanced.youtube_patch_mode.webkit", bundle: .app)
        case .ejs:
            return String(localized: "settings.advanced.youtube_patch_mode.ejs", bundle: .app)
        case .off:
            return String(localized: "settings.advanced.youtube_patch_mode.off", bundle: .app)
        }
    }
}
