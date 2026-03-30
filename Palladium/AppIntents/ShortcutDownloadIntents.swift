import AppIntents
import Foundation

enum ShortcutDownloadPreset: String, Codable, CaseIterable, AppEnum {
    case video
    case audio
    case mute
    case custom

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("shortcuts.download_type.title"))
    }

    static var caseDisplayRepresentations: [ShortcutDownloadPreset: DisplayRepresentation] {
        [
            .video: DisplayRepresentation(title: LocalizedStringResource("download.preset.video")),
            .audio: DisplayRepresentation(title: LocalizedStringResource("download.preset.audio")),
            .mute: DisplayRepresentation(title: LocalizedStringResource("download.preset.mute")),
            .custom: DisplayRepresentation(title: LocalizedStringResource("common.custom"))
        ]
    }

    var downloadPreset: DownloadPreset {
        switch self {
        case .video:
            return .autoVideo
        case .audio:
            return .audio
        case .mute:
            return .mute
        case .custom:
            return .custom
        }
    }
}

enum ShortcutSaveDestination: String, Codable, CaseIterable, AppEnum {
    case appFolder
    case photos

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("shortcuts.save_destination.title"))
    }

    static var caseDisplayRepresentations: [ShortcutSaveDestination: DisplayRepresentation] {
        [
            .appFolder: DisplayRepresentation(title: LocalizedStringResource("post_download.action.save_folder.title")),
            .photos: DisplayRepresentation(title: LocalizedStringResource("photos.action.save"))
        ]
    }
}

struct StartDownloadIntent: AppIntent {
    static var title: LocalizedStringResource = "shortcuts.start_download.title"
    static var description = IntentDescription("shortcuts.start_download.description")
    static var openAppWhenRun = true

    @Parameter(title: "shortcuts.parameter.url")
    var url: String

    @Parameter(title: "shortcuts.parameter.download_type")
    var downloadType: ShortcutDownloadPreset

    @Parameter(title: "shortcuts.parameter.save_destination")
    var saveDestination: ShortcutSaveDestination

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = PendingShortcutDownloadRequest(
            url: trimmedURL,
            preset: downloadType,
            destination: saveDestination
        )
        ShortcutDownloadRequestStore.savePendingRequest(request)
        return .result(dialog: IntentDialog("shortcuts.start_download.dialog"))
    }
}

struct PalladiumShortcutsProvider: AppShortcutsProvider {
    static let appShortcuts: [AppShortcut] = [
        AppShortcut(
            intent: StartDownloadIntent(),
            phrases: [
                "Start download in \(.applicationName)",
                "Download media with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("shortcuts.start_download.title"),
            systemImageName: "arrow.down.circle"
        )
    ]
}
