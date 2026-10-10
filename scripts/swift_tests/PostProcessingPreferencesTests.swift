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

    func testFreshInstallUsesAppleHardwareEncoding() throws {
        let suiteName = "PostProcessingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PostProcessingPreferences.load(from: defaults)

        XCTAssertEqual(preferences.codec, .auto)
        XCTAssertEqual(preferences.encoder, .auto)
        XCTAssertEqual(preferences.quality, .high)
        XCTAssertTrue(preferences.hardwareDecoding)
        XCTAssertFalse(preferences.alwaysReencode)
        XCTAssertEqual(preferences.resolvedEncoder, .hardware)
        XCTAssertEqual(preferences.resolvedFFmpegEncoder, "h264_videotoolbox")
    }

    func testCodecAndEncoderResolveForEachContainer() {
        let cases: [(VideoPostProcessingFormat, VideoPostProcessingCodec, VideoPostProcessingEncoder, String)] = [
            (.mp4, .auto, .auto, "h264_videotoolbox"),
            (.mp4, .hevc, .auto, "hevc_videotoolbox"),
            (.webm, .auto, .auto, "libvpx-vp9"),
            (.webm, .vp8, .hardware, "libvpx"),
            (.avi, .auto, .auto, "mpeg4"),
            (.mov, .prores, .auto, "prores_videotoolbox"),
            (.mov, .prores, .software, "prores_ks"),
            (.mp4, .vp8, .auto, "h264_videotoolbox"),
            (.webm, .h264, .software, "libvpx-vp9"),
        ]
        for (format, codec, encoder, expected) in cases {
            let preferences = PostProcessingPreferences(enabled: true, format: format, codec: codec, encoder: encoder)
            XCTAssertEqual(preferences.resolvedFFmpegEncoder, expected, "\(format) \(codec) \(encoder)")
        }
    }

    func testEveryCodecHasAnEncoderForItsContainers() {
        for format in VideoPostProcessingFormat.allCases {
            XCTAssertTrue(format.supportedCodecs.contains(format.defaultCodec))
            for codec in format.supportedCodecs {
                XCTAssertFalse(codec.availableEncoders.isEmpty)
                for encoder in codec.availableEncoders {
                    XCTAssertNotNil(codec.ffmpegEncoder(encoder))
                }
            }
        }
    }

    func testLegacySnapshotDecodesWithEncodingDefaults() throws {
        let data = Data(#"{"enabled":true,"method":"recode","format":"mov"}"#.utf8)

        let preferences = try JSONDecoder().decode(PostProcessingPreferences.self, from: data)

        XCTAssertEqual(preferences, PostProcessingPreferences(enabled: true, method: .recode, format: .mov))
    }

    func testEncodingSettingsReachConfiguration() throws {
        let preferences = PostProcessingPreferences(
            enabled: true,
            format: .mkv,
            codec: .hevc,
            encoder: .hardware,
            quality: .low,
            hardwareDecoding: false,
            alwaysReencode: true
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(preferences.configurationJSON(for: .autoVideo).utf8))
                as? [String: Any]
        )

        XCTAssertEqual(json["codec"] as? String, "hevc")
        XCTAssertEqual(json["encoder"] as? String, "hardware")
        XCTAssertEqual(json["quality"] as? String, "low")
        XCTAssertEqual(json["hardwareDecoding"] as? Bool, false)
        XCTAssertEqual(json["alwaysReencode"] as? Bool, true)
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
        defaults.set("invalid", forKey: PostProcessingPreferences.codecKey)
        defaults.set("invalid", forKey: PostProcessingPreferences.encoderKey)
        defaults.set("invalid", forKey: PostProcessingPreferences.qualityKey)

        let preferences = PostProcessingPreferences.load(from: defaults)

        XCTAssertEqual(preferences.method, .recode)
        XCTAssertEqual(preferences.format, .mp4)
        XCTAssertEqual(preferences.codec, .auto)
        XCTAssertEqual(preferences.encoder, .auto)
        XCTAssertEqual(preferences.quality, .high)
        XCTAssertFalse(preferences.enabled)
    }
}
