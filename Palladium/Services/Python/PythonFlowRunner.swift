import Foundation
import PythonKit

enum PythonFlowRunner {
    static func executeDownloadFlow(url: String, preset: String, customArgs: String, extraArgs: String) async -> PythonFlowOutcome {
        await runOnPythonThread {
            let builtins = Python.import("builtins")
            let main = Python.import("__main__")
            _ = builtins.exec(PythonScripts.ytDlpScript, main.__dict__)
            let payload = String(main.run_yt_dlp_flow(url, preset, customArgs, extraArgs)) ?? ""
            return decodeDownloadPayload(payload)
        }
    }

    static func executePackageFlow(action: String) async -> PythonFlowOutcome {
        await runOnPythonThread {
            let builtins = Python.import("builtins")
            let main = Python.import("__main__")
            _ = builtins.exec(PythonScripts.ytDlpScript, main.__dict__)
            let payload = String(main.run_package_maintenance(action)) ?? ""
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
                downloadedPath: nil
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
            downloadedPath: downloadedPath
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
                downloadedPath: nil
            )
        }

        let pipAttempted = result["pip_attempted"] as? Bool ?? false
        let pipExitCode = result["pip_exit_code"] as? Int
        let success = result["success"] as? Bool ?? false
        let output = result["output"] as? String ?? ""
        let versions = result["versions"] as? [String: String] ?? [:]

        let summary = """
        pip attempted: \(pipAttempted)
        pip exit code: \(pipExitCode.map(String.init) ?? "none")
        success: \(success)
        """

        let versionsText = """
        yt-dlp: \(versions["yt-dlp"] ?? "unknown")
        yt-dlp-apple-webkit-jsi: \(versions["yt-dlp-apple-webkit-jsi"] ?? "unknown")
        """

        return PythonFlowOutcome(
            statusText: success ? "success" : "error",
            summaryText: summary,
            outputText: output,
            versionsText: versionsText,
            downloadedPath: nil
        )
    }

    private static func runOnPythonThread(
        _ work: @escaping @Sendable () -> PythonFlowOutcome
    ) async -> PythonFlowOutcome {
        await PythonExecutor.shared.run(work)
    }
}

struct PythonFlowOutcome: Sendable {
    let statusText: String
    let summaryText: String
    let outputText: String
    let versionsText: String?
    let downloadedPath: String?
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
