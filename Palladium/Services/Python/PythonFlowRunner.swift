import Foundation
import PythonKit
import Darwin

enum PythonFlowRunner {
    private static var insertedScriptDirectories = Set<String>()

    static func executeDownloadFlow(url: String, preset: String, presetArgsJSON: String, extraArgs: String) async -> PythonFlowOutcome {
        await runOnPythonThread {
            let payload: String
            do {
                let module = try loadYtDlpModule()
                let function = try pythonMember(module, named: "run_yt_dlp_flow")
                payload = callPythonFunction(
                    function,
                    arguments: [url, preset, presetArgsJSON, extraArgs]
                )
            } catch {
                payload = fallbackPythonErrorPayload(error)
            }
            return decodeDownloadPayload(payload)
        }
    }

    static func executePackageFlow(action: String, customVersions: [String: String]? = nil) async -> PythonFlowOutcome {
        await runOnPythonThread {
            let customVersionsJSON: String
            if let customVersions,
               let data = try? JSONSerialization.data(withJSONObject: customVersions),
               let text = String(data: data, encoding: .utf8) {
                customVersionsJSON = text
            } else {
                customVersionsJSON = ""
            }

            let payload: String
            do {
                let module = try loadYtDlpModule()
                let function = try pythonMember(module, named: "run_package_maintenance")
                payload = callPythonFunction(
                    function,
                    arguments: [action, customVersionsJSON]
                )
            } catch {
                payload = fallbackPythonErrorPayload(error)
            }
            return decodePackagePayload(payload)
        }
    }

    static func interruptActiveFlow() {
        PythonExecutor.shared.interruptActiveWork()
    }

    private static func loadYtDlpModule() throws -> PythonObject {
        let scriptURL = PythonScripts.ytDlpScriptURL
        let scriptPath = scriptURL.path
        let scriptDirectoryPath = scriptURL.deletingLastPathComponent().path

        let sys = try Python.attemptImport("sys")
        if !insertedScriptDirectories.contains(scriptDirectoryPath) {
            let sysPath = try pythonMember(sys, named: "path")
            let insert = try pythonMember(sysPath, named: "insert")
            _ = try insert.throwing.dynamicallyCall(withArguments: [0, scriptDirectoryPath])
            insertedScriptDirectories.insert(scriptDirectoryPath)
        }

        let importlibUtil = try Python.attemptImport("importlib.util")
        let moduleName = "palladium_runtime_ytdlp"

        let specFromFileLocation = try pythonMember(importlibUtil, named: "spec_from_file_location")
        let spec = try specFromFileLocation.throwing.dynamicallyCall(withArguments: [moduleName, scriptPath])

        let moduleFromSpec = try pythonMember(importlibUtil, named: "module_from_spec")
        let module = try moduleFromSpec.throwing.dynamicallyCall(withArguments: [spec])

        let modules = try pythonMember(sys, named: "modules")
        let operatorModule = try Python.attemptImport("operator")
        let setItem = try pythonMember(operatorModule, named: "setitem")
        _ = try setItem.throwing.dynamicallyCall(withArguments: [modules, moduleName, module])

        let loader = try pythonMember(spec, named: "loader")
        let execModule = try pythonMember(loader, named: "exec_module")
        _ = try execModule.throwing.dynamicallyCall(withArguments: [module])
        return module
    }

    private static func pythonMember(_ object: PythonObject, named name: String) throws -> PythonObject {
        guard let member = object.checking[dynamicMember: name] else {
            throw PythonModuleLoadError.missingAttribute(name)
        }
        return member
    }

    private static func callPythonFunction(
        _ function: PythonObject,
        arguments: [PythonConvertible]
    ) -> String {
        do {
            let result = try function.throwing.dynamicallyCall(withArguments: arguments)
            return String(result) ?? ""
        } catch {
            return fallbackPythonErrorPayload(error)
        }
    }

