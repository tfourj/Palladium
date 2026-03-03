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
        let writablePackagesPath = makeWritablePackagesPath()

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

        var pythonPathComponents = [stdlibPath, dynloadPath]
        if let writablePackagesPath {
            pythonPathComponents.insert(writablePackagesPath, at: 0)
            setenv("PALLADIUM_PYTHON_PACKAGES", writablePackagesPath, 1)
        }

        setenv("PYTHONHOME", pythonRoot.path, 1)
        setenv("PYTHONPATH", pythonPathComponents.joined(separator: ":"), 1)
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
}
