//
//  PalladiumApp.swift
//  Palladium
//
//  Created by TfourJ on 3. 3. 26.
//

import SwiftUI
import Foundation

@main
struct PalladiumApp: App {
    init() {
        retainFFmpegBridgeExports()
        PythonRuntimeBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private enum PythonRuntimeBootstrap {
    static func configure() {
        let bundle = Bundle.main
        let pythonRoot = bundle.bundleURL.appendingPathComponent("python")
        let libRoot = pythonRoot.appendingPathComponent("lib")
        let bundledPackagesPath = bundle.bundleURL.appendingPathComponent("python-packages").path
        let manualPayloadPackagesPath = makeManualPayloadPackagesPath()
        let writablePackagesPath = makeWritablePackagesPath()
        let writableDownloadsPath = makeWritableDownloadsPath()
        let writableCachePath = makeWritableCachePath()

        guard let versionFolder = try? FileManager.default.contentsOfDirectory(
            atPath: libRoot.path
        ).first(where: { $0.hasPrefix("python3.") }) else {
            return
        }

        let stdlibPath = libRoot.appendingPathComponent(versionFolder).path
        let dynloadPath = libRoot
            .appendingPathComponent(versionFolder)
            .appendingPathComponent("lib-dynload")
            .path

        var packagePathComponents: [String] = []
        if let manualPayloadPackagesPath {
            packagePathComponents.append(manualPayloadPackagesPath)
            setenv("PALLADIUM_MANUAL_PAYLOAD_PACKAGES", manualPayloadPackagesPath, 1)
        }
        if FileManager.default.fileExists(atPath: bundledPackagesPath) {
            packagePathComponents.append(bundledPackagesPath)
            setenv("PALLADIUM_BUNDLED_PYTHON_PACKAGES", bundledPackagesPath, 1)
        }
        if let writablePackagesPath {
            packagePathComponents.append(writablePackagesPath)
            setenv("PALLADIUM_PYTHON_PACKAGES", writablePackagesPath, 1)
        }
        let pythonPathComponents = packagePathComponents + [stdlibPath, dynloadPath]
        if let writableDownloadsPath {
            setenv("PALLADIUM_DOWNLOADS", writableDownloadsPath, 1)
        }
        if let writableCachePath {
            setenv("PALLADIUM_CACHE_DIR", writableCachePath, 1)
            setenv("XDG_CACHE_HOME", writableCachePath, 1)
        }
        if let executablePath = bundle.executableURL?.path {
            setenv("PALLADIUM_EXECUTABLE_PATH", executablePath, 1)
        }

        setenv("PYTHONHOME", pythonRoot.path, 1)
        setenv("PYTHONPATH", pythonPathComponents.joined(separator: ":"), 1)
#if targetEnvironment(simulator)
        setenv("PALLADIUM_PAYLOAD_SITE_PACKAGES", "site-packages-iphonesimulator", 1)
#else
        setenv("PALLADIUM_PAYLOAD_SITE_PACKAGES", "site-packages-iphoneos", 1)
#endif
    }

    private static func makeManualPayloadPackagesPath() -> String? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let packagesDir = appSupport.appendingPathComponent("manual-payload-packages", isDirectory: true)
            try FileManager.default.createDirectory(
                at: packagesDir,
                withIntermediateDirectories: true
            )
            return packagesDir.path
        } catch {
            return nil
        }
    }

    private static func makeWritablePackagesPath() -> String? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let packagesDir = appSupport.appendingPathComponent("python-packages", isDirectory: true)
            try FileManager.default.createDirectory(
                at: packagesDir,
                withIntermediateDirectories: true
            )
            return packagesDir.path
        } catch {
            return nil
        }
    }

    private static func makeWritableDownloadsPath() -> String? {
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let downloadsDir = documents.appendingPathComponent("Temp", isDirectory: true)
            let savedDir = documents.appendingPathComponent("Saved", isDirectory: true)
            let cookiesDir = documents.appendingPathComponent("Cookies", isDirectory: true)
            try FileManager.default.createDirectory(
                at: downloadsDir,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: savedDir,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: cookiesDir,
                withIntermediateDirectories: true
            )

            // Keep a visible file in Documents so Files app reliably shows app storage.
            let readmeURL = documents.appendingPathComponent("README.txt")
            if !FileManager.default.fileExists(atPath: readmeURL.path) {
                let text = """
                Palladium app storage

                Temp: temporary video/audio output files
                Saved: files copied via "Save to App Folder"
                Cookies: imported Netscape cookie files for yt-dlp
                """
                try text.write(to: readmeURL, atomically: true, encoding: .utf8)
            }
            return downloadsDir.path
        } catch {
            return nil
        }
    }

    private static func makeWritableCachePath() -> String? {
        do {
            let caches = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let ytdlpCacheDir = caches.appendingPathComponent("yt-dlp", isDirectory: true)
            try FileManager.default.createDirectory(
                at: ytdlpCacheDir,
                withIntermediateDirectories: true
            )
            return ytdlpCacheDir.path
        } catch {
            return nil
        }
    }
}
