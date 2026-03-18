import Foundation

enum PythonScripts {
    static let ytDlpScript = loadScript(named: "yt_dlp_flow", extension: "py")

    private static func loadScript(named name: String, extension fileExtension: String) -> String {
        let fileName = "\(name).\(fileExtension)"

        for bundle in candidateBundles {
            if let directURL = bundle.url(forResource: name, withExtension: fileExtension),
               let script = try? String(contentsOf: directURL, encoding: .utf8) {
                return script
            }

            if let scriptURL = bundledScriptURL(in: bundle, fileName: fileName),
               let script = try? String(contentsOf: scriptURL, encoding: .utf8) {
                return script
            }
        }

        preconditionFailure("Missing bundled Python script: \(fileName)")
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
