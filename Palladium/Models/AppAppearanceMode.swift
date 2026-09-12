import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return String(localized: "appearance.system", bundle: .app)
        case .dark:
            return String(localized: "appearance.dark", bundle: .app)
        case .light:
            return String(localized: "appearance.light", bundle: .app)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}
