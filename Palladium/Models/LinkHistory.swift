import Foundation

struct LinkHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let url: String
    let presetRawValue: String
    let title: String?
    let timestamp: Date

    var preset: DownloadPreset {
        DownloadPreset(rawValue: presetRawValue) ?? .autoVideo
    }
}
