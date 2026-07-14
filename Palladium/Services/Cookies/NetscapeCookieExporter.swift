import Foundation

enum NetscapeCookieExporter {
    static func text(from cookies: [HTTPCookie], now: Date = Date()) throws -> String {
        let records = cookies
            .filter { cookie in
                guard let expiresDate = cookie.expiresDate else { return true }
                return expiresDate > now
            }
            .sorted(by: cookieSortOrder)
            .compactMap(netscapeRecord)

        guard !records.isEmpty else {
            throw NSError(
                domain: "PalladiumCookies",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "cookies.error.web_no_cookies")]
            )
        }

        return (["# Netscape HTTP Cookie File"] + records).joined(separator: "\n") + "\n"
    }

    nonisolated private static func cookieSortOrder(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
        let leftKey = [lhs.domain, lhs.path, lhs.name]
        let rightKey = [rhs.domain, rhs.path, rhs.name]
        return leftKey.lexicographicallyPrecedes(rightKey)
    }

    nonisolated private static func netscapeRecord(for cookie: HTTPCookie) -> String? {
        let domain = cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = cookie.path.isEmpty ? "/" : cookie.path

        guard !domain.isEmpty,
              isValidField(domain),
              isValidField(path),
              isValidField(cookie.name),
              isValidField(cookie.value) else {
            return nil
        }

        let exportedDomain = cookie.isHTTPOnly ? "#HttpOnly_\(domain)" : domain
        let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
        let secure = cookie.isSecure ? "TRUE" : "FALSE"
        let expiration = cookie.expiresDate.map {
            String(max(0, Int64($0.timeIntervalSince1970.rounded(.down))))
        } ?? "0"

        return [
            exportedDomain,
            includeSubdomains,
            path,
            secure,
            expiration,
            cookie.name,
            cookie.value,
        ].joined(separator: "\t")
    }

    nonisolated private static func isValidField(_ value: String) -> Bool {
        !value.contains { character in
            character == "\t" || character == "\r" || character == "\n"
        }
    }
}
