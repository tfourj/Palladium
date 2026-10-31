import BackgroundTasks
import Foundation
import UIKit

/// Keeps a running download alive while Palladium is in the background.
///
/// On iOS 26 and later a download runs as a continued processing task, which shows system progress UI and lets
/// the Python flow keep running after the app leaves the foreground. The silent audio mode plays silence instead,
/// which also works in LiveContainer and on older systems. Older systems, or submissions the scheduler or audio
/// session rejects, fall back to the short UIKit background time window.
final class BackgroundDownloadTask {
    static let shared = BackgroundDownloadTask()

    /// Built from the running bundle identifier, which the scheduler requires as a prefix. Sideloading tools that
    /// append a suffix to it need a matching entry in Info.plist's permitted identifiers.
    private static let identifierPrefix = "\(Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium").download."
    /// Time to wait before ending the task so the next queued download can reuse it.
    private static let queueGracePeriod: Duration = .seconds(10)
    /// yt-dlp reports 100% for each stream and side file, and the system shows a full bar as finished.
    /// The rest of the bar is left for heartbeat steps during post-processing that reports no progress.
    private static let maximumRunningFraction = 0.95
    private static let progressUnitCount: Int64 = 1_000_000
    /// Steps such as embedding a thumbnail report no progress, and the system expires tasks that look stalled.
    private static let heartbeatInterval: Duration = .seconds(3)
    /// Share of the remaining bar each stalled heartbeat adds during post-processing, so long silent steps keep
    /// moving without finishing.
    private static let heartbeatStepFraction = 0.02
    /// Verbose progress lines can arrive many times a second, faster than the system UI needs to redraw.
    private static let subtitleUpdateInterval: Duration = .seconds(1)

    private var continuedTask: BGTask?
    private var submittedIdentifier: String?
    private var legacyTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingEnd: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var lastHeartbeatUnits: Int64 = -1
    private var reportedUnits: Int64 = -1
    private var taskStartedAt: ContinuousClock.Instant?
    private var lastProgressAt: ContinuousClock.Instant?
    private var enteredBackgroundAt: ContinuousClock.Instant?
    private var defaultSubtitle = ""
    private var wantedSubtitle = ""
    private var displayedSubtitle = ""
    private var lastSubtitleUpdate: ContinuousClock.Instant?
    private var currentFraction: Double = 0
    private var log: (String) -> Void = { _ in }
    private var onStop: () -> Void = {}

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enteredBackgroundAt = .now
        }
    }

    /// Whether this system supports continued processing tasks for downloads.
    static var isSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    /// Whether downloads can keep running in the background with `mode` on this system.
    static func isSupported(in mode: BackgroundDownloadMode) -> Bool {
        mode == .silentAudio || isSupported
    }

    /// The bundle identifier this install runs under, which sideloading tools may have changed.
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    /// Whether Info.plist permits the identifiers downloads register under the running bundle identifier.
    ///
    /// Sideloading tools can change the bundle identifier without updating the permitted identifiers, and the
    /// scheduler then rejects every download task.
    static var isPermittedOnThisInstall: Bool {
        permittedIdentifiers.contains(permittedIdentifierPattern)
    }

    /// The Info.plist entry that permits download task identifiers under the running bundle identifier.
    static var permittedIdentifierPattern: String {
        identifierPrefix + "*"
    }

    private static var permittedIdentifiers: [String] {
        Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
    }

    /// Whether the system is showing progress UI, which also tells the user when the download finishes.
    var isShowingSystemProgress: Bool {
        continuedTask != nil
    }

    /// Starts background execution for a download, or reuses the task that is still active from a previous one.
    ///
    /// When `mode` is nil, only the short UIKit background time window is requested.
    ///
    /// `onStop` runs when the system progress UI's stop button ends the task while the app is in the background.
    func begin(
        subtitle: String,
        mode: BackgroundDownloadMode?,
        log: @escaping (String) -> Void,
        onStop: @escaping () -> Void
    ) {
        pendingEnd?.cancel()
        pendingEnd = nil
        self.log = log
        self.onStop = onStop
        defaultSubtitle = subtitle

        if continuedTask != nil || submittedIdentifier != nil || SilentAudioKeepAlive.shared.isActive {
            resetProgress()
            update(fraction: 0, subtitle: nil)
            log("[palladium] reusing background download task\n")
            return
        }

        currentFraction = 0
        wantedSubtitle = subtitle
        if mode == .systemTask, #available(iOS 26.0, *), submitContinuedProcessingTask(subtitle: subtitle) {
            endLegacyTask()
        } else if mode == .silentAudio, SilentAudioKeepAlive.shared.start(log: log) {
            endLegacyTask()
        } else if legacyTaskID == .invalid {
            beginLegacyTask()
        }
    }

    /// Reports download progress to the system UI. A nil subtitle restores the subtitle passed to `begin`.
    func update(fraction: Double?, subtitle: String?) {
        if let fraction {
            currentFraction = min(max(fraction, 0), Self.maximumRunningFraction)
        }
        wantedSubtitle = subtitle ?? defaultSubtitle
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask else { return }

        // Repeated lines report the same fraction, and only a change replaces the heartbeat steps since then.
        // Each ffmpeg step restarts at 0%, but the system bar only moves forward during one download, since a
        // drop can look like a stalled task.
        let units = Int64(currentFraction * Double(task.progress.totalUnitCount))
        if units != reportedUnits {
            reportedUnits = units
            lastProgressAt = .now
            task.progress.completedUnitCount = max(task.progress.completedUnitCount, units)
        }
        showWantedSubtitle(on: task, force: false)
    }

    /// Shows the latest subtitle, at most once per update interval unless `force` is set.
    @available(iOS 26.0, *)
    private func showWantedSubtitle(on task: BGContinuedProcessingTask, force: Bool) {
        guard wantedSubtitle != displayedSubtitle else { return }
        let now = ContinuousClock.now
        if !force, let lastSubtitleUpdate, now - lastSubtitleUpdate < Self.subtitleUpdateInterval {
            return
        }
        lastSubtitleUpdate = now
        displayedSubtitle = wantedSubtitle
        task.updateTitle(Self.title, subtitle: wantedSubtitle)
    }

    /// Whether a download stopped from the system progress UI still keeps its result.
    ///
    /// The stop can arrive after yt-dlp already finished, for example while a thumbnail is embedded, and the
    /// interrupt it sends is then ignored. Files from a finished run are kept instead of being discarded.
    static func keepsResult(afterStopWithResultKind resultKind: String, downloadedPathCount: Int) -> Bool {
        (resultKind == "success" || resultKind == "partial") && downloadedPathCount > 0
    }

    /// Starts the system bar over for the next queued download that reuses the task.
    private func resetProgress() {
        currentFraction = 0
        reportedUnits = -1
        (continuedTask as? ProgressReporting)?.progress.completedUnitCount = 0
    }

    /// Ends background execution. When another queued download follows, the task is kept briefly so it can be reused.
    func end(success: Bool, nextDownloadExpected: Bool) {
        pendingEnd?.cancel()
        pendingEnd = nil
        guard nextDownloadExpected else {
            finish(success: success)
            return
        }
        pendingEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.queueGracePeriod)
            guard !Task.isCancelled else { return }
            self?.finish(success: success)
        }
    }

    private static var title: String {
        String(localized: "download.background.title", bundle: .app)
    }

    @available(iOS 26.0, *)
    private func submitContinuedProcessingTask(subtitle: String) -> Bool {
        // Each identifier can only be registered once, so every task gets a unique suffix.
        let identifier = Self.identifierPrefix + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                self.handleLaunch(of: task)
            }
        }
        guard registered else {
            let bundleID = Self.bundleIdentifier
            log("[palladium] background download task identifier is not permitted: \(identifier) (bundle \(bundleID))\n")
            let permitted = Self.permittedIdentifiers.joined(separator: ", ")
            log("[palladium] permitted background task identifiers: \(permitted)\n")
            return false
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: Self.title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log("[palladium] background download task unavailable: \(error.localizedDescription)\n")
            return false
        }

        submittedIdentifier = identifier
        displayedSubtitle = subtitle
        let bundleID = Self.bundleIdentifier
        log("[palladium] background download task requested: \(identifier) (bundle \(bundleID))\n")
        return true
    }

    @available(iOS 26.0, *)
    private func handleLaunch(of task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask, task.identifier == submittedIdentifier else {
            task.setTaskCompleted(success: false)
            return
        }

        submittedIdentifier = nil
        continuedTask = task
        task.progress.totalUnitCount = Self.progressUnitCount
        reportedUnits = -1
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.handleContinuedTaskExpiration()
            }
        }
        taskStartedAt = .now
        lastProgressAt = .now
        update(fraction: currentFraction, subtitle: wantedSubtitle)
        showWantedSubtitle(on: task, force: true)
        startHeartbeat()
        log("[palladium] background download task started\n")
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        lastHeartbeatUnits = -1
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled else { return }
                self?.advanceStalledProgress()
                self?.showThrottledSubtitle()
            }
        }
    }

    /// Advances progress when nothing changed since the last heartbeat, while staying below complete.
    private func advanceStalledProgress() {
        guard let progress = (continuedTask as? ProgressReporting)?.progress else { return }
        if progress.completedUnitCount == lastHeartbeatUnits {
            progress.completedUnitCount += Self.heartbeatStep(
                completedUnitCount: progress.completedUnitCount,
                totalUnitCount: progress.totalUnitCount
            )
        }
        lastHeartbeatUnits = progress.completedUnitCount
    }

    /// Units a stalled heartbeat adds, never reaching complete.
    ///
    /// Below the running maximum a single unit keeps the bar steady, since real progress replaces it soon. From
    /// the running maximum on, only post-processing remains, and a share of what is left keeps the bar moving.
    static func heartbeatStep(completedUnitCount: Int64, totalUnitCount: Int64) -> Int64 {
        let remaining = totalUnitCount - completedUnitCount
        guard remaining > 1 else { return 0 }
        let runningMaximumUnits = Int64(maximumRunningFraction * Double(totalUnitCount))
        guard completedUnitCount >= runningMaximumUnits else { return 1 }
        let step = Int64(Double(remaining) * heartbeatStepFraction)
        return min(max(step, 1), remaining - 1)
    }

    /// Shows a subtitle that arrived during the throttle window and was not followed by another update.
    private func showThrottledSubtitle() {
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask else { return }
        showWantedSubtitle(on: task, force: false)
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func handleContinuedTaskExpiration() {
        guard let task = continuedTask else { return }
        pendingEnd?.cancel()
        pendingEnd = nil
        stopHeartbeat()
        continuedTask = nil
        log("[palladium] background download task expired: \(expirationDetails(for: task))\n")

        // The stop button and system conditions both expire the task, and iOS does not say which one it was.
        // In the background treat it as the user's stop; otherwise keep going with the short UIKit window.
        if UIApplication.shared.applicationState == .background {
            task.setTaskCompleted(success: false)
            log("[palladium] background download task stopped; cancelling download\n")
            onStop()
            return
        }
        if legacyTaskID == .invalid {
            beginLegacyTask()
        }
        task.setTaskCompleted(success: false)
        log("[palladium] background download task ended by the system; continuing with limited background time\n")
    }

    /// Conditions iOS may weigh when it expires a task, since the expiration itself gives no reason.
    private func expirationDetails(for task: BGTask) -> String {
        var details: [String] = []
        if let taskStartedAt {
            details.append("ran \(Self.secondsText(since: taskStartedAt))")
        }
        if let progress = (task as? ProgressReporting)?.progress {
            details.append("bar \(String(format: "%.2f%%", progress.fractionCompleted * 100))")
        }
        if let enteredBackgroundAt, UIApplication.shared.applicationState == .background {
            details.append("in background \(Self.secondsText(since: enteredBackgroundAt))")
        }
        if let lastProgressAt {
            details.append("last download progress \(Self.secondsText(since: lastProgressAt)) ago")
        }
        details.append("thermal \(Self.thermalStateText(ProcessInfo.processInfo.thermalState))")
        details.append("low power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
        return details.joined(separator: ", ")
    }

    private static func secondsText(since instant: ContinuousClock.Instant) -> String {
        let elapsed = (ContinuousClock.now - instant).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return String(format: "%.1fs", seconds)
    }

    private static func thermalStateText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private func beginLegacyTask() {
        legacyTaskID = UIApplication.shared.beginBackgroundTask(withName: "Palladium download") { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.legacyTaskID != .invalid else { return }
                self.log("[palladium] background time expired; pausing until the app returns\n")
                self.endLegacyTask()
            }
        }
        if legacyTaskID != .invalid {
            log("[palladium] background download time requested\n")
        }
    }

    private func endLegacyTask() {
        guard legacyTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(legacyTaskID)
        legacyTaskID = .invalid
    }

    private func finish(success: Bool) {
        pendingEnd = nil
        stopHeartbeat()
        if let submittedIdentifier {
            self.submittedIdentifier = nil
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: submittedIdentifier)
        }
        if let task = continuedTask {
            continuedTask = nil
            // Post-download actions such as saving to Photos still need a moment after the task ends.
            if UIApplication.shared.applicationState != .active, legacyTaskID == .invalid {
                beginLegacyTask()
            }
            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask, success {
                task.progress.completedUnitCount = task.progress.totalUnitCount
            }
            task.setTaskCompleted(success: success)
        } else if SilentAudioKeepAlive.shared.isActive {
            // Post-download actions need the same moment as above once the audio stops.
            if UIApplication.shared.applicationState != .active, legacyTaskID == .invalid {
                beginLegacyTask()
            }
            SilentAudioKeepAlive.shared.stop()
        } else {
            endLegacyTask()
        }
        displayedSubtitle = ""
        lastSubtitleUpdate = nil
        reportedUnits = -1
        taskStartedAt = nil
        lastProgressAt = nil
        currentFraction = 0
    }
}
