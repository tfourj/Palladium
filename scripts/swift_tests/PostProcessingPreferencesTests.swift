import XCTest
@testable import Palladium

@MainActor
final class PostProcessingPreferencesTests: XCTestCase {
    func testFreshInstallDisablesConversion() throws {
        let suiteName = "PostProcessingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PostProcessingPreferences.load(from: defaults)

        XCTAssertFalse(preferences.enabled)
        XCTAssertEqual(preferences.configurationJSON(for: .autoVideo), "{}")
    }

    func testSavedSettingsReachVideoDownloadsOnly() throws {
        let suiteName = "PostProcessingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PostProcessingPreferences.enabledKey)
        defaults.set("remux", forKey: PostProcessingPreferences.methodKey)
        defaults.set("webm", forKey: PostProcessingPreferences.formatKey)

        let preferences = PostProcessingPreferences.load(from: defaults)

        for preset in [DownloadPreset.autoVideo, .mute, .custom] {
            let data = Data(preferences.configurationJSON(for: preset).utf8)
            XCTAssertEqual(try JSONDecoder().decode(PostProcessingPreferences.self, from: data), preferences)
        }
        XCTAssertEqual(preferences.configurationJSON(for: .audio), "{}")
        XCTAssertEqual(preferences.configurationJSON(for: .images), "{}")
    }

    func testWebMConversionConfigurationSupportsBothMethods() throws {
        XCTAssertTrue(VideoPostProcessingFormat.allCases.contains(.webm))
        for method in VideoPostProcessingMethod.allCases {
            let preferences = PostProcessingPreferences(enabled: true, method: method, format: .webm)
            let data = Data(preferences.configurationJSON(for: .autoVideo).utf8)
            XCTAssertEqual(try JSONDecoder().decode(PostProcessingPreferences.self, from: data), preferences)
        }
    }

    func testInvalidStoredValuesUseSafeDefaults() throws {
        let suiteName = "PostProcessingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("invalid", forKey: PostProcessingPreferences.methodKey)
        defaults.set("invalid", forKey: PostProcessingPreferences.formatKey)

        let preferences = PostProcessingPreferences.load(from: defaults)

        XCTAssertEqual(preferences.method, .recode)
        XCTAssertEqual(preferences.format, .mp4)
        XCTAssertFalse(preferences.enabled)
    }
}
