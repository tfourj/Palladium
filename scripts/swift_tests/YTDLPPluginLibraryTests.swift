import Compression
import XCTest
@testable import Palladium

final class YTDLPPluginLibraryTests: XCTestCase {
    private var rootURL: URL!
    private var pluginsURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YTDLPPluginLibraryTests-\(UUID().uuidString)", isDirectory: true)
        pluginsURL = rootURL.appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testReadsPluginKindsFromArchiveEntries() throws {
        let archive = makeArchive(names: [
            "yt_dlp_plugins/",
            "yt_dlp_plugins/postprocessor/tagger.py",
            "yt_dlp_plugins/extractor/site.py",
            "README.md",
        ])

        let names = try YTDLPPluginLibrary.archiveEntryNames(in: archive)

        XCTAssertEqual(YTDLPPluginLibrary.kinds(inEntryNames: names), [.extractor, .postprocessor])
    }

    func testPluginFolderMustBeAtArchiveRoot() {
        let kinds = YTDLPPluginLibrary.kinds(inEntryNames: [
            "nested/yt_dlp_plugins/extractor/site.py",
            "yt_dlp_plugins/extractor/notes.txt",
            "yt_dlp_plugins/other/module.py",
        ])

        XCTAssertEqual(kinds, [])
    }

