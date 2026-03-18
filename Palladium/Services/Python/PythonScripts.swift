import Foundation

enum PythonScripts {
    private static let stagedPythonFiles: [String] = [
        "yt_dlp_flow.py",
        "palladium_ytdlp/__init__.py",
        "palladium_ytdlp/args.py",
        "palladium_ytdlp/entrypoints.py",
        "palladium_ytdlp/ffmpeg_bridge.py",
        "palladium_ytdlp/files.py",
        "palladium_ytdlp/packages.py",
        "palladium_ytdlp/shared.py",
        "palladium_ytdlp/webkit_jsi.py",
    ]

    static let ytDlpScriptURL = stagePythonScripts().appendingPathComponent("yt_dlp_flow.py")

    private static func stagePythonScripts() -> URL {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("PalladiumPythonScripts", isDirectory: true)

        try? fileManager.removeItem(at: rootURL)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        for relativePath in stagedPythonFiles {
            let sourceURL = requiredBundledFileURL(for: relativePath)
            let destinationURL = rootURL.appendingPathComponent(relativePath)
            try? fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }

            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                preconditionFailure("Unable to stage Python script \(relativePath): \(error.localizedDescription)")
            }
        }

        return rootURL
    }

    private static func requiredBundledFileURL(for relativePath: String) -> URL {
        let fileName = (relativePath as NSString).lastPathComponent
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension

        for bundle in candidateBundles {
            if let directURL = bundle.url(forResource: name, withExtension: fileExtension) {
                return directURL
            }

            if let scriptURL = bundledScriptURL(in: bundle, fileName: fileName) {
                return scriptURL
            }
        }

        preconditionFailure("Missing bundled Python script: \(relativePath)")
    }

    private static var candidateBundles: [Bundle] {
        let bundles = [Bundle.main, Bundle(for: BundleSentinel.self)]
        var seenPaths = Set<String>()
        return bundles.filter { seenPaths.insert($0.bundlePath).inserted }
    }

    private static func bundledScriptURL(in bundle: Bundle, fileName: String) -> URL? {
        guard let resourceURL = bundle.resourceURL else { return nil }
        let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            guard item.lastPathComponent == fileName else { continue }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return item
            }
        }

        return nil
    }

    private final class BundleSentinel {}
}
