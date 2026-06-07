import Foundation

enum PackageSourceMode: String, CaseIterable, Identifiable {
    case stable
    case nightly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return String(localized: "packages.source.stable")
        case .nightly:
            return String(localized: "packages.source.nightly")
        case .custom:
            return String(localized: "packages.source.custom")
        }
    }
}

enum PackageSourceDefaults {
    static let customSpecs = """
    yt-dlp
    yt-dlp-apple-webkit-jsi
    pip
    """
}
