import Foundation

enum DownloadServiceDomain {
    private static let aliases = [
        "youtu.be": "youtube.com",
        "youtube-nocookie.com": "youtube.com",
    ]

    private static let commonCountryCodeSecondLevelDomains: Set<String> = [
        "ac", "co", "com", "edu", "gov", "net", "org",
    ]

    static func canonicalHost(for sourceURL: URL?) -> String? {
        guard let rawHost = sourceURL?.host(percentEncoded: false) else { return nil }
        let host = rawHost
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return nil }
        guard !isIPAddress(host) else { return host }

        let serviceDomain = registrableDomain(from: host)
        return aliases[serviceDomain] ?? serviceDomain
    }

    private static func registrableDomain(from host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }

        let topLevelDomain = labels[labels.count - 1]
        let secondLevelDomain = labels[labels.count - 2]
        let usesCountryCodeSecondLevelDomain = topLevelDomain.count == 2
            && commonCountryCodeSecondLevelDomains.contains(secondLevelDomain)
        let retainedLabelCount = usesCountryCodeSecondLevelDomain ? 3 : 2
        return labels.suffix(retainedLabelCount).joined(separator: ".")
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return false }
        return labels.allSatisfy { label in
            guard let octet = Int(label) else { return false }
            return (0...255).contains(octet)
        }
    }
}
