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
import UIKit

struct ContentView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tfourj.Palladium",
        category: "python"
    )
    nonisolated private static let pythonQueue = DispatchQueue(label: "com.tfourj.Palladium.python")

    @State private var isRunning = false
    @State private var statusText = "idle"
    @State private var urlText = ""
    @State private var logText = "Enter a URL and tap Download."
    @State private var packageStatusText = "idle"
    @State private var packageLogText = "Use Refresh Versions or Update Packages."
    @State private var versionsText = "yt-dlp: unknown\nyt-dlp-apple-webkit-jsi: unknown"
    @State private var shareItem: ShareItem?

    var body: some View {
        TabView {
            downloadTab
                .tabItem {
                    Label("Download", systemImage: "arrow.down.circle")
                }

            packagesTab
                .tabItem {
                    Label("Packages", systemImage: "shippingbox")
                }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    private var downloadTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yt-dlp downloader")
                .font(.title2.bold())

            Text("status: \(statusText)")
                .font(.subheadline.monospaced())

            TextField("https://example.com/video", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Button(action: runDownloadFlow) {
                Text(isRunning ? "Running..." : "Download")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

    private var packagesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("package manager")
                .font(.title2.bold())

            Text("status: \(packageStatusText)")
                .font(.subheadline.monospaced())

            Text(versionsText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(action: refreshPackageVersions) {
                    Text(isRunning ? "Running..." : "Refresh Versions")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)

                Button(action: updatePackages) {
                    Text(isRunning ? "Running..." : "Update Packages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }

            ScrollView {
                Text(packageLogText)
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

    private func runDownloadFlow() {
        guard !isRunning else { return }
        let targetURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetURL.isEmpty else { return }

        isRunning = true
        statusText = "running"
        logText = ""

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        setenv("PALLADIUM_LOG_FD", "\(writeFD)", 1)
        setenv("PALLADIUM_DOWNLOAD_URL", targetURL, 1)
        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                logText.append(chunk)
            }
        }

        Task {
            let outcome = await ContentView.runOnPythonQueue {
                ContentView.executePythonFlow()
            }

            unsetenv("PALLADIUM_LOG_FD")
            unsetenv("PALLADIUM_DOWNLOAD_URL")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()

            isRunning = false
            statusText = outcome.statusText
            let outputBody = logText.isEmpty ? outcome.outputText : logText
            logText = "\(outcome.summaryText)\n\n\(outputBody)"
            Self.logger.info("yt-dlp flow finished with status: \(outcome.statusText, privacy: .public)")
            Self.logger.info("\(logText, privacy: .public)")
            print(logText)

            if outcome.statusText == "success",
               let downloadedPath = outcome.downloadedPath,
               FileManager.default.fileExists(atPath: downloadedPath) {
                shareItem = ShareItem(url: URL(fileURLWithPath: downloadedPath))
            }
        }
    }

    private func refreshPackageVersions() {
        runPackageFlow(action: "check")
    }

    private func updatePackages() {
        runPackageFlow(action: "update")
    }

    private func runPackageFlow(action: String) {
        guard !isRunning else { return }

        isRunning = true
        packageStatusText = action == "update" ? "updating" : "checking"
        packageLogText = ""

        let logPipe = Pipe()
        let readHandle = logPipe.fileHandleForReading
        let writeFD = logPipe.fileHandleForWriting.fileDescriptor
        setenv("PALLADIUM_LOG_FD", "\(writeFD)", 1)
        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                packageLogText.append(chunk)
            }
        }

        Task {
            let outcome = await ContentView.runOnPythonQueue {
                ContentView.executePackageFlow(action: action)
            }

            unsetenv("PALLADIUM_LOG_FD")
            readHandle.readabilityHandler = nil
            try? readHandle.close()
            try? logPipe.fileHandleForWriting.close()

            isRunning = false
            packageStatusText = outcome.statusText
            let outputBody = packageLogText.isEmpty ? outcome.outputText : packageLogText
            packageLogText = "\(outcome.summaryText)\n\n\(outputBody)"
            if let versionsText = outcome.versionsText {
                self.versionsText = versionsText
            }
            Self.logger.info("package flow finished with status: \(outcome.statusText, privacy: .public)")
            Self.logger.info("\(packageLogText, privacy: .public)")
            print(packageLogText)
        }
    }

    nonisolated private static func executePythonFlow() -> PythonFlowOutcome {
        let builtins = Python.import("builtins")
        let main = Python.import("__main__")
        _ = builtins.exec(pythonRunnerScript, main.__dict__)
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
                """,
                versionsText: nil,
                downloadedPath: nil
            )
        }

        let pipAttempted = result["pip_attempted"] as? Bool ?? false
        let pipExitCode = result["pip_exit_code"] as? Int
        let ytExitCode = result["yt_exit_code"] as? Int
        let success = result["success"] as? Bool ?? false
        let output = result["output"] as? String ?? ""
        let downloadedPath = result["downloaded_path"] as? String

        let summary = """
        pip attempted: \(pipAttempted)
        pip exit code: \(pipExitCode.map(String.init) ?? "none")
        yt-dlp exit code: \(ytExitCode.map(String.init) ?? "none")
        success: \(success)
        """

        let status = success ? "success" : "error"
        return PythonFlowOutcome(
            statusText: status,
            summaryText: summary,
            outputText: output,
            versionsText: nil,
            downloadedPath: downloadedPath
        )
    }

    nonisolated private static func executePackageFlow(action: String) -> PythonFlowOutcome {
        let builtins = Python.import("builtins")
        let main = Python.import("__main__")
        _ = builtins.exec(pythonRunnerScript, main.__dict__)
        let payload = String(main.run_package_maintenance(action)) ?? ""

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

        let status = success ? "success" : "error"
        return PythonFlowOutcome(
            statusText: status,
            summaryText: summary,
            outputText: output,
            versionsText: versionsText,
            downloadedPath: nil
        )
    }

    nonisolated private static func runOnPythonQueue(
        _ work: @escaping @Sendable () -> PythonFlowOutcome
    ) async -> PythonFlowOutcome {
        await withCheckedContinuation { continuation in
            pythonQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    nonisolated private static let pythonRunnerScript = #"""
import contextlib
import io
import json
import os
import runpy
import sys
import traceback
import importlib.metadata as importlib_metadata
import time

def ensure_pip_entrypoint():
    pip_main = None
    try:
        from pip._internal.cli.main import main as pip_main
        return pip_main
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
                return pip_main
        except Exception:
            print("[palladium] ensurepip fallback failed")
            traceback.print_exc()
            return None

def collect_versions():
    versions = {}
    for package_name in ("yt-dlp", "yt-dlp-apple-webkit-jsi"):
        try:
            versions[package_name] = importlib_metadata.version(package_name)
        except Exception:
            versions[package_name] = "not installed"
    return versions

def run_yt_dlp_flow():
    output = io.StringIO()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    yt_exit_code = None
    downloaded_path = None
    success = False
    download_url = os.environ.get("PALLADIUM_DOWNLOAD_URL", "").strip()
    downloads_dir = os.environ.get("PALLADIUM_DOWNLOADS", "").strip()
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    live_fd_value = os.environ.get("PALLADIUM_LOG_FD")
    live_log_stream = None
    if live_fd_value:
        try:
            live_fd = int(live_fd_value)
            live_log_stream = os.fdopen(live_fd, "w", buffering=1, encoding="utf-8", errors="replace", closefd=False)
        except Exception:
            live_log_stream = None

    class Tee:
        def __init__(self, *streams):
            self.streams = [s for s in streams if s is not None]
        def write(self, data):
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

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")
        if downloads_dir:
            os.makedirs(downloads_dir, exist_ok=True)
            print(f"[palladium] download target: {downloads_dir}")

        needs_yt_dlp_install = False
        needs_webkit_jsi_install = False

        print("[palladium] checking yt_dlp import")
        try:
            import yt_dlp  # noqa: F401
            print("[palladium] yt_dlp already installed")
        except Exception:
            needs_yt_dlp_install = True
            print("[palladium] yt_dlp module missing")

        print("[palladium] checking yt-dlp-apple-webkit-jsi package")
        try:
            importlib_metadata.version("yt-dlp-apple-webkit-jsi")
            print("[palladium] yt-dlp-apple-webkit-jsi already installed")
        except Exception:
            needs_webkit_jsi_install = True
            print("[palladium] yt-dlp-apple-webkit-jsi missing")

        if needs_yt_dlp_install or needs_webkit_jsi_install:
            pip_attempted = True
            pip_main = ensure_pip_entrypoint()
            if pip_main is not None:
                packages = []
                if needs_yt_dlp_install:
                    packages.append("yt-dlp")
                if needs_webkit_jsi_install:
                    packages.append("yt-dlp-apple-webkit-jsi")

                try:
                    pip_args = ["install", "--no-cache-dir", "--progress-bar", "off", "--no-color", *packages]
                    if install_target:
                        pip_args[1:1] = ["--target", install_target]
                    pip_result = pip_main(pip_args)
                    pip_exit_code = 0 if pip_result is None else int(pip_result)
                    print(f"[palladium] pip exit code: {pip_exit_code}")
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] pip install failed")
                    traceback.print_exc()
            else:
                pip_exit_code = 1

            try:
                if install_target and install_target not in sys.path:
                    sys.path.insert(0, install_target)
                import yt_dlp  # noqa: F401
                print("[palladium] yt_dlp import succeeded after install")
            except Exception:
                print("[palladium] yt_dlp still unavailable after install attempt")
                traceback.print_exc()

        if not download_url:
            print("[palladium] no URL provided")
            yt_exit_code = 1
        else:
            print(f"[palladium] running yt-dlp -v {download_url}")
        argv_backup = sys.argv[:]
        cwd_backup = os.getcwd()
        run_started_at = time.time()
        try:
            if download_url:
                if downloads_dir:
                    os.chdir(downloads_dir)
                sys.argv = [
                    "yt-dlp",
                    "-v",
                    "--no-check-certificate",
                    "-P",
                    downloads_dir if downloads_dir else ".",
                    "-o",
                    "%(title)s [%(id)s].%(ext)s",
                    download_url,
                ]
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
                if yt_exit_code == 0:
                    try:
                        scan_dir = downloads_dir if downloads_dir else os.getcwd()
                        candidates = []
                        for filename in os.listdir(scan_dir):
                            full_path = os.path.join(scan_dir, filename)
                            if os.path.isfile(full_path) and not filename.endswith(".part"):
                                mtime = os.path.getmtime(full_path)
                                if mtime >= (run_started_at - 5):
                                    candidates.append((mtime, full_path))
                        if candidates:
                            downloaded_path = max(candidates, key=lambda item: item[0])[1]
                            print(f"[palladium] downloaded file: {downloaded_path}")
                    except Exception:
                        print("[palladium] unable to detect downloaded file path")
                        traceback.print_exc()
        except Exception:
            print("[palladium] unable to execute yt_dlp as __main__")
            traceback.print_exc()
            yt_exit_code = 1
        finally:
            sys.argv = argv_backup
            try:
                os.chdir(cwd_backup)
            except Exception:
                pass
            if live_log_stream is not None:
                try:
                    live_log_stream.flush()
                except Exception:
                    pass

        success = (pip_exit_code in (None, 0)) and (yt_exit_code == 0)
        print(f"[palladium] flow success: {success}")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "yt_exit_code": yt_exit_code,
        "success": success,
        "downloaded_path": downloaded_path,
        "output": output.getvalue(),
    })

def run_package_maintenance(action):
    output = io.StringIO()
    console_stdout = sys.__stdout__ if sys.__stdout__ is not None else None
    console_stderr = sys.__stderr__ if sys.__stderr__ is not None else None
    pip_attempted = False
    pip_exit_code = None
    success = False
    install_target = os.environ.get("PALLADIUM_PYTHON_PACKAGES")
    live_fd_value = os.environ.get("PALLADIUM_LOG_FD")
    live_log_stream = None
    if live_fd_value:
        try:
            live_fd = int(live_fd_value)
            live_log_stream = os.fdopen(live_fd, "w", buffering=1, encoding="utf-8", errors="replace", closefd=False)
        except Exception:
            live_log_stream = None

    class Tee:
        def __init__(self, *streams):
            self.streams = [s for s in streams if s is not None]
        def write(self, data):
            for stream in self.streams:
                try:
                    stream.write(data)
                except UnicodeEncodeError:
                    safe_data = data.encode("ascii", "replace").decode("ascii")
                    stream.write(safe_data)
                if hasattr(stream, "flush"):
                    stream.flush()
            return len(data)
        def flush(self):
            for stream in self.streams:
                if hasattr(stream, "flush"):
                    stream.flush()

    with contextlib.redirect_stdout(Tee(output, console_stdout, live_log_stream)), contextlib.redirect_stderr(Tee(output, console_stderr, live_log_stream)):
        os.environ["PYTHONIOENCODING"] = "utf-8"
        if install_target:
            os.makedirs(install_target, exist_ok=True)
            if install_target not in sys.path:
                sys.path.insert(0, install_target)
            print(f"[palladium] package install target: {install_target}")

        print(f"[palladium] package action: {action}")
        if action == "update":
            pip_attempted = True
            pip_main = ensure_pip_entrypoint()
            if pip_main is not None:
                try:
                    packages = ["yt-dlp", "yt-dlp-apple-webkit-jsi"]
                    pip_args = ["install", "-U", "--no-cache-dir", "--progress-bar", "off", "--no-color", *packages]
                    if install_target:
                        pip_args[1:1] = ["--target", install_target]
                    pip_result = pip_main(pip_args)
                    pip_exit_code = 0 if pip_result is None else int(pip_result)
                    print(f"[palladium] pip exit code: {pip_exit_code}")
                except Exception:
                    pip_exit_code = 1
                    print("[palladium] pip update failed")
                    traceback.print_exc()
            else:
                pip_exit_code = 1

        versions = collect_versions()
        print(f"[palladium] yt-dlp version: {versions.get('yt-dlp')}")
        print(f"[palladium] yt-dlp-apple-webkit-jsi version: {versions.get('yt-dlp-apple-webkit-jsi')}")

        success = (pip_exit_code in (None, 0))
        print(f"[palladium] package flow success: {success}")

    return json.dumps({
        "pip_attempted": pip_attempted,
        "pip_exit_code": pip_exit_code,
        "success": success,
        "versions": versions,
        "output": output.getvalue(),
    })
"""#
}

private struct PythonFlowOutcome: Sendable {
    let statusText: String
    let summaryText: String
    let outputText: String
    let versionsText: String?
    let downloadedPath: String?
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
