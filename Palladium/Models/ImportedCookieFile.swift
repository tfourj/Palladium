import Foundation

struct ImportedCookieFile: Identifiable, Equatable, Hashable {
    let fileName: String
    let fileURL: URL
    let modifiedAt: Date
    let sizeBytes: Int64

    var id: String { fileName }

    var displayName: String {
        fileName
    }

    var formattedSize: String {
        StorageLocationSummary.byteFormatter.string(fromByteCount: sizeBytes)
    }
}
