import Darwin
import Foundation

@main
enum DownloadServiceDomainTests {
    private struct TestCase {
        let source: String?
        let expectedHost: String?
    }

    static func main() {
        let testCases = [
            TestCase(source: nil, expectedHost: nil),
            TestCase(source: "https://tiktok.com/@creator/video/1", expectedHost: "tiktok.com"),
            TestCase(source: "https://www.tiktok.com/@creator/video/1", expectedHost: "tiktok.com"),
            TestCase(source: "https://vm.tiktok.com/example", expectedHost: "tiktok.com"),
            TestCase(source: "https://vt.tiktok.com/example", expectedHost: "tiktok.com"),
            TestCase(source: "https://youtube.com/watch?v=example", expectedHost: "youtube.com"),
            TestCase(source: "https://m.youtube.com/watch?v=example", expectedHost: "youtube.com"),
            TestCase(source: "https://music.youtube.com/watch?v=example", expectedHost: "youtube.com"),
            TestCase(source: "https://youtu.be/example", expectedHost: "youtube.com"),
            TestCase(source: "https://www.youtube-nocookie.com/embed/example", expectedHost: "youtube.com"),
            TestCase(source: "https://media.example.com/video", expectedHost: "example.com"),
            TestCase(source: "https://news.bbc.co.uk/video", expectedHost: "bbc.co.uk"),
            TestCase(source: "https://127.0.0.1/video", expectedHost: "127.0.0.1"),
            TestCase(source: "https://[2001:db8::1]/video", expectedHost: "2001:db8::1"),
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

        guard failures.isEmpty else {
            for failure in failures {
                FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
            }
            exit(EXIT_FAILURE)
        }

        print("Passed \(testCases.count) download service domain tests")
    }
}
