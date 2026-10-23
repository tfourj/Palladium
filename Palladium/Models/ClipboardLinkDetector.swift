import Foundation

enum ClipboardLinkDetector {
    private static let supportedSchemes: Set<String> = ["http", "https"]

    static func firstLink(in text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url, isSupported(url) else { continue }
            return url.absoluteString
        }
        return nil
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme) else {
            return false
        }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            return false
        }
        return true
    }
}
