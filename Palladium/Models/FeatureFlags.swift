import Foundation

enum FeatureFlags {
    static let isURLAllowlistEnabled = booleanValue(
        forInfoDictionaryKey: "ALLOWLIST_ENABLED",
        defaultValue: true
    )

    private static func booleanValue(forInfoDictionaryKey key: String, defaultValue: Bool) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) else {
            return defaultValue
        }

        if let boolean = value as? Bool {
            return boolean
        }

        if let string = value as? String {
            return (string as NSString).boolValue
        }

        return defaultValue
    }
}
