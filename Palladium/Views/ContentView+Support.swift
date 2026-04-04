//
//  ContentView+Support.swift
//  Palladium
//

import SwiftUI
import UIKit

extension ContentView {
    var shouldDisableIdleTimer: Bool {
        isRunning || isPackageRunning
    }

    func syncIdleTimerDisabled() {
        let shouldDisable = shouldDisableIdleTimer
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = shouldDisable
        }
    }

    func clearIdleTimerOverride() {
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func showTemporaryToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeIn(duration: 0.18)) {
            showToastMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.24)) {
                showToastMessage = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                if !showToastMessage {
                    toastMessage = nil
                }
            }
        }
    }

    func appendConsoleText(_ text: String, source: ConsoleLogSource? = nil) {
        consoleLogStore.appendChunk(text, sourceHint: source)
    }

    func installKeyboardDismissTapIfNeeded() {
        guard !keyboardDismissTapInstalled else { return }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }

        let recognizer = UITapGestureRecognizer(
            target: KeyboardDismissTapHandler.shared,
            action: #selector(KeyboardDismissTapHandler.handleTap)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = KeyboardDismissTapHandler.shared
        window.addGestureRecognizer(recognizer)
        keyboardDismissTapInstalled = true
    }

    func fourCC(_ code: FourCharCode) -> String {
        let n = UInt32(code)
        let bytes: [UInt8] = [
            UInt8((n >> 24) & 0xFF),
            UInt8((n >> 16) & 0xFF),
            UInt8((n >> 8) & 0xFF),
            UInt8(n & 0xFF)
        ]
        let chars = bytes.map { b -> Character in
            if b >= 32 && b <= 126 {
                return Character(UnicodeScalar(b))
            }
            return "."
        }
        return String(chars)
    }

    func makeCancelMarkerURL() -> URL? {
        if let downloadsPath = ProcessInfo.processInfo.environment["PALLADIUM_DOWNLOADS"], !downloadsPath.isEmpty {
            return URL(fileURLWithPath: downloadsPath).appendingPathComponent(".palladium-cancel-\(UUID().uuidString)")
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(".palladium-cancel-\(UUID().uuidString)")
    }

    func makeDownloadRunDirectory() throws -> URL {
        let downloadsURL: URL
        if let downloadsPath = ProcessInfo.processInfo.environment["PALLADIUM_DOWNLOADS"], !downloadsPath.isEmpty {
            downloadsURL = URL(fileURLWithPath: downloadsPath, isDirectory: true)
        } else {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            downloadsURL = documents.appendingPathComponent("Temp", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        let runDirectory = downloadsURL.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        return runDirectory
    }

    func requestActiveOperationCancellation() {
        FFmpegBridgeControl.requestCancellation()
        if let markerURL = cancelMarkerURL {
            try? "cancel".write(to: markerURL, atomically: true, encoding: .utf8)
        }
        PythonFlowRunner.interruptActiveFlow()
    }
}

final class StreamingUTF8Decoder {
    private var pendingData = Data()

    func append(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        pendingData.append(data)

        if let decoded = String(data: pendingData, encoding: .utf8) {
            pendingData.removeAll(keepingCapacity: true)
            return decoded
        }

        let maxTrailingBytes = min(3, pendingData.count)
        if maxTrailingBytes > 0 {
            for trailingBytes in 1...maxTrailingBytes {
                let prefixCount = pendingData.count - trailingBytes
                let prefix = pendingData.prefix(prefixCount)
                if let decoded = String(data: prefix, encoding: .utf8) {
                    pendingData = Data(pendingData.suffix(trailingBytes))
                    return decoded
                }
            }
        }

        guard pendingData.count > 3 else { return "" }
        let decoded = String(decoding: pendingData, as: UTF8.self)
        pendingData.removeAll(keepingCapacity: true)
        return decoded
    }

    func finish() -> String {
        guard !pendingData.isEmpty else { return "" }
        let decoded = String(decoding: pendingData, as: UTF8.self)
        pendingData.removeAll(keepingCapacity: true)
        return decoded
    }
}

private final class KeyboardDismissTapHandler: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissTapHandler()

    @objc func handleTap() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }
        return !isTextInputViewHierarchy(touchedView)
    }

    private func isTextInputViewHierarchy(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node is UITextField || node is UITextView || node is UISearchBar {
                return true
            }
            current = node.superview
        }
        return false
    }
}
