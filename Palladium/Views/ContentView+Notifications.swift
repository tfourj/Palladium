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

        scheduleAuthorizedCompletionNotification(fileURL: fileURL)
    }

    func scheduleAuthorizedCompletionNotification(fileURL: URL) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            debugNotification("delivery permission status=\(settings.authorizationStatus.rawValue)")
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                addCompletionNotification(fileURL: fileURL)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        Self.logger.error("notification permission request failed: \(error.localizedDescription, privacy: .public)")
                        debugNotification("delivery permission request failed: \(error.localizedDescription)")
                    } else if granted {
                        debugNotification("delivery permission granted")
                        addCompletionNotification(fileURL: fileURL)
                    } else {
                        debugNotification("delivery permission denied by prompt")
                    }
                }
            case .denied:
                debugNotification("completion notification skipped (permission denied)")
            @unknown default:
                debugNotification("completion notification skipped (unknown permission)")
            }
        }
    }

    func addCompletionNotification(fileURL: URL) {
        debugNotification("scheduling notification file=\(fileURL.lastPathComponent)")

        let content = UNMutableNotificationContent()
        content.title = String(localized: "post_download.title")
        content.body = fileURL.lastPathComponent
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "palladium-download-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
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
