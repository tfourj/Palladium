import Compression
import XCTest
@testable import Palladium

final class InstalledAppExporterTests: XCTestCase {
    private let identifier = "com.tfourj.Palladium.ABCDE12345.download.*"
    private var workURL: URL!

    override func setUpWithError() throws {
        workURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledAppExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workURL)
    }

    func testExportsPayloadWithPatchedPlistAndOriginalIdentifiers() throws {
        let appURL = try makeApp()
        let outputURL = workURL.appendingPathComponent("Patched.ipa")

        try InstalledAppExporter.exportPatchedIPA(from: appURL, permitting: identifier, to: outputURL)

        let archive = try ZipReader(Data(contentsOf: outputURL))
        XCTAssertFalse(archive.names.contains { $0.hasPrefix("__MACOSX") })
        XCTAssertTrue(archive.names.allSatisfy { $0.hasPrefix("Payload/") })

        let appPlist = try archive.plist(named: "Payload/Fake.app/Info.plist")
        XCTAssertEqual(appPlist["CFBundleIdentifier"] as? String, "com.tfourj.Palladium")
        XCTAssertEqual(
            appPlist["BGTaskSchedulerPermittedIdentifiers"] as? [String],
            ["com.tfourj.Palladium.download.*", identifier]
        )

        let pluginPlist = try archive.plist(named: "Payload/Fake.app/PlugIns/Share.appex/Info.plist")
        XCTAssertEqual(pluginPlist["CFBundleIdentifier"] as? String, "com.tfourj.Palladium.ShareExtension")

        XCTAssertEqual(try archive.data(named: "Payload/Fake.app/Fake"), Data("binary".utf8))
        XCTAssertEqual(archive.permissions(named: "Payload/Fake.app/Fake"), 0o755)
    }

    func testKeepsPluginIdentifierOutsideAppIdentifier() throws {
        let appURL = try makeApp(pluginIdentifier: "com.example.Share")
        let outputURL = workURL.appendingPathComponent("Patched.ipa")

        try InstalledAppExporter.exportPatchedIPA(from: appURL, permitting: identifier, to: outputURL)

        let archive = try ZipReader(Data(contentsOf: outputURL))
        let pluginPlist = try archive.plist(named: "Payload/Fake.app/PlugIns/Share.appex/Info.plist")
        XCTAssertEqual(pluginPlist["CFBundleIdentifier"] as? String, "com.example.Share")
    }

    private func makeApp(pluginIdentifier: String = "com.tfourj.Palladium.ABCDE12345.ShareExtension") throws -> URL {
        let appURL = workURL.appendingPathComponent("Source/Fake.app", isDirectory: true)
        let pluginURL = appURL.appendingPathComponent("PlugIns/Share.appex", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginURL, withIntermediateDirectories: true)

        let appPlist: [String: Any] = [
            "CFBundleIdentifier": "com.tfourj.Palladium.ABCDE12345",
            "BGTaskSchedulerPermittedIdentifiers": ["com.tfourj.Palladium.download.*"],
        ]
        let pluginPlist: [String: Any] = ["CFBundleIdentifier": pluginIdentifier]
        try writePlist(appPlist, to: appURL.appendingPathComponent("Info.plist"))
        try writePlist(pluginPlist, to: pluginURL.appendingPathComponent("Info.plist"))

        let executableURL = appURL.appendingPathComponent("Fake")
        try Data("binary".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return appURL
    }

    private func writePlist(_ plist: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    }
}

/// Reads entry names, contents, and Unix permissions from a zip archive.
private struct ZipReader {
    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
        let externalAttributes: UInt32
    }

    private let bytes: [UInt8]
    private let entries: [String: Entry]

    var names: [String] { Array(entries.keys) }

    init(_ archive: Data) throws {
        bytes = [UInt8](archive)
        let byteArray = bytes
        let end = try XCTUnwrap(
            stride(from: byteArray.count - 22, through: 0, by: -1)
                .first(where: { Self.uint32(byteArray, $0) == 0x0605_4b50 })
        )

        var entries: [String: Entry] = [:]
        var position = Int(Self.uint32(bytes, end + 16))
        for _ in 0..<Int(Self.uint16(bytes, end + 10)) {
            let nameLength = Int(Self.uint16(bytes, position + 28))
            let name = String(decoding: bytes[position + 46..<position + 46 + nameLength], as: UTF8.self)
            entries[name] = Entry(
                method: Self.uint16(bytes, position + 10),
                compressedSize: Int(Self.uint32(bytes, position + 20)),
                uncompressedSize: Int(Self.uint32(bytes, position + 24)),
                localOffset: Int(Self.uint32(bytes, position + 42)),
                externalAttributes: Self.uint32(bytes, position + 38)
            )
            position += 46 + nameLength + Int(Self.uint16(bytes, position + 30))
                + Int(Self.uint16(bytes, position + 32))
        }
        self.entries = entries
    }

    func permissions(named name: String) -> UInt32? {
        entries[name].map { ($0.externalAttributes >> 16) & 0o777 }
    }

    func plist(named name: String) throws -> [String: Any] {
        let plist = try PropertyListSerialization.propertyList(from: data(named: name), format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func data(named name: String) throws -> Data {
        let entry = try XCTUnwrap(entries[name], "Missing \(name)")
        let local = entry.localOffset
        let start = local + 30 + Int(Self.uint16(bytes, local + 26)) + Int(Self.uint16(bytes, local + 28))
        let compressed = Array(bytes[start..<start + entry.compressedSize])
        guard entry.method == 8 else { return Data(compressed) }

        var output = [UInt8](repeating: 0, count: max(entry.uncompressedSize, 1))
        let written = compression_decode_buffer(
            &output, output.count, compressed, compressed.count, nil, COMPRESSION_ZLIB
        )
        return Data(output.prefix(written))
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(uint16(bytes, offset)) | UInt32(uint16(bytes, offset + 2)) << 16
    }
}