    private static func fallbackPythonErrorPayload(_ error: Error) -> String {
        let message = String(describing: error)
        let isCancelled = message.contains("KeyboardInterrupt") || message.localizedCaseInsensitiveContains("cancel requested")
        let payload: [String: Any] = [
            "pip_attempted": false,
            "pip_exit_code": NSNull(),
            "yt_exit_code": isCancelled ? 130 : NSNull(),
            "cancelled": isCancelled,
            "success": false,
            "downloaded_path": NSNull(),
            "output": message,
            "updates_available": false,
            "updates_summary": isCancelled ? "Cancelled." : "Not checked yet.",
            "versions": [:],
            "available_versions": [:],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"success\":false,\"cancelled\":\(isCancelled ? "true" : "false"),\"output\":\"\(message.replacingOccurrences(of: "\"", with: "\\\""))\"}"
        }
        return text
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
        let cancelled = result["cancelled"] as? Bool ?? false
        let updatesAvailable = result["updates_available"] as? Bool ?? false
        let updatesSummary = result["updates_summary"] as? String ?? "Not checked yet."
        let output = result["output"] as? String ?? ""
        let versions = normalizedVersions(from: result["versions"])
        let availableVersions = normalizedAvailableVersions(from: result["available_versions"])

        let summary = """
        pip attempted: \(pipAttempted)
        pip exit code: \(pipExitCode.map(String.init) ?? "none")
        cancelled: \(cancelled)
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
            statusText: cancelled ? "cancelled" : (success ? "success" : "error"),
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

private enum PythonModuleLoadError: Error, CustomStringConvertible {
    case missingAttribute(String)

    var description: String {
        switch self {
        case .missingAttribute(let name):
            return "Missing Python attribute: \(name)"
        }
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
    private let stateLock = NSLock()
    private var pythonThread: Thread!
    private var activePythonThreadID: UInt = 0

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
            let task = PythonWorkItem { [self] in
                setActivePythonThreadID(PythonCAPI.threadIdent())
                defer { setActivePythonThreadID(0) }
                continuation.resume(returning: work())
            }
            perform(#selector(executeWorkItem(_:)), on: pythonThread, with: task, waitUntilDone: false)
        }
    }

    func interruptActiveWork() {
        let threadID: UInt = stateLock.withLock {
            activePythonThreadID
        }
        guard threadID != 0 else { return }

        let gilState = PythonCAPI.gilEnsure()
        defer { PythonCAPI.gilRelease(gilState) }

        let result = PythonCAPI.setAsyncException(threadID, PythonCAPI.keyboardInterruptException)
        if result > 1 {
            _ = PythonCAPI.setAsyncException(threadID, nil)
        }
    }

    private func setActivePythonThreadID(_ threadID: UInt) {
        stateLock.withLock {
            activePythonThreadID = threadID
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

private enum PythonCAPI {
    private typealias PyGILStateEnsureFn = @convention(c) () -> Int32
    private typealias PyGILStateReleaseFn = @convention(c) (Int32) -> Void
    private typealias PyThreadGetIdentFn = @convention(c) () -> UInt
    private typealias PyThreadStateSetAsyncExcFn = @convention(c) (UInt, UnsafeMutableRawPointer?) -> Int32

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen(nil, RTLD_NOW)
    }()

    private static let gilEnsureFn: PyGILStateEnsureFn? = loadFunction(named: "PyGILState_Ensure")
    private static let gilReleaseFn: PyGILStateReleaseFn? = loadFunction(named: "PyGILState_Release")
    private static let threadIdentFn: PyThreadGetIdentFn? = loadFunction(named: "PyThread_get_thread_ident")
    private static let asyncExcFn: PyThreadStateSetAsyncExcFn? = loadFunction(named: "PyThreadState_SetAsyncExc")
    private static let keyboardInterruptSymbol: UnsafeMutableRawPointer? = {
        guard let handle else { return nil }
        return dlsym(handle, "PyExc_KeyboardInterrupt")
    }()

    static func gilEnsure() -> Int32 {
        gilEnsureFn?() ?? 0
    }

    static func gilRelease(_ state: Int32) {
        gilReleaseFn?(state)
    }

    static func threadIdent() -> UInt {
        threadIdentFn?() ?? 0
    }

    static var keyboardInterruptException: UnsafeMutableRawPointer? {
        guard let keyboardInterruptSymbol else { return nil }
        return keyboardInterruptSymbol
            .assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            .pointee
    }

    static func setAsyncException(_ threadID: UInt, _ exception: UnsafeMutableRawPointer?) -> Int32 {
        asyncExcFn?(threadID, exception) ?? 0
    }

    private static func loadFunction<T>(named name: String) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
