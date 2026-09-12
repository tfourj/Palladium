import Observation
import XCTest
@testable import Palladium

final class AppLanguageSettingsTests: XCTestCase {
    func testSystemMatchesRegionalLanguageAndFallsBackToEnglish() {
        XCTAssertEqual(resolve("system", ["ja-JP"]), "ja")
        XCTAssertEqual(resolve("system", ["en-GB"]), "en")
        XCTAssertEqual(resolve("system", ["sl-SI"]), "en")
        XCTAssertEqual(resolve("system", []), "en")
        XCTAssertEqual(resolve("system", ["fr-FR", "ja-JP", "en-US"]), "ja")
    }

    func testExplicitSelectionOverridesSystemLanguage() {
        XCTAssertEqual(resolve("en", ["ja-JP"]), "en")
        XCTAssertEqual(resolve("ja", ["en-US"]), "ja")
        XCTAssertEqual(resolve("removed-language", ["ja-JP"]), "ja")
    }

    func testSelectionPersistsAndSystemCanBeRestored() throws {
        let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let language = AppLanguageSettings(defaults: defaults)

        XCTAssertEqual(language.selection, "system")
        language.selection = "ja"
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).selection, "ja")
        XCTAssertEqual(String(localized: "tab.settings", bundle: language.localizedBundle), "設定")
        language.selection = "en"
        XCTAssertEqual(String(localized: "tab.settings", bundle: language.localizedBundle), "Settings")
        language.selection = "system"
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).selection, "system")
        defaults.set("unsupported", forKey: AppLanguageSettings.defaultsKey)
        XCTAssertEqual(language.selection, "system")
    }

    func testStringLookupsNotifyViewsWhenLanguageChanges() throws {
        let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let language = AppLanguageSettings(defaults: defaults)
        let changed = expectation(description: "Localized strings invalidate their observing views")

        withObservationTracking {
            _ = language.localizedBundle
        } onChange: {
            changed.fulfill()
        }
        language.selection = "ja"
        wait(for: [changed], timeout: 1)
    }

    private func resolve(_ selection: String, _ preferredLanguages: [String]) -> String {
        AppLanguageSettings.resolve(selection: selection, preferredLanguages: preferredLanguages,
                                    availableLanguages: ["ja", "Base", "en"])
    }
}
