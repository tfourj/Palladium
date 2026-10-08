import BackgroundTasks
import Foundation
import UIKit

/// Keeps a running download alive while Palladium is in the background.
///
/// On iOS 26 and later a download runs as a continued processing task, which shows system progress UI and lets
/// the Python flow keep running after the app leaves the foreground. Older systems, or submissions the scheduler
/// rejects, fall back to the short UIKit background time window.
final class BackgroundDownloadTask {
    static let shared = BackgroundDownloadTask()

    private static let identifierPrefix = "\(Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium").download."
    /// Time to wait before ending the task so a queued download or post-download action can reuse it.
    private static let endGracePeriod: Duration = .seconds(10)

    private var continuedTask: BGTask?
    private var submittedIdentifier: String?
    private var legacyTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingEnd: Task<Void, Never>?
    private var defaultSubtitle = ""
    private var wantedSubtitle = ""
    private var displayedSubtitle = ""
    private var currentFraction: Double = 0
    private var log: (String) -> Void = { _ in }
    private var onExpiration: () -> Void = {}

    private init() {}

    /// Starts background execution for a download, or reuses the task that is still active from a previous one.
    func begin(subtitle: String, log: @escaping (String) -> Void, onExpiration: @escaping () -> Void) {
        pendingEnd?.cancel()
        pendingEnd = nil
        self.log = log
        self.onExpiration = onExpiration
        defaultSubtitle = subtitle

        if continuedTask != nil || submittedIdentifier != nil {
            update(fraction: 0, subtitle: nil)
            log("[palladium] reusing background download task\n")
            return
        }

        currentFraction = 0
        wantedSubtitle = subtitle
        if #available(iOS 26.0, *), submitContinuedProcessingTask(subtitle: subtitle) {
            endLegacyTask()
        } else if legacyTaskID == .invalid {
            beginLegacyTask()
        }
    }

    /// Reports download progress to the system UI. A nil subtitle restores the subtitle passed to `begin`.
    func update(fraction: Double?, subtitle: String?) {
        if let fraction {
            currentFraction = min(max(fraction, 0), 1)
        }
        wantedSubtitle = subtitle ?? defaultSubtitle
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask else { return }

        task.progress.completedUnitCount = Int64(currentFraction * Double(task.progress.totalUnitCount))
        if wantedSubtitle != displayedSubtitle {
            displayedSubtitle = wantedSubtitle
            task.updateTitle(Self.title, subtitle: wantedSubtitle)
        }
    }

    /// Ends background execution after a short grace period unless another download begins first.
    func end(success: Bool) {
        pendingEnd?.cancel()
        pendingEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.endGracePeriod)
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
            log("[palladium] background download task identifier is not permitted\n")
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
        log("[palladium] background download task requested\n")
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
        task.progress.totalUnitCount = 1000
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.handleContinuedTaskExpiration()
            }
        }
        update(fraction: currentFraction, subtitle: wantedSubtitle)
        log("[palladium] background download task started\n")
    }

    private func handleContinuedTaskExpiration() {
        guard let task = continuedTask else { return }
        pendingEnd?.cancel()
        pendingEnd = nil
        continuedTask = nil
        task.setTaskCompleted(success: false)

        // The system UI's stop button also expires the task. Keep going when the user is in the app.
        if UIApplication.shared.applicationState == .active {
            log("[palladium] background download task ended by the system\n")
        } else {
            log("[palladium] background download task stopped; cancelling download\n")
            onExpiration()
        }
    }

    private func beginLegacyTask() {
        legacyTaskID = UIApplication.shared.beginBackgroundTask(withName: "Palladium download") { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.legacyTaskID != .invalid else { return }
                self.log("[palladium] background time expired; pausing download until the app returns\n")
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
        if let task = continuedTask {
            continuedTask = nil
            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask, success {
                task.progress.completedUnitCount = task.progress.totalUnitCount
            }
            task.setTaskCompleted(success: success)
        }
        if let submittedIdentifier {
            self.submittedIdentifier = nil
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: submittedIdentifier)
        }
        endLegacyTask()
        displayedSubtitle = ""
        currentFraction = 0
    }
}
