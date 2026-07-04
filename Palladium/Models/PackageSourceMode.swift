import Foundation

enum PackageAction: String {
    case check
    case versions
    case update
    case reinstall
    case indexVersions = "index_versions"
    case installPayloadZip = "install_payload_zip"

    var initialStatusText: String {
        switch self {
        case .installPayloadZip:
            return "installing"
        case .update, .reinstall:
            return "updating"
        case .indexVersions:
            return "indexing"
        case .check, .versions:
            return "checking"
        }
    }
}

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
    curl-cffi
    gallery-dl
    pip
    """
}
