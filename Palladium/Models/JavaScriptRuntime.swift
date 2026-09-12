import Foundation

enum JavaScriptRuntime: String, CaseIterable, Identifiable {
    case webkit
    case quickjs

    static let defaultsKey = "palladium.javascriptRuntime"
    static let defaultValue = JavaScriptRuntime.webkit

    var id: String { rawValue }

    static var selected: JavaScriptRuntime {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}
