#if DEBUG
import Darwin
import Foundation
import SwiftFFmpeg
import UIKit

nonisolated enum DeveloperFramework: String, CaseIterable, Identifiable, Sendable {
    case app
    case python
    case ffmpeg
    case curlCffi
    case quickJS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: "App"
        case .python: "Python"
        case .ffmpeg: "FFmpeg"
        case .curlCffi: "curl_cffi"
        case .quickJS: "QuickJS"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app.badge"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .ffmpeg: "film"
        case .curlCffi: "network"
        case .quickJS: "curlybraces"
        }
    }
}

nonisolated struct DeveloperDiagnosticDetail: Identifiable, Hashable, Sendable {
    let key: String
    let value: String

    var id: String { key }
}

nonisolated struct DeveloperDiagnosticResult: Sendable {
    let ok: Bool
    let output: String
    let details: [DeveloperDiagnosticDetail]
    let error: String?
    let durationMS: Int

    var report: String {
        var lines = ["status: \(ok ? "passed" : "failed") (\(durationMS) ms)"]
        if let error { lines.append("error: \(error)") }
        lines += details.map { "\($0.key): \($0.value)" }
        if !output.isEmpty { lines.append(output) }
        return lines.joined(separator: "\n")
    }
}

nonisolated struct DeveloperDiagnosticCheck: Identifiable, Sendable {
    let id: String
    let framework: DeveloperFramework
    let title: String
    let run: @Sendable () async -> DeveloperDiagnosticResult
}