    func testImportsArchiveAndReplacesPluginWithSameName() throws {
        let sourceURL = rootURL.appendingPathComponent("site-plugin.zip")
        try makeArchive(names: ["yt_dlp_plugins/extractor/site.py"]).write(to: sourceURL)
        try YTDLPPluginLibrary.importPlugin(from: sourceURL, into: pluginsURL)

        try makeArchive(names: ["yt_dlp_plugins/postprocessor/tagger.py"]).write(to: sourceURL)
        try YTDLPPluginLibrary.importPlugin(from: sourceURL, into: pluginsURL)

        let plugins = try YTDLPPluginLibrary.plugins(in: pluginsURL)
        XCTAssertEqual(plugins.map(\.fileName), ["site-plugin.zip"])
        XCTAssertEqual(plugins.first?.displayName, "site-plugin")
        XCTAssertEqual(plugins.first?.kinds, [.postprocessor])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pluginsURL.path), ["site-plugin.zip"])
    }

    func testImportsPluginFolder() throws {
        let sourceURL = rootURL.appendingPathComponent("folder-plugin", isDirectory: true)
        let extractorURL = sourceURL.appendingPathComponent("yt_dlp_plugins/extractor", isDirectory: true)
        try FileManager.default.createDirectory(at: extractorURL, withIntermediateDirectories: true)
        try Data("pass\n".utf8).write(to: extractorURL.appendingPathComponent("site.py"))

        try YTDLPPluginLibrary.importPlugin(from: sourceURL, into: pluginsURL)

        let plugin = try XCTUnwrap(YTDLPPluginLibrary.plugins(in: pluginsURL).first)
        XCTAssertTrue(plugin.isFolder)
        XCTAssertEqual(plugin.displayName, "folder-plugin")
        XCTAssertEqual(plugin.kinds, [.extractor])
        XCTAssertEqual(plugin.sizeBytes, 5)
    }

    func testRejectsUnsupportedFilesAndArchivesWithoutPlugins() throws {
        let textURL = rootURL.appendingPathComponent("site.py")
        try Data("pass\n".utf8).write(to: textURL)
        let emptyArchiveURL = rootURL.appendingPathComponent("empty.zip")
        try makeArchive(names: ["README.md"]).write(to: emptyArchiveURL)

        XCTAssertThrowsError(try YTDLPPluginLibrary.importPlugin(from: textURL, into: pluginsURL)) { error in
            XCTAssertEqual(error as? YTDLPPluginLibrary.ImportError, .unsupportedFile)
        }
        XCTAssertThrowsError(try YTDLPPluginLibrary.importPlugin(from: emptyArchiveURL, into: pluginsURL)) { error in
            XCTAssertEqual(error as? YTDLPPluginLibrary.ImportError, .notPlugin)
        }
        XCTAssertEqual(try YTDLPPluginLibrary.plugins(in: pluginsURL), [])
    }

    func testDownloadedFileNamePrefersServerArchiveName() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/download?id=1"))

        XCTAssertEqual(
            YTDLPPluginLibrary.downloadedFileName(suggestedName: "site-plugin.zip", url: url),
            "site-plugin.zip"
        )
        XCTAssertEqual(
            YTDLPPluginLibrary.downloadedFileName(
                suggestedName: "download",
                url: try XCTUnwrap(URL(string: "https://example.com/files/other.whl"))
            ),
            "other.whl"
        )
        XCTAssertEqual(
            YTDLPPluginLibrary.downloadedFileName(suggestedName: "../.hidden.zip", url: url),
            "hidden.zip"
        )
        XCTAssertNil(YTDLPPluginLibrary.downloadedFileName(suggestedName: "page.html", url: url))
    }

    func testLinkImportReportsFailedDownloadsAndRejectedFiles() async throws {
        StubURLProtocol.response = (404, [:], Data())
        await assertLinkImportFails(with: .downloadFailed)

        StubURLProtocol.response = (200, [:], Data("<html></html>".utf8))
        await assertLinkImportFails(with: .unsupportedFile, link: "https://example.com/page.html")

        await assertLinkImportFails(with: .invalidLink, link: "ftp://example.com/plugin.zip")
        XCTAssertEqual(try YTDLPPluginLibrary.plugins(in: pluginsURL), [])
    }

    private func assertLinkImportFails(
        with expected: YTDLPPluginLibrary.ImportError,
        link: String = "https://example.com/plugin.zip",
        line: UInt = #line
    ) async {
        do {
            try await YTDLPPluginLibrary.importPlugin(
                fromLink: link,
                into: pluginsURL,
                session: StubURLProtocol.session
            )
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? YTDLPPluginLibrary.ImportError, expected, line: line)
        }
    }

    func testFindsPluginFolderWrappedInOneTopLevelFolder() {
        XCTAssertEqual(
            YTDLPPluginLibrary.wrappedPluginRoot(inEntryNames: [
                "repo-main/",
                "repo-main/pyproject.toml",
                "repo-main/yt_dlp_plugins/extractor/site.py",
                "__MACOSX/repo-main/._pyproject.toml",
            ]),
            "repo-main"
        )
        XCTAssertNil(YTDLPPluginLibrary.wrappedPluginRoot(inEntryNames: [
            "repo-main/yt_dlp_plugins/extractor/site.py",
            "other/README.md",
        ]))
        XCTAssertNil(YTDLPPluginLibrary.wrappedPluginRoot(inEntryNames: ["repo-main/README.md"]))
    }

    func testImportsSourceArchiveAsFolderPlugin() throws {
        let source = Data("from yt_dlp.extractor.common import InfoExtractor\n".utf8)
        let sourceURL = rootURL.appendingPathComponent("repo-main.zip")
        try makeArchive(
            files: [
                ("repo-main/", Data()),
                ("repo-main/pyproject.toml", Data("[project]\nname = \"repo\"\n".utf8)),
                ("repo-main/yt_dlp_plugins/extractor/site.py", source),
                ("repo-main/yt_dlp_plugins/postprocessor/tagger.py", Data()),
            ],
            deflate: true
        ).write(to: sourceURL)

        try YTDLPPluginLibrary.importPlugin(from: sourceURL, into: pluginsURL)

        let plugin = try XCTUnwrap(YTDLPPluginLibrary.plugins(in: pluginsURL).first)
        XCTAssertEqual(plugin.fileName, "repo-main")
        XCTAssertTrue(plugin.isFolder)
        XCTAssertEqual(plugin.kinds, [.extractor, .postprocessor])
        let pluginURL = pluginsURL.appendingPathComponent("repo-main/yt_dlp_plugins/extractor/site.py")
        XCTAssertEqual(try Data(contentsOf: pluginURL), source)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: pluginsURL.appendingPathComponent("repo-main/pyproject.toml").path
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pluginsURL.path), ["repo-main"])
    }

    func testSourceArchiveWithUnsafePathsIsNotImported() throws {
        let sourceURL = rootURL.appendingPathComponent("repo-main.zip")
        try makeArchive(files: [
            ("repo-main/yt_dlp_plugins/extractor/site.py", Data("pass\n".utf8)),
            ("repo-main/yt_dlp_plugins/../../escape.py", Data("pass\n".utf8)),
        ]).write(to: sourceURL)

        XCTAssertThrowsError(try YTDLPPluginLibrary.importPlugin(from: sourceURL, into: pluginsURL)) { error in
            XCTAssertEqual(error as? YTDLPPluginLibrary.ImportError, .unreadableArchive)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pluginsURL.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("escape.py").path))
    }

    /// Builds a stored ZIP archive with empty entries.
    private func makeArchive(names: [String]) -> Data {
        makeArchive(files: names.map { ($0, Data()) })
    }

    /// Builds a ZIP archive, deflating non-empty file contents when `deflate` is set.
    private func makeArchive(files: [(name: String, contents: Data)], deflate: Bool = false) -> Data {
        var local = Data()
        var central = Data()
        for file in files {
            let nameBytes = Data(file.name.utf8)
            let compresses = deflate && !file.contents.isEmpty
            let stored = compresses ? deflated(file.contents) : file.contents
            let method: UInt16 = compresses ? 8 : 0
            let offset = UInt32(local.count)

            local.append(uint32: 0x0403_4b50)
            local.append(uint16: 20)
            local.append(uint16: 0)
            local.append(uint16: method)
            local.append(Data(count: 8))
            local.append(uint32: UInt32(stored.count))
            local.append(uint32: UInt32(file.contents.count))
            local.append(uint16: UInt16(nameBytes.count))
            local.append(uint16: 0)
            local.append(nameBytes)
            local.append(stored)

            central.append(uint32: 0x0201_4b50)
            central.append(uint16: 20)
            central.append(uint16: 20)
            central.append(uint16: 0)
            central.append(uint16: method)
            central.append(Data(count: 8))
            central.append(uint32: UInt32(stored.count))
            central.append(uint32: UInt32(file.contents.count))
            central.append(uint16: UInt16(nameBytes.count))
            central.append(Data(count: 12))
            central.append(uint32: offset)
            central.append(nameBytes)
        }

        var archive = local
        archive.append(central)
        archive.append(uint32: 0x0605_4b50)
        archive.append(Data(count: 4))
        archive.append(uint16: UInt16(files.count))
        archive.append(uint16: UInt16(files.count))
        archive.append(uint32: UInt32(central.count))
        archive.append(uint32: UInt32(local.count))
        archive.append(uint16: 0)
        return archive
    }

    private func deflated(_ data: Data) -> Data {
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: source.count + 64)
        let size = compression_encode_buffer(
            &destination,
            destination.count,
            source,
            source.count,
            nil,
            COMPRESSION_ZLIB
        )
        return Data(destination.prefix(size))
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xff) })
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (status: Int, headers: [String: String], body: Data) = (200, [:], Data())

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: Self.response.status,
                httpVersion: "HTTP/1.1",
                headerFields: Self.response.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
