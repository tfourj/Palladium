import Foundation

enum JavaScriptRuntime: String, CaseIterable, Identifiable {
    case webkit
    case quickjs

    static let defaultsKey = "palladium.javascriptRuntime"
    static let defaultValue = JavaScriptRuntime.webkit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webkit:
            return String(localized: "settings.advanced.javascript_runtime.webkit", bundle: .app)
        case .quickjs:
            return String(localized: "settings.advanced.javascript_runtime.quickjs", bundle: .app)
        }
    }

    static var selected: JavaScriptRuntime {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}
