//
//  ContentView.swift
//  Palladium
//
//  Created by TfourJ on 3. 3. 26.
//

import SwiftUI
import PythonKit
import OSLog
import Foundation

struct ContentView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium",
        category: "python"
    )
    nonisolated(unsafe) private static var pythonRunnerInstalled = false
    nonisolated private static let pythonRunnerInstallLock = NSLock()

    @State private var isRunning = false
    @State private var statusText = "idle"
    @State private var logText = "Tap the button to install yt-dlp if needed and run -v."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yt-dlp setup check")
                .font(.title2.bold())

            Text("status: \(statusText)")
                .font(.subheadline.monospaced())

            Button(action: runYtDlpFlow) {
                Text(isRunning ? "Running..." : "Install yt-dlp and run -v")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)

            ScrollView {
                Text(logText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }

    private func runYtDlpFlow() {
        guard !isRunning else { return }
        isRunning = true
        statusText = "running"
        logText = ""

        let liveLogTask = Task {
            while !Task.isCancelled {
                if let chunk = ContentView.drainPythonLiveLogs(), !chunk.isEmpty {
                    logText.append(chunk)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if let finalChunk = ContentView.drainPythonLiveLogs(), !finalChunk.isEmpty {
                logText.append(finalChunk)
            }
        }

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                ContentView.executePythonFlow()
            }.value

            liveLogTask.cancel()

            isRunning = false
            statusText = outcome.statusText
            let outputBody = logText.isEmpty ? outcome.outputText : logText
            logText = "\(outcome.summaryText)\n\n\(outputBody)"
            Self.logger.info("yt-dlp flow finished with status: \(outcome.statusText, privacy: .public)")
            Self.logger.info("\(logText, privacy: .public)")
            print(logText)
        }
    }

    nonisolated private static func executePythonFlow() -> PythonFlowOutcome {
        ensurePythonRunnerInstalled()
        let main = Python.import("__main__")
        let payload = String(main.run_yt_dlp_flow()) ?? ""

        guard let data = payload.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return PythonFlowOutcome(
                statusText: "error",
                summaryText: "success: false",
                outputText: """
                Failed to decode Python result.

                Raw payload:
                \(payload)
                """
            )
        }

        let pipAttempted = result["pip_attempted"] as? Bool ?? false
        let pipExitCode = result["pip_exit_code"] as? Int
        let ytExitCode = result["yt_exit_code"] as? Int
        let success = result["success"] as? Bool ?? false
        let output = result["output"] as? String ?? ""

        let summary = """
        pip attempted: \(pipAttempted)
        pip exit code: \(pipExitCode.map(String.init) ?? "none")
        yt-dlp exit code: \(ytExitCode.map(String.init) ?? "none")
        success: \(success)
        """

        let status = success ? "success" : "error"
        return PythonFlowOutcome(statusText: status, summaryText: summary, outputText: output)
    }

    nonisolated private static func drainPythonLiveLogs() -> String? {
        ensurePythonRunnerInstalled()
        let main = Python.import("__main__")
        return String(main.drain_live_logs())
    }

    nonisolated private static func ensurePythonRunnerInstalled() {
        pythonRunnerInstallLock.lock()
        defer { pythonRunnerInstallLock.unlock() }
        if pythonRunnerInstalled { return }
        let builtins = Python.import("builtins")
        let main = Python.import("__main__")
        _ = builtins.exec(pythonRunnerScript, main.__dict__)
        pythonRunnerInstalled = true
    }

    nonisolated private static let pythonRunnerScript = #"""
import contextlib
import io
import json
import os
import runpy
import sys
import threading
import traceback

_live_log_chunks = []
_live_log_lock = threading.Lock()

def drain_live_logs():
    with _live_log_lock:
        if not _live_log_chunks:
            return ""
        chunk = "".join(_live_log_chunks)
        _live_log_chunks.clear()
        return chunk

def _push_live_log(data):
    with _live_log_lock:
        _live_log_chunks.append(data)

