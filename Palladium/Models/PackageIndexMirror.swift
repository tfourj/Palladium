import Foundation

enum PackageIndexMirror: String, CaseIterable, Identifiable {
    case pypi
    case tsinghua
    case aliyun
    case custom

    static let defaultsKey = "palladium.packageIndexMirror"
    static let customURLDefaultsKey = "palladium.packageIndexCustomURL"
    static let defaultValue = PackageIndexMirror.pypi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pypi:
            return String(localized: "packages.index.pypi", bundle: .app)
        case .tsinghua:
            return String(localized: "packages.index.tsinghua", bundle: .app)
        case .aliyun:
            return String(localized: "packages.index.aliyun", bundle: .app)
        case .custom:
            return String(localized: "packages.index.custom", bundle: .app)
        }
    }

    /// Preset index URL; nil means pip's default index.
    var presetURL: String? {
        switch self {
        case .pypi, .custom:
            return nil
        case .tsinghua:
            return "https://pypi.tuna.tsinghua.edu.cn/simple"
        case .aliyun:
            return "https://mirrors.aliyun.com/pypi/simple/"
        }
    }

    /// Index URL passed to pip, or nil to keep pip's default index.
    func indexURL(customURL: String) -> String? {
        if self == .custom {
            return Self.normalizedCustomURL(customURL)
        }
        return presetURL
    }

    static func normalizedCustomURL(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func selected(in defaults: UserDefaults = .standard) -> PackageIndexMirror {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }

    static func selectedIndexURL(in defaults: UserDefaults = .standard) -> String? {
        selected(in: defaults).indexURL(customURL: defaults.string(forKey: customURLDefaultsKey) ?? "")
    }
}
