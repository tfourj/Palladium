import Compression
import Foundation

/// Adds a background task identifier to the Info.plist inside an .ipa.
///
/// Every other archive entry is copied byte for byte, so file permissions and compression stay intact. The patched
/// Info.plist is stored uncompressed, which avoids recompressing the archive.
nonisolated enum IPABackgroundPatcher {
    struct Result {
        let archive: Data
        let alreadyPatched: Bool
    }

    struct PatchError: LocalizedError {
        var errorDescription: String? {
            String(localized: "settings.download_behavior.background.patch.invalid_ipa", bundle: .app)
        }
    }

    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let dataDescriptorFlag: UInt16 = 0x0008
    private static let permittedIdentifiersKey = "BGTaskSchedulerPermittedIdentifiers"

    static func patch(_ archive: Data, permitting identifier: String) throws -> Result {
        let bytes = [UInt8](archive)
        let directory = try CentralDirectory(bytes)
        guard let plistEntry = directory.entries.first(where: { isAppInfoPlist($0.name) }) else {
            throw PatchError()
        }

        let plist = try readEntry(plistEntry, in: bytes)
        let (patchedPlist, alreadyPatched) = try patchInfoPlist(plist, permitting: identifier)
        let output = rebuild(bytes, directory: directory, replacing: plistEntry, with: patchedPlist)
        return Result(archive: output, alreadyPatched: alreadyPatched)
    }

    private static func isAppInfoPlist(_ name: String) -> Bool {
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 3 && components[0] == "Payload" && components[1].hasSuffix(".app")
            && components[2] == "Info.plist"
    }

    private static func readEntry(_ entry: CentralDirectory.Entry, in bytes: [UInt8]) throws -> Data {
        guard bytes.uint32(at: entry.localOffset) == localHeaderSignature else { throw PatchError() }
        let nameLength = Int(bytes.uint16(at: entry.localOffset + 26))
        let extraLength = Int(bytes.uint16(at: entry.localOffset + 28))
        let start = entry.localOffset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw PatchError() }
        let compressed = Array(bytes[start..<start + entry.compressedSize])

        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw PatchError()
        }
    }

    private static func inflate(_ compressed: [UInt8], expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { throw PatchError() }
        var output = [UInt8](repeating: 0, count: expectedSize)
        // COMPRESSION_ZLIB reads raw DEFLATE data, which is what zip entries contain.
        let written = compression_decode_buffer(
            &output, expectedSize, compressed, compressed.count, nil, COMPRESSION_ZLIB
        )
        guard written == expectedSize else { throw PatchError() }
        return Data(output)
    }

    private static func patchInfoPlist(_ data: Data, permitting identifier: String) throws -> (Data, Bool) {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard var plist = object as? [String: Any] else { throw PatchError() }

        var identifiers = plist[permittedIdentifiersKey] as? [String] ?? []
        if identifiers.contains(identifier) {
            return (data, true)
        }
        identifiers.append(identifier)
        plist[permittedIdentifiersKey] = identifiers

        let patched = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        return (patched, false)
    }

    private static func rebuild(
        _ bytes: [UInt8],
        directory: CentralDirectory,
        replacing plistEntry: CentralDirectory.Entry,
        with plist: Data
    ) -> Data {
        let plistBytes = [UInt8](plist)
        let plistCRC = CRC32.checksum(plistBytes)
        let ordered = directory.entries.sorted { $0.localOffset < $1.localOffset }
        var newOffsets: [Int: Int] = [:]
        var output = Data()
        output.reserveCapacity(bytes.count + plistBytes.count)

        for (index, entry) in ordered.enumerated() {
            newOffsets[entry.localOffset] = output.count
            if entry.localOffset == plistEntry.localOffset {
                output.append(contentsOf: storedLocalEntry(bytes, entry: entry, data: plistBytes, crc: plistCRC))
            } else {
                let end = index + 1 < ordered.count ? ordered[index + 1].localOffset : directory.offset
                output.append(contentsOf: bytes[entry.localOffset..<end])
            }
        }

        let directoryOffset = output.count
        for entry in directory.entries {
            var header = Array(bytes[entry.headerOffset..<entry.headerOffset + entry.headerLength])
            header.setUInt32(UInt32(newOffsets[entry.localOffset] ?? 0), at: 42)
            if entry.localOffset == plistEntry.localOffset {
                header.setUInt16(entry.flags & ~dataDescriptorFlag, at: 8)
                header.setUInt16(0, at: 10)
                header.setUInt32(plistCRC, at: 16)
                header.setUInt32(UInt32(plistBytes.count), at: 20)
                header.setUInt32(UInt32(plistBytes.count), at: 24)
            }
            output.append(contentsOf: header)
        }

        var end = Array(bytes[directory.endOffset...])
        end.setUInt32(UInt32(output.count - directoryOffset), at: 12)
        end.setUInt32(UInt32(directoryOffset), at: 16)
        output.append(contentsOf: end)
        return output
    }

    /// Builds a local header that stores the data uncompressed, keeping the original name and timestamps.
    private static func storedLocalEntry(
        _ bytes: [UInt8],
        entry: CentralDirectory.Entry,
        data: [UInt8],
        crc: UInt32
    ) -> [UInt8] {
        let offset = entry.localOffset
        let nameLength = Int(bytes.uint16(at: offset + 26))
        var header = Array(bytes[offset..<offset + 30])
        header.setUInt16(bytes.uint16(at: offset + 6) & ~dataDescriptorFlag, at: 6)
        header.setUInt16(0, at: 8)
        header.setUInt32(crc, at: 14)
        header.setUInt32(UInt32(data.count), at: 18)
        header.setUInt32(UInt32(data.count), at: 22)
        header.setUInt16(0, at: 28)
        return header + bytes[offset + 30..<offset + 30 + nameLength] + data
    }

    private struct CentralDirectory {
        struct Entry {
            let headerOffset: Int
            let headerLength: Int
            let flags: UInt16
            let method: UInt16
            let compressedSize: Int
            let uncompressedSize: Int
            let localOffset: Int
            let name: String
        }

        let entries: [Entry]
        let offset: Int
        let endOffset: Int

        init(_ bytes: [UInt8]) throws {
            guard bytes.count >= 22 else { throw PatchError() }
            let lowestOffset = max(0, bytes.count - 22 - 0xffff)
            guard let endOffset = stride(from: bytes.count - 22, through: lowestOffset, by: -1)
                .first(where: { bytes.uint32(at: $0) == IPABackgroundPatcher.endOfCentralDirectorySignature })
            else {
                throw PatchError()
            }

            let count = Int(bytes.uint16(at: endOffset + 10))
            let offset = Int(bytes.uint32(at: endOffset + 16))
            // ZIP64 archives mark these fields with all bits set, which this patcher doesn't handle.
            guard count != 0xffff, offset != 0xffff_ffff, offset < endOffset else { throw PatchError() }

            var entries: [Entry] = []
            var position = offset
            for _ in 0..<count {
                guard position + 46 <= endOffset,
                      bytes.uint32(at: position) == IPABackgroundPatcher.centralHeaderSignature
                else {
                    throw PatchError()
                }
                let nameLength = Int(bytes.uint16(at: position + 28))
                let extraLength = Int(bytes.uint16(at: position + 30))
                let commentLength = Int(bytes.uint16(at: position + 32))
                let length = 46 + nameLength + extraLength + commentLength
                let nameBytes = bytes[position + 46..<position + 46 + nameLength]
                entries.append(
                    Entry(
                        headerOffset: position,
                        headerLength: length,
                        flags: bytes.uint16(at: position + 8),
                        method: bytes.uint16(at: position + 10),
                        compressedSize: Int(bytes.uint32(at: position + 20)),
                        uncompressedSize: Int(bytes.uint32(at: position + 24)),
                        localOffset: Int(bytes.uint32(at: position + 42)),
                        name: String(decoding: nameBytes, as: UTF8.self)
                    )
                )
                position += length
            }

            self.entries = entries
            self.offset = offset
            self.endOffset = endOffset
        }
    }

    private enum CRC32 {
        private static let table: [UInt32] = (0..<256).map { value in
            var crc = UInt32(value)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? 0xedb8_8320 ^ (crc >> 1) : crc >> 1
            }
            return crc
        }

        static func checksum(_ bytes: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xffff_ffff
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
            }
            return crc ^ 0xffff_ffff
        }
    }
}

nonisolated private extension Array where Element == UInt8 {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    mutating func setUInt16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8(value >> 8)
    }

    mutating func setUInt32(_ value: UInt32, at offset: Int) {
        for index in 0..<4 {
            self[offset + index] = UInt8((value >> (8 * UInt32(index))) & 0xff)
        }
    }
}
