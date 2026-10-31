import Foundation

/// How a download keeps running after Palladium leaves the foreground.
enum BackgroundDownloadMode: String, CaseIterable, Identifiable {
    /// iOS 26 continued processing tasks with system progress UI.
    case systemTask
    /// A silent audio session, which works where background tasks are unavailable, such as in LiveContainer.
    case silentAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemTask:
            return String(localized: "settings.download_behavior.background.mode.system_task", bundle: .app)
        case .silentAudio:
            return String(localized: "settings.download_behavior.background.mode.silent_audio", bundle: .app)
        }
    }

    /// LiveContainer runs guest apps inside its own process, whose Info.plist does not permit Palladium's
    /// background tasks, so silent audio is the only mode that works there.
    static func defaultMode(isRunningInLiveContainer: Bool) -> BackgroundDownloadMode {
        isRunningInLiveContainer ? .silentAudio : .systemTask
    }

    /// LiveContainer sets this variable for every app it launches.
    static var isRunningInLiveContainer: Bool {
        ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil
    }
}
