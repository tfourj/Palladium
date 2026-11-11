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

    /// Builds a stored ZIP archive with empty entries.
    private func makeArchive(names: [String]) -> Data {
        var local = Data()
        var central = Data()
        for name in names {
            let nameBytes = Data(name.utf8)
            let offset = UInt32(local.count)
            local.append(uint32: 0x0403_4b50)
            local.append(uint16: 20)
            local.append(Data(count: 20))
            local.append(uint16: UInt16(nameBytes.count))
            local.append(uint16: 0)
            local.append(nameBytes)

            central.append(uint32: 0x0201_4b50)
            central.append(uint16: 20)
            central.append(uint16: 20)
            central.append(Data(count: 20))
            central.append(uint16: UInt16(nameBytes.count))
            central.append(Data(count: 12))
            central.append(uint32: offset)
            central.append(nameBytes)
        }

        var archive = local
        archive.append(central)
        archive.append(uint32: 0x0605_4b50)
        archive.append(Data(count: 4))
        archive.append(uint16: UInt16(names.count))
        archive.append(uint16: UInt16(names.count))
        archive.append(uint32: UInt32(central.count))
        archive.append(uint32: UInt32(local.count))
        archive.append(uint16: 0)
        return archive
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
