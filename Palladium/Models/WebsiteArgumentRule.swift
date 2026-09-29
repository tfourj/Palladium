import Foundation

enum WebsiteArgumentMatchType: String, Codable, CaseIterable, Identifiable {
    case website
    case regex

    var id: String { rawValue }
}

struct WebsiteArgumentRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var matchType: WebsiteArgumentMatchType = .website
    var pattern = ""
    var arguments = ""
    var isEnabled = true

    var trimmedArguments: String {
        arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        switch matchType {
        case .website:
            return WebsiteArgumentRules.normalizedWebsite(pattern) != nil
        case .regex:
            return WebsiteArgumentRules.regularExpression(pattern) != nil
        }
    }
}

enum WebsiteArgumentRules {
    static let defaultsKey = "palladium.websiteArgumentRules"

    static func load(from defaults: UserDefaults = .standard) -> [WebsiteArgumentRule] {
        guard let data = defaults.data(forKey: defaultsKey),
              let rules = try? JSONDecoder().decode([WebsiteArgumentRule].self, from: data) else {
            return []
        }
        return rules
    }

    static func save(_ rules: [WebsiteArgumentRule], to defaults: UserDefaults = .standard) {
        if rules.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Regex rules are checked first in list order. Otherwise the most specific website wins,
    /// so `test.example.com` is used before `example.com`.
    static func matchingRule(for link: String, in rules: [WebsiteArgumentRule]) -> WebsiteArgumentRule? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeRules = rules.filter { $0.isEnabled && !$0.trimmedArguments.isEmpty }

        let regexRule = activeRules.first { rule in
            guard rule.matchType == .regex, let expression = regularExpression(rule.pattern) else {
                return false
            }
            let range = NSRange(link.startIndex..., in: link)
            return expression.firstMatch(in: link, range: range) != nil
        }
        if let regexRule {
            return regexRule
        }

        let hosts = candidateHosts(for: link)
        guard !hosts.isEmpty else { return nil }

        var bestMatch: (rule: WebsiteArgumentRule, specificity: Int)?
        for rule in activeRules where rule.matchType == .website {
            guard let website = normalizedWebsite(rule.pattern),
                  hosts.contains(where: { $0 == website || $0.hasSuffix(".\(website)") }) else {
                continue
            }
            let specificity = website.split(separator: ".").count
            if specificity > bestMatch?.specificity ?? 0 {
                bestMatch = (rule, specificity)
            }
        }
        return bestMatch?.rule
    }

    /// Accepts plain domains, pasted links, and `*.` prefixes, returning a bare lowercase host.
    static func normalizedWebsite(_ pattern: String) -> String? {
        var value = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("://") {
            value = URL(string: value)?.host(percentEncoded: false) ?? ""
        } else if let pathStart = value.firstIndex(where: { "/?#:".contains($0) }) {
            value = String(value[..<pathStart])
        }
        if value.hasPrefix("*.") {
            value.removeFirst(2)
        }
        value = stripWWW(value.trimmingCharacters(in: CharacterSet(charactersIn: ".")))

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy(allowed.contains),
              !value.contains("..") else {
            return nil
        }
        return value
    }

    static func regularExpression(_ pattern: String) -> NSRegularExpression? {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func candidateHosts(for link: String) -> [String] {
        var url = URL(string: link)
        if url?.host(percentEncoded: false) == nil {
            url = URL(string: "https://\(link)")
        }
        guard let rawHost = url?.host(percentEncoded: false) else { return [] }

        let host = stripWWW(rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        guard !host.isEmpty else { return [] }

        var hosts = [host]
        if let canonicalHost = DownloadServiceDomain.canonicalHost(for: url), !hosts.contains(canonicalHost) {
            hosts.append(canonicalHost)
        }
        return hosts
    }

    private static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
