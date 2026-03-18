import Foundation
import PythonKit

enum PythonFlowRunner {
    static func executeDownloadFlow(url: String, preset: String, presetArgsJSON: String, extraArgs: String) async -> PythonFlowOutcome {
        await runOnPythonThread {
            let builtins = Python.import("builtins")
            let main = Python.import("__main__")
            _ = builtins.exec(PythonScripts.ytDlpScript, main.__dict__)
            let payload = String(main.run_yt_dlp_flow(url, preset, presetArgsJSON, extraArgs)) ?? ""
            return decodeDownloadPayload(payload)
        }
    }

    static func executePackageFlow(action: String, customVersions: [String: String]? = nil) async -> PythonFlowOutcome {
        await runOnPythonThread {
            let builtins = Python.import("builtins")
            let main = Python.import("__main__")
            _ = builtins.exec(PythonScripts.ytDlpScript, main.__dict__)
            let customVersionsJSON: String
            if let customVersions,
               let data = try? JSONSerialization.data(withJSONObject: customVersions),
               let text = String(data: data, encoding: .utf8) {
                customVersionsJSON = text
            } else {
                customVersionsJSON = ""
            }
            let payload = String(main.run_package_maintenance(action, customVersionsJSON)) ?? ""
            return decodePackagePayload(payload)
        }
    }

    private static func decodeDownloadPayload(_ payload: String) -> PythonFlowOutcome {
        guard let data = payload.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return PythonFlowOutcome(
                statusText: "error",
                summaryText: "success: false",
                outputText: """
                Failed to decode Python result.

                Raw payload:
                \(payload)
                """,
                versionsText: nil,
                downloadedPath: nil,
                pipExitCode: nil,
                ytDlpExitCode: nil,
                updatesAvailable: nil,
                updatesSummary: nil,
                availableVersions: nil
            )
        }

        let pipAttempted = result["pip_attempted"] as? Bool ?? false
        let pipExitCode = result["pip_exit_code"] as? Int
        let ytExitCode = result["yt_exit_code"] as? Int
        let success = result["success"] as? Bool ?? false
        let cancelled = result["cancelled"] as? Bool ?? false
        let output = result["output"] as? String ?? ""
        let downloadedPath = result["downloaded_path"] as? String

        let summary = """
        pip attempted: \(pipAttempted)
        pip exit code: \(pipExitCode.map(String.init) ?? "none")
        yt-dlp exit code: \(ytExitCode.map(String.init) ?? "none")
        cancelled: \(cancelled)
        success: \(success)
        """

