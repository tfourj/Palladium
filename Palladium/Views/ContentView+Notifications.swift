//
//  ContentView+Notifications.swift
//  Palladium
//

import UIKit
import UserNotifications
import OSLog

extension ContentView {
    func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            debugNotification("permission status=\(settings.authorizationStatus.rawValue)")
            guard settings.authorizationStatus == .notDetermined else {
                debugNotification("permission request skipped (already determined)")
                return
            }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    Self.logger.error("notification permission request failed: \(error.localizedDescription, privacy: .public)")
                    debugNotification("permission request failed: \(error.localizedDescription)")
                } else {
                    Self.logger.info("notification permission granted: \(granted, privacy: .public)")
                    debugNotification("permission request result granted=\(granted)")
                }
            }
        }
    }

    func notifyDownloadCompletionIfNeeded(fileURL: URL) {
        guard notificationsEnabled else {
            debugNotification("completion notification skipped (disabled)")
            return
        }
        scheduleCompletionNotificationIfNeeded(fileURL: fileURL, attempt: 1)
    }

    func scheduleCompletionNotificationIfNeeded(fileURL: URL, attempt: Int) {
        let appState = UIApplication.shared.applicationState
        debugNotification("completion check attempt=\(attempt) scenePhase=\(String(describing: scenePhase)) appState=\(appState.rawValue)")
        if appState == .active {
            if attempt == 1 {
                debugNotification("app still active, retrying notification check shortly")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    scheduleCompletionNotificationIfNeeded(fileURL: fileURL, attempt: 2)
                }
            } else {
                debugNotification("completion notification skipped (user in app)")
            }
            return
        }

        debugNotification("scheduling notification file=\(fileURL.lastPathComponent)")

        let content = UNMutableNotificationContent()
        content.title = String(localized: "post_download.title")
        content.body = fileURL.lastPathComponent
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "palladium-download-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("failed to schedule completion notification: \(error.localizedDescription, privacy: .public)")
                debugNotification("schedule failed: \(error.localizedDescription)")
            } else {
                debugNotification("schedule success id=\(request.identifier)")
            }
        }
    }

    func debugNotification(_ message: String) {
        let line = "[notify] \(message)"
        Self.logger.info("\(line, privacy: .public)")
        print(line)
        Task { @MainActor in
            appendConsoleText("\(line)\n", source: .app)
        }
    }
}
