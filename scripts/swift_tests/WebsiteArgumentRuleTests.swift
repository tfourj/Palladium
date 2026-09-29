import Foundation
import XCTest
@testable import Palladium

final class WebsiteArgumentRuleTests: XCTestCase {
    func testWebsiteRuleMatchesDomainAndSubdomains() {
        let rules = [website("example.com", arguments: "--no-mtime")]

        XCTAssertEqual(match("https://example.com/video", rules), "example.com")
        XCTAssertEqual(match("https://www.example.com/video", rules), "example.com")
        XCTAssertEqual(match("https://media.example.com/video", rules), "example.com")
        XCTAssertNil(match("https://notexample.com/video", rules))
        XCTAssertNil(match("https://example.com.evil.net/video", rules))
    }

    func testMostSpecificWebsiteRuleWinsRegardlessOfOrder() {
        let rules = [
            website("example.com", arguments: "--no-mtime"),
            website("test.example.com", arguments: "--limit-rate 5M"),
        ]

        XCTAssertEqual(match("https://test.example.com/video", rules), "test.example.com")
        XCTAssertEqual(match("https://a.test.example.com/video", rules), "test.example.com")
        XCTAssertEqual(match("https://other.example.com/video", rules), "example.com")
    }

    func testFirstWebsiteRuleWinsTies() {
        let first = website("example.com", arguments: "--first")
        let second = website("www.example.com", arguments: "--second")

        let rule = WebsiteArgumentRules.matchingRule(for: "https://example.com", in: [first, second])

        XCTAssertEqual(rule?.id, first.id)
    }

    func testRegexRulesTakePriorityInListOrder() {
        let rules = [
            website("test.example.com", arguments: "--website"),
            regex("^https://test\\.example\\.com/live/", arguments: "--live"),
            regex("example\\.com", arguments: "--any"),
        ]

        XCTAssertEqual(match("https://TEST.example.com/live/1", rules), "^https://test\\.example\\.com/live/")
        XCTAssertEqual(match("https://test.example.com/watch/1", rules), "example\\.com")
    }

    func testDisabledEmptyAndInvalidRulesAreSkipped() {
        var disabled = website("example.com", arguments: "--disabled")
        disabled.isEnabled = false
        let rules = [
            disabled,
            website("example.com", arguments: "   "),
            regex("([", arguments: "--broken"),
            website("example.com", arguments: "--used"),
        ]

        let rule = WebsiteArgumentRules.matchingRule(for: "https://example.com", in: rules)

        XCTAssertEqual(rule?.arguments, "--used")
    }

    func testYouTubeAliasMatchesYouTubeWebsite() {
        let rules = [website("youtube.com", arguments: "--no-mtime")]

        XCTAssertEqual(match("https://youtu.be/example", rules), "youtube.com")
        XCTAssertEqual(match("youtube.com/watch?v=example", rules), "youtube.com")
    }

    func testWebsiteNormalizationAcceptsCommonInput() {
        XCTAssertEqual(WebsiteArgumentRules.normalizedWebsite(" Example.com "), "example.com")
        XCTAssertEqual(WebsiteArgumentRules.normalizedWebsite("https://www.example.com/path"), "example.com")
        XCTAssertEqual(WebsiteArgumentRules.normalizedWebsite("*.test.example.com"), "test.example.com")
        XCTAssertEqual(WebsiteArgumentRules.normalizedWebsite("example.com/watch"), "example.com")
        XCTAssertNil(WebsiteArgumentRules.normalizedWebsite(""))
        XCTAssertNil(WebsiteArgumentRules.normalizedWebsite("exa mple.com"))
    }

    func testRulesPersist() throws {
        let suiteName = "WebsiteArgumentRuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rules = [
            website("example.com", arguments: "--no-mtime"),
            regex("example\\.org", arguments: "--limit-rate 5M"),
        ]

        WebsiteArgumentRules.save(rules, to: defaults)
        XCTAssertEqual(WebsiteArgumentRules.load(from: defaults), rules)

        WebsiteArgumentRules.save([], to: defaults)
        XCTAssertNil(defaults.object(forKey: WebsiteArgumentRules.defaultsKey))
        XCTAssertEqual(WebsiteArgumentRules.load(from: defaults), [])
    }

    private func website(_ pattern: String, arguments: String) -> WebsiteArgumentRule {
        WebsiteArgumentRule(matchType: .website, pattern: pattern, arguments: arguments)
    }

    private func regex(_ pattern: String, arguments: String) -> WebsiteArgumentRule {
        WebsiteArgumentRule(matchType: .regex, pattern: pattern, arguments: arguments)
    }

    private func match(_ link: String, _ rules: [WebsiteArgumentRule]) -> String? {
        WebsiteArgumentRules.matchingRule(for: link, in: rules)?.pattern
    }
}