def run_yt_dlp_flow():
    output = io.StringIO()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    yt_exit_code = None
    success = False
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")

    with _live_log_lock:
        _live_log_chunks.clear()

    class Tee:
        def __init__(self, *streams):
            self.streams = [s for s in streams if s is not None]
        def write(self, data):
            _push_live_log(data)
            for stream in self.streams:
                try:
                    stream.write(data)
                except UnicodeEncodeError:
                    # Some iOS-backed console streams report ASCII only.
                    safe_data = data.encode("ascii", "replace").decode("ascii")
                    stream.write(safe_data)
                if hasattr(stream, "flush"):
                    stream.flush()
            return len(data)
        def flush(self):
            for stream in self.streams:
                if hasattr(stream, "flush"):
                    stream.flush()

    with contextlib.redirect_stdout(Tee(output, console_stdout)), contextlib.redirect_stderr(Tee(output, console_stderr)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")

        print("[palladium] checking yt_dlp import")
        try:
            import yt_dlp  # noqa: F401
            print("[palladium] yt_dlp already installed")
        except Exception:
            pip_attempted = True
            print("[palladium] yt_dlp module missing; installing package yt-dlp via pip")
            pip_main = None
            try:
                from pip._internal.cli.main import main as pip_main
            except Exception:
                print("[palladium] pip entrypoint unavailable")
                traceback.print_exc()
                print("[palladium] attempting ensurepip fallback")
                try:
                    import ensurepip
                    with ensurepip._get_pip_whl_path_ctx() as pip_wheel:
                        pip_wheel_str = str(pip_wheel)
                        if pip_wheel_str not in sys.path:
                            sys.path.insert(0, pip_wheel_str)
                        from pip._internal.cli.main import main as pip_main
                        print("[palladium] pip loaded from ensurepip bundled wheel")
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] ensurepip fallback failed")
                    traceback.print_exc()
            if pip_main is not None:
                try:
                    pip_args = ["install", "--no-cache-dir", "--progress-bar", "off", "--no-color", "yt-dlp"]
                    if install_target:
                        pip_args[1:1] = ["--target", install_target]
                    pip_result = pip_main(pip_args)
                    pip_exit_code = 0 if pip_result is None else int(pip_result)
                    print(f"[palladium] pip exit code: {pip_exit_code}")
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] pip install failed")
                    traceback.print_exc()

            try:
                if install_target and install_target not in sys.path:
                    sys.path.insert(0, install_target)
                import yt_dlp  # noqa: F401
                print("[palladium] yt_dlp import succeeded after install")
            except Exception:
                print("[palladium] yt_dlp still unavailable after install attempt")
                traceback.print_exc()

        print("[palladium] running yt-dlp -v")
        argv_backup = sys.argv[:]
        try:
            sys.argv = ["yt-dlp", "-v", "--version"]
            try:
                runpy.run_module("yt_dlp", run_name="__main__", alter_sys=True)
                yt_exit_code = 0
            except SystemExit as exc:
                if exc.code is None:
                    yt_exit_code = 0
                elif isinstance(exc.code, int):
                    yt_exit_code = exc.code
                else:
                    print(f"[palladium] unexpected SystemExit code: {exc.code}")
                    yt_exit_code = 1
            except Exception:
                print("[palladium] yt-dlp execution failed")
                traceback.print_exc()
                yt_exit_code = 1
        except Exception:
            print("[palladium] unable to execute yt_dlp as __main__")
            traceback.print_exc()
            yt_exit_code = 1
        finally:
            sys.argv = argv_backup

        success = (pip_exit_code in (None, 0)) and (yt_exit_code == 0)
        print(f"[palladium] flow success: {success}")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "yt_exit_code": yt_exit_code,
        "success": success,
        "output": output.getvalue(),
    })
"""#
}

private struct PythonFlowOutcome: Sendable {
    let statusText: String
    let summaryText: String
    let outputText: String
}

#Preview {
    ContentView()
}
