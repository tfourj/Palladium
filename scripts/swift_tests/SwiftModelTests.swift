import Darwin
import Foundation

@main
enum SwiftModelTests {
    private struct ServiceDomainTestCase {
        let source: String?
        let expectedHost: String?
    }

    static func main() {
        var failures: [String] = []
        failures.append(contentsOf: serviceDomainFailures())
        failures.append(contentsOf: temporaryDownloadRetentionFailures())

        guard failures.isEmpty else {
            for failure in failures {
                FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
            }
            exit(EXIT_FAILURE)
        }

        print("Passed 18 Swift model tests")
    }

    private static func serviceDomainFailures() -> [String] {
        let testCases = [
            ServiceDomainTestCase(source: nil, expectedHost: nil),
            ServiceDomainTestCase(source: "https://tiktok.com/@creator/video/1", expectedHost: "tiktok.com"),
            ServiceDomainTestCase(source: "https://www.tiktok.com/@creator/video/1", expectedHost: "tiktok.com"),
            ServiceDomainTestCase(source: "https://vm.tiktok.com/example", expectedHost: "tiktok.com"),
            ServiceDomainTestCase(source: "https://vt.tiktok.com/example", expectedHost: "tiktok.com"),
            ServiceDomainTestCase(source: "https://youtube.com/watch?v=example", expectedHost: "youtube.com"),
            ServiceDomainTestCase(source: "https://m.youtube.com/watch?v=example", expectedHost: "youtube.com"),
            ServiceDomainTestCase(source: "https://music.youtube.com/watch?v=example", expectedHost: "youtube.com"),
            ServiceDomainTestCase(source: "https://youtu.be/example", expectedHost: "youtube.com"),
            ServiceDomainTestCase(
                source: "https://www.youtube-nocookie.com/embed/example",
                expectedHost: "youtube.com"
            ),
            ServiceDomainTestCase(source: "https://media.example.com/video", expectedHost: "example.com"),
            ServiceDomainTestCase(source: "https://news.bbc.co.uk/video", expectedHost: "bbc.co.uk"),
            ServiceDomainTestCase(source: "https://127.0.0.1/video", expectedHost: "127.0.0.1"),
            ServiceDomainTestCase(source: "https://[2001:db8::1]/video", expectedHost: "2001:db8::1"),
        ]

        var failures: [String] = []
        for testCase in testCases {
            let sourceURL = testCase.source.flatMap(URL.init(string:))
            let actualHost = DownloadServiceDomain.canonicalHost(for: sourceURL)
            guard actualHost != testCase.expectedHost else { continue }
            failures.append(
                "\(testCase.source ?? "nil"): expected \(testCase.expectedHost ?? "nil"), "
                    + "received \(actualHost ?? "nil")"
            )
        }
        return failures
    }

    private static func temporaryDownloadRetentionFailures() -> [String] {
        let testCases = [
            (showsTemporaryDownloads: false, resultAllowsCleanup: true, expectedRemoval: true),
            (showsTemporaryDownloads: true, resultAllowsCleanup: true, expectedRemoval: false),
            (showsTemporaryDownloads: false, resultAllowsCleanup: false, expectedRemoval: false),
            (showsTemporaryDownloads: true, resultAllowsCleanup: false, expectedRemoval: false),
        ]

        var failures: [String] = []
        for testCase in testCases {
            let actualRemoval = TemporaryDownloadRetentionPolicy.shouldRemoveSource(
                showsTemporaryDownloads: testCase.showsTemporaryDownloads,
                resultAllowsCleanup: testCase.resultAllowsCleanup
            )
            guard actualRemoval != testCase.expectedRemoval else { continue }
            failures.append(
                "retention policy with show-temp=\(testCase.showsTemporaryDownloads), "
                    + "cleanup-allowed=\(testCase.resultAllowsCleanup): "
                    + "expected removal \(testCase.expectedRemoval), received \(actualRemoval)"
            )
        }
        return failures
    }
}
