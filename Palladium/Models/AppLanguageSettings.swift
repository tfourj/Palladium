import Foundation
import Observation

// Both the observation registrar and UserDefaults support reads from background tasks.
nonisolated final class AppLanguageSettings: Observable {
    static let shared = AppLanguageSettings()
    static let defaultsKey = "palladium.appLanguage"
    static let system = "system"

    private let registrar = ObservationRegistrar()
    private let defaults: UserDefaults
    private let resourceBundle: Bundle

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.resourceBundle = bundle
    }

    var availableLanguages: [String] {
        ["en"] + resourceBundle.localizations.filter { $0 != "en" && $0 != "Base" }.sorted()
    }

    var selection: String {
        get {
            registrar.access(self, keyPath: \.selection)
            let saved = defaults.string(forKey: Self.defaultsKey) ?? Self.system
            return availableLanguages.contains(saved) ? saved : Self.system
        }
        set {
            registrar.withMutation(of: self, keyPath: \.selection) {
                defaults.set(availableLanguages.contains(newValue) ? newValue : Self.system, forKey: Self.defaultsKey)
            }
        }
    }

    var languageCode: String {
        Self.resolve(selection: selection, preferredLanguages: Locale.preferredLanguages,
                     availableLanguages: availableLanguages)
    }

    var locale: Locale { Locale(identifier: languageCode) }

    var localizedBundle: Bundle {
        let path = resourceBundle.path(forResource: languageCode, ofType: "lproj")
            ?? resourceBundle.path(forResource: "en", ofType: "lproj")
        return path.flatMap(Bundle.init(path:)) ?? resourceBundle
    }

    func refreshSystemLanguage() {
        // Notify string-producing views as well as SwiftUI labels after returning from Settings.
        registrar.withMutation(of: self, keyPath: \.selection) {}
    }

    static func resolve(selection: String, preferredLanguages: [String], availableLanguages: [String]) -> String {
        let supported = ["en"] + availableLanguages.filter { $0 != "en" && $0 != "Base" }.sorted()
        if supported.contains(selection) { return selection }
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferredLanguages).first ?? "en"
    }

    static func nativeName(for language: String) -> String {
        Locale(identifier: language).localizedString(forIdentifier: language) ?? language
    }
}

extension Bundle {
    // String(localized:locale:) formats values but does not select a different language bundle.
    nonisolated static var app: Bundle { AppLanguageSettings.shared.localizedBundle }
}
