import Compression
import XCTest
@testable import Palladium

final class IPABackgroundPatcherTests: XCTestCase {
    private let identifier = "com.tfourj.Palladium.ABCDE12345.download.*"
    private let executable = Data((0..<4096).map { UInt8($0 % 251) })

    func testAddsIdentifierAndKeepsOtherEntries() throws {
        let archive = try makeArchive(plistFormat: .xml)

        let result = try IPABackgroundPatcher.patch(archive, permitting: identifier)

        XCTAssertFalse(result.alreadyPatched)
        XCTAssertEqual(try permittedIdentifiers(in: result.archive), ["com.tfourj.Palladium.download.*", identifier])
        XCTAssertNotNil(result.archive.range(of: localEntry(name: "Payload/Palladium.app/Palladium", data: executable)))
    }

    func testReportsAlreadyPatchedArchive() throws {
        let patched = try IPABackgroundPatcher.patch(try makeArchive(plistFormat: .xml), permitting: identifier)

        let result = try IPABackgroundPatcher.patch(patched.archive, permitting: identifier)

        XCTAssertTrue(result.alreadyPatched)
        XCTAssertEqual(try permittedIdentifiers(in: result.archive), ["com.tfourj.Palladium.download.*", identifier])
    }

    func testPatchesBinaryInfoPlist() throws {
        let result = try IPABackgroundPatcher.patch(try makeArchive(plistFormat: .binary), permitting: identifier)

        XCTAssertEqual(try permittedIdentifiers(in: result.archive), ["com.tfourj.Palladium.download.*", identifier])
    }

    func testRejectsFileThatIsNotAnArchive() {
        XCTAssertThrowsError(try IPABackgroundPatcher.patch(Data("not a zip".utf8), permitting: identifier))
    }

    private func permittedIdentifiers(in archive: Data) throws -> [String] {
        let data = try XCTUnwrap(ZipBuilder.storedEntry(named: "Payload/Palladium.app/Info.plist", in: archive))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return try XCTUnwrap(plist?["BGTaskSchedulerPermittedIdentifiers"] as? [String])
    }

    private func makeArchive(plistFormat: PropertyListSerialization.PropertyListFormat) throws -> Data {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.tfourj.Palladium",
            "BGTaskSchedulerPermittedIdentifiers": ["com.tfourj.Palladium.download.*"],
        ]
        let infoPlist = try PropertyListSerialization.data(fromPropertyList: plist, format: plistFormat, options: 0)
        return try ZipBuilder.archive([
            ("Payload/", Data(), false),
            ("Payload/Palladium.app/Info.plist", infoPlist, true),
            ("Payload/Palladium.app/Palladium", executable, false),
        ])
    }

    private func localEntry(name: String, data: Data) -> Data {
        ZipBuilder.localEntry(name: name, data: data, method: 0, crc: ZipBuilder.crc32(data))
    }
}

/// Writes minimal zip archives with stored or deflated entries, matching what the patcher reads.
private enum ZipBuilder {
    static func archive(_ entries: [(name: String, data: Data, deflate: Bool)]) throws -> Data {
        var body = Data()
        var directory = Data()
        for entry in entries {
            let crc = crc32(entry.data)
            let stored = entry.deflate ? try deflate(entry.data) : entry.data
            let method: UInt16 = entry.deflate ? 8 : 0
            let offset = UInt32(body.count)
            body.append(localEntry(name: entry.name, data: stored, method: method, crc: crc, size: entry.data.count))

            let name = Data(entry.name.utf8)
            directory.append(uint32(0x0201_4b50))
            directory.append(uint16(0x031e))
            directory.append(uint16(20))
            directory.append(uint16(0))
            directory.append(uint16(method))
            directory.append(uint32(0))
            directory.append(uint32(crc))
            directory.append(uint32(UInt32(stored.count)))
            directory.append(uint32(UInt32(entry.data.count)))
            directory.append(uint16(UInt16(name.count)))
            directory.append(uint16(0))
            directory.append(uint16(0))
            directory.append(uint16(0))
            directory.append(uint16(0))
            directory.append(uint32(0o100755 << 16))
            directory.append(uint32(offset))
            directory.append(name)
        }

        var end = Data()
        end.append(uint32(0x0605_4b50))
        end.append(uint16(0))
        end.append(uint16(0))
        end.append(uint16(UInt16(entries.count)))
        end.append(uint16(UInt16(entries.count)))
        end.append(uint32(UInt32(directory.count)))
        end.append(uint32(UInt32(body.count)))
        end.append(uint16(0))
        return body + directory + end
    }

    static func localEntry(name: String, data: Data, method: UInt16, crc: UInt32, size: Int? = nil) -> Data {
        let nameData = Data(name.utf8)
        var entry = Data()
        entry.append(uint32(0x0403_4b50))
        entry.append(uint16(20))
        entry.append(uint16(0))
        entry.append(uint16(method))
        entry.append(uint32(0))
        entry.append(uint32(crc))
        entry.append(uint32(UInt32(data.count)))
        entry.append(uint32(UInt32(size ?? data.count)))
        entry.append(uint16(UInt16(nameData.count)))
        entry.append(uint16(0))
        entry.append(nameData)
        entry.append(data)
        return entry
    }

    /// Reads an uncompressed entry, which is how the patcher stores the patched Info.plist.
    static func storedEntry(named name: String, in archive: Data) -> Data? {
        let bytes = [UInt8](archive)
        guard let end = stride(from: bytes.count - 22, through: 0, by: -1)
            .first(where: { readUInt32(bytes, $0) == 0x0605_4b50 })
        else {
            return nil
        }

        var position = Int(readUInt32(bytes, end + 16))
        for _ in 0..<Int(readUInt16(bytes, end + 10)) {
            let nameLength = Int(readUInt16(bytes, position + 28))
            let headerLength = 46 + nameLength + Int(readUInt16(bytes, position + 30))
                + Int(readUInt16(bytes, position + 32))
            let entryName = String(decoding: bytes[position + 46..<position + 46 + nameLength], as: UTF8.self)
            if entryName == name, readUInt16(bytes, position + 10) == 0 {
                let size = Int(readUInt32(bytes, position + 20))
                let local = Int(readUInt32(bytes, position + 42))
                let start = local + 30 + Int(readUInt16(bytes, local + 26)) + Int(readUInt16(bytes, local + 28))
                return Data(bytes[start..<start + size])
            }
            position += headerLength
        }
        return nil
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? 0xedb8_8320 ^ (crc >> 1) : crc >> 1
            }
        }
        return crc ^ 0xffff_ffff
    }

    private static func deflate(_ data: Data) throws -> Data {
        let source = [UInt8](data)
        var output = [UInt8](repeating: 0, count: source.count + 1024)
        let written = compression_encode_buffer(&output, output.count, source, source.count, nil, COMPRESSION_ZLIB)
        guard written > 0 else { throw CocoaError(.coderInvalidValue) }
        return Data(output.prefix(written))
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(readUInt16(bytes, offset)) | UInt32(readUInt16(bytes, offset + 2)) << 16
    }

    private static func uint16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