        return PythonFlowOutcome(
            statusText: cancelled ? "cancelled" : (success ? "success" : "error"),
            summaryText: summary,
            outputText: output,
            versionsText: nil,
            downloadedPath: downloadedPath,
            pipExitCode: pipExitCode,
            ytDlpExitCode: ytExitCode,
            updatesAvailable: nil,
            updatesSummary: nil,
            availableVersions: nil
        )
    }

    private static func decodePackagePayload(_ payload: String) -> PythonFlowOutcome {
        guard let data = payload.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return PythonFlowOutcome(
                statusText: "error",
                summaryText: "success: false",
                outputText: """
                Failed to decode Python result.

                Raw payload:
                \(payload)
                """,
                versionsText: nil,
                downloadedPath: nil,
                pipExitCode: nil,
                ytDlpExitCode: nil,
                updatesAvailable: nil,
                updatesSummary: nil,
                availableVersions: nil
            )
        }

        let pipAttempted = result["pip_attempted"] as? Bool ?? false
        let pipExitCode = result["pip_exit_code"] as? Int
        let success = result["success"] as? Bool ?? false
        let updatesAvailable = result["updates_available"] as? Bool ?? false
        let updatesSummary = result["updates_summary"] as? String ?? "Not checked yet."
        let output = result["output"] as? String ?? ""
        let versions = normalizedVersions(from: result["versions"])
        let availableVersions = normalizedAvailableVersions(from: result["available_versions"])

        let summary = """
        pip attempted: \(pipAttempted)
        pip exit code: \(pipExitCode.map(String.init) ?? "none")
        updates available: \(updatesAvailable)
        updates summary: \(updatesSummary)
        success: \(success)
        """

        var versionLines = [
            "yt-dlp: \(versions["yt-dlp"] ?? "not installed")",
            "yt-dlp-apple-webkit-jsi: \(versions["yt-dlp-apple-webkit-jsi"] ?? "not installed")"
        ]
        if let pipVersion = versions["pip"],
           !pipVersion.isEmpty,
           pipVersion.lowercased() != "not installed" {
            versionLines.append("pip: \(pipVersion)")
        }
        let versionsText = versionLines.joined(separator: "\n")

        return PythonFlowOutcome(
            statusText: success ? "success" : "error",
            summaryText: summary,
            outputText: output,
            versionsText: versionsText,
            downloadedPath: nil,
            pipExitCode: pipExitCode,
            ytDlpExitCode: nil,
            updatesAvailable: updatesAvailable,
            updatesSummary: updatesSummary,
            availableVersions: availableVersions
        )
    }

    private static func runOnPythonThread(
        _ work: @escaping @Sendable () -> PythonFlowOutcome
    ) async -> PythonFlowOutcome {
        await PythonExecutor.shared.run(work)
    }

    private static func normalizedVersions(from value: Any?) -> [String: String] {
        guard let raw = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for key in ["yt-dlp", "yt-dlp-apple-webkit-jsi", "pip"] {
            guard let item = raw[key] else { continue }
            let versionText = String(describing: item).trimmingCharacters(in: .whitespacesAndNewlines)
            if !versionText.isEmpty {
                result[key] = versionText
            }
        }
        return result
    }

    private static func normalizedAvailableVersions(from value: Any?) -> [String: [String]] {
        guard let raw = value as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for key in ["yt-dlp", "yt-dlp-apple-webkit-jsi", "pip"] {
            guard let list = raw[key] as? [Any] else { continue }
            let values = list.map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !values.isEmpty {
                result[key] = values
            }
        }
        return result
    }
}

struct PythonFlowOutcome: Sendable {
    let statusText: String
    let summaryText: String
    let outputText: String
    let versionsText: String?
    let downloadedPath: String?
    let pipExitCode: Int?
    let ytDlpExitCode: Int?
    let updatesAvailable: Bool?
    let updatesSummary: String?
    let availableVersions: [String: [String]]?
}

private final class PythonExecutor: NSObject {
    static let shared = PythonExecutor()

    private let threadReady = DispatchSemaphore(value: 0)
    private var pythonThread: Thread!

    private override init() {
        super.init()
        pythonThread = Thread(target: self, selector: #selector(threadMain), object: nil)
        pythonThread.name = "com.tfourj.Palladium.python-thread"
        pythonThread.qualityOfService = .userInitiated
        pythonThread.stackSize = 8 * 1024 * 1024
        pythonThread.start()
        threadReady.wait()
    }

    @objc private func threadMain() {
        autoreleasepool {
            let runLoop = RunLoop.current
            runLoop.add(Port(), forMode: .default)
            threadReady.signal()
            while !Thread.current.isCancelled {
                runLoop.run(mode: .default, before: .distantFuture)
            }
        }
    }

    @objc private func executeWorkItem(_ item: PythonWorkItem) {
        item.execute()
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let task = PythonWorkItem {
                continuation.resume(returning: work())
            }
            perform(#selector(executeWorkItem(_:)), on: pythonThread, with: task, waitUntilDone: false)
        }
    }
}

private final class PythonWorkItem: NSObject {
    private let block: () -> Void

    init(block: @escaping () -> Void) {
        self.block = block
    }

    @objc func execute() {
        block()
    }
}