nonisolated enum DeveloperDiagnostics {
    private typealias QuickJSRun = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias QuickJSFree = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    // FFmpeg's CLI entry points share global state, so native runs never overlap.
    private static let nativeQueue = DispatchQueue(
        label: "com.tfourj.Palladium.developer-diagnostics",
        qos: .userInitiated
    )

    static let defaultPythonSource = "import sys, platform\nprint(platform.platform())\nsys.version_info[:3]"
    static let defaultJavaScriptSource = "Promise.resolve('živjo 🌍').then(value => console.log(value))"
    static let defaultCurlURL = "https://tls.browserleaks.com/json"
    static let defaultImpersonateTarget = "chrome"

    static let standardChecks: [DeveloperDiagnosticCheck] = [
        DeveloperDiagnosticCheck(id: "python.info", framework: .python, title: "Runtime info") {
            await python("python_info")
        },
        DeveloperDiagnosticCheck(id: "python.eval", framework: .python, title: "Evaluate snippet") {
            await python("python_eval", argument: ["source": "sum(range(10))"])
        },
        DeveloperDiagnosticCheck(id: "ffmpeg.version", framework: .ffmpeg, title: "Native ffmpeg -version") {
            await ffmpeg(tool: .ffmpeg, arguments: ["-hide_banner", "-version"])
        },
        DeveloperDiagnosticCheck(id: "ffprobe.version", framework: .ffmpeg, title: "Native ffprobe -version") {
            await ffmpeg(tool: .ffprobe, arguments: ["-hide_banner", "-version"])
        },
        DeveloperDiagnosticCheck(id: "ffmpeg.encode", framework: .ffmpeg, title: "Native encode and probe") {
            await ffmpegEncodeTest()
        },
        DeveloperDiagnosticCheck(id: "ffmpeg.bridge", framework: .ffmpeg, title: "Python bridge") {
            await python("ffmpeg_bridge")
        },
        DeveloperDiagnosticCheck(id: "curl.info", framework: .curlCffi, title: "Import and targets") {
            await python("curl_cffi_info")
        },
        DeveloperDiagnosticCheck(id: "curl.request", framework: .curlCffi, title: "Impersonated request") {
            await curlRequest(url: defaultCurlURL, impersonate: defaultImpersonateTarget)
        },
        DeveloperDiagnosticCheck(id: "quickjs.info", framework: .quickJS, title: "Native engine info") {
            await quickJS(["operation": "info"])
        },
        DeveloperDiagnosticCheck(id: "quickjs.eval", framework: .quickJS, title: "Native evaluate") {
            await quickJS(["operation": "evaluate", "source": defaultJavaScriptSource])
        },
        DeveloperDiagnosticCheck(id: "quickjs.bridge", framework: .quickJS, title: "Python bridge") {
            await python("quickjs_bridge", argument: ["source": defaultJavaScriptSource])
        },
    ]

    static func checks(for framework: DeveloperFramework) -> [DeveloperDiagnosticCheck] {
        standardChecks.filter { $0.framework == framework }
    }

    // MARK: App

    @MainActor
    static func appDetails() -> [DeveloperDiagnosticDetail] {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = ProcessInfo.processInfo.environment
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        #if targetEnvironment(simulator)
        let destination = "Simulator"
        #else
        let destination = "Device"
        #endif

        let device = UIDevice.current
        return [
            DeveloperDiagnosticDetail(key: "Version", value: info["CFBundleShortVersionString"] as? String ?? "-"),
            DeveloperDiagnosticDetail(key: "Build", value: info["CFBundleVersion"] as? String ?? "unknown"),
            DeveloperDiagnosticDetail(key: "Commit", value: info["GIT_COMMIT_ID"] as? String ?? "unknown"),
            DeveloperDiagnosticDetail(key: "Final build", value: String(describing: info["APP_FINAL"] ?? "unknown")),
            DeveloperDiagnosticDetail(key: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "unknown"),
            DeveloperDiagnosticDetail(key: "System", value: "\(device.systemName) \(device.systemVersion)"),
            DeveloperDiagnosticDetail(key: "Hardware", value: "\(machine) (\(destination))"),
            DeveloperDiagnosticDetail(key: "SwiftFFmpeg build", value: SwiftFFmpeg.buildCommit),
            DeveloperDiagnosticDetail(key: "JavaScript runtime", value: JavaScriptRuntime.selected.rawValue),
            DeveloperDiagnosticDetail(key: "PYTHONHOME", value: environment["PYTHONHOME"] ?? "unset"),
            DeveloperDiagnosticDetail(key: "Downloads", value: environment["PALLADIUM_DOWNLOADS"] ?? "unset"),
            DeveloperDiagnosticDetail(key: "Cache", value: environment["PALLADIUM_CACHE_DIR"] ?? "unset"),
        ]
    }

    // MARK: Python

    static func python(_ name: String, argument: [String: String] = [:]) async -> DeveloperDiagnosticResult {
        let argumentJSON = (try? JSONSerialization.data(withJSONObject: argument))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let payload = await PythonFlowRunner.runDebugDiagnostic(name: name, argumentJSON: argumentJSON)
        return decodePythonResult(payload)
    }

    static func curlRequest(url: String, impersonate: String) async -> DeveloperDiagnosticResult {
        await python("curl_cffi_request", argument: ["url": url, "impersonate": impersonate])
    }

    static func decodePythonResult(_ payload: String) -> DeveloperDiagnosticResult {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DeveloperDiagnosticResult(
                ok: false,
                output: payload,
                details: [],
                error: "Invalid diagnostic payload",
                durationMS: 0
            )
        }
        let details = (object["details"] as? [String: Any] ?? [:])
            .map { DeveloperDiagnosticDetail(key: $0.key, value: displayValue($0.value)) }
            .sorted { $0.key < $1.key }
        return DeveloperDiagnosticResult(
            ok: object["ok"] as? Bool ?? false,
            output: object["output"] as? String ?? "",
            details: details,
            error: object["error"] as? String,
            durationMS: object["duration_ms"] as? Int ?? 0
        )
    }

    private static func displayValue(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case is [Any], is [String: Any]:
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: value)
        default:
            return String(describing: value)
        }
    }

    // MARK: FFmpeg

    static func ffmpeg(tool: FFmpegTool, arguments: [String]) async -> DeveloperDiagnosticResult {
        await measured {
            let executed = executeFFmpeg(tool: tool, arguments: arguments)
            var details = [DeveloperDiagnosticDetail(key: "swiftffmpeg build", value: SwiftFFmpeg.buildCommit)]
            if let version = ffmpegVersion(from: executed.output) {
                details.append(DeveloperDiagnosticDetail(key: "version", value: version))
            }
            if let configuration = ffmpegConfiguration(from: executed.output) {
                details.append(DeveloperDiagnosticDetail(key: "configuration", value: configuration))
            }
            return (executed.exitCode == 0, executed.output, details, executed.error)
        }
    }

    static func ffmpegEncodeTest() async -> DeveloperDiagnosticResult {
        await measured {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("palladium-debug-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputPath = directory.appendingPathComponent("native-test.mp4").path
            let probeURL = directory.appendingPathComponent("native-test.json")

            let encode = executeFFmpeg(tool: .ffmpeg, arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=15",
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "1",
                "-c:v", "mpeg4", "-c:a", "aac", outputPath,
            ])
            guard encode.exitCode == 0 else {
                return (false, encode.output, [], encode.error ?? "ffmpeg exited with \(encode.exitCode)")
            }

            // The native wrapper mixes FFmpeg's log into captured output, so ffprobe writes JSON to a file.
            let probe = executeFFmpeg(tool: .ffprobe, arguments: [
                "-hide_banner", "-v", "error", "-show_entries", "stream=codec_name",
                "-of", "json", "-o", probeURL.path, outputPath,
            ])
            let probeJSON = (try? Data(contentsOf: probeURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let streams = probeJSON?["streams"] as? [[String: Any]] ?? []
            let codecs = streams.compactMap { $0["codec_name"] as? String }
            let size = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
            let details = [
                DeveloperDiagnosticDetail(key: "streams", value: codecs.joined(separator: ", ")),
                DeveloperDiagnosticDetail(key: "bytes", value: String(size)),
            ]
            return (codecs == ["mpeg4", "aac"], probe.output, details, probe.error)
        }
    }

    // Both tools share one program name in the linked wrapper, so ffprobe also prints "ffmpeg version".
    static func ffmpegVersion(from output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ")
            guard words.count > 2, ["ffmpeg", "ffprobe"].contains(words[0]), words[1] == "version" else { continue }
            return String(words[2])
        }
        return nil
    }

    static func ffmpegConfiguration(from output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("configuration:") }?
            .dropFirst("configuration:".count)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func executeFFmpeg(
        tool: FFmpegTool,
        arguments: [String]
    ) -> (exitCode: Int, output: String, error: String?) {
        do {
            let result = try SwiftFFmpeg.executeDetailed(arguments, tool: tool)
            return (result.exitCode, joinedOutput(result.stdout, result.stderr), nil)
        } catch SwiftFFmpegError.executionFailed(let code, let stdout, let stderr) {
            return (code, joinedOutput(stdout, stderr), "exited with \(code)")
        } catch {
            return (1, "", String(describing: error))
        }
    }

    private static func joinedOutput(_ stdout: String, _ stderr: String) -> String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: QuickJS

    static func quickJS(_ request: [String: String]) async -> DeveloperDiagnosticResult {
        await measured {
            guard let response = invokeQuickJS(request) else {
                return (false, "", [], "QuickJS bridge symbols are unavailable")
            }
            let ok = response["ok"] as? Bool ?? false
            let details = ["name", "version", "status"].compactMap { key in
                (response[key] as? String).map { DeveloperDiagnosticDetail(key: key, value: $0) }
            }
            let error = (response["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return (ok, response["output"] as? String ?? "", details, ok ? nil : error)
        }
    }

    private static func invokeQuickJS(_ request: [String: String]) -> [String: Any]? {
        guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let runSymbol = dlsym(handle, "palladium_quickjs_bridge_run"),
              let freeSymbol = dlsym(handle, "palladium_quickjs_bridge_free"),
              let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        let run = unsafeBitCast(runSymbol, to: QuickJSRun.self)
        let free = unsafeBitCast(freeSymbol, to: QuickJSFree.self)
        guard let pointer = json.withCString({ run($0) }) else { return nil }
        defer { free(pointer) }
        let response = Data(bytes: pointer, count: strlen(pointer))
        return try? JSONSerialization.jsonObject(with: response) as? [String: Any]
    }

    // MARK: Helpers

    private static func measured(
        _ work: @escaping @Sendable () -> (Bool, String, [DeveloperDiagnosticDetail], String?)
    ) async -> DeveloperDiagnosticResult {
        await withCheckedContinuation { continuation in
            nativeQueue.async {
                let clock = ContinuousClock()
                let start = clock.now
                let (ok, output, details, error) = work()
                let elapsed = start.duration(to: clock.now).components
                let durationMS = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
                continuation.resume(returning: DeveloperDiagnosticResult(
                    ok: ok,
                    output: output,
                    details: details,
                    error: error,
                    durationMS: durationMS
                ))
            }
        }
    }
}
#endif
