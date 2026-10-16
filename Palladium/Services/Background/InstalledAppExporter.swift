import Foundation

/// Packages the installed app bundle into a patched .ipa, so the patched copy matches the version that is running.
///
/// Bundle identifiers are reset to Palladium's own, so the sideloading tool adds its suffix to the original identifier
/// again instead of to the one it already changed.
nonisolated enum InstalledAppExporter {
    static let originalBundleIdentifier = "com.tfourj.Palladium"
    private static let permittedIdentifiersKey = "BGTaskSchedulerPermittedIdentifiers"

    static func exportPatchedIPA(
        from appURL: URL = Bundle.main.bundleURL,
        permitting identifier: String,
        to outputURL: URL
    ) throws {
        let fileManager = FileManager.default
        let workURL = fileManager.temporaryDirectory
            .appendingPathComponent("ipa-export-\(UUID().uuidString)", isDirectory: true)
        let payloadURL = workURL.appendingPathComponent("Payload", isDirectory: true)
        defer { try? fileManager.removeItem(at: workURL) }

        try fileManager.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        let copiedAppURL = payloadURL.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
        try fileManager.copyItem(at: appURL, to: copiedAppURL)

        var installedIdentifier = ""
        try updateInfoPlist(inBundleAt: copiedAppURL) { plist in
            installedIdentifier = plist[kCFBundleIdentifierKey as String] as? String ?? ""
            plist[kCFBundleIdentifierKey as String] = originalBundleIdentifier
            var identifiers = plist[permittedIdentifiersKey] as? [String] ?? []
            if !identifiers.contains(identifier) {
                identifiers.append(identifier)
            }
            plist[permittedIdentifiersKey] = identifiers
        }

        let pluginsURL = copiedAppURL.appendingPathComponent("PlugIns", isDirectory: true)
        let plugins = (try? fileManager.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil)) ?? []
        for pluginURL in plugins where pluginURL.pathExtension == "appex" {
            try updateInfoPlist(inBundleAt: pluginURL) { plist in
                guard let identifier = plist[kCFBundleIdentifierKey as String] as? String,
                      !installedIdentifier.isEmpty,
                      identifier.hasPrefix(installedIdentifier + ".")
                else {
                    return
                }
                let suffix = identifier.dropFirst(installedIdentifier.count)
                plist[kCFBundleIdentifierKey as String] = originalBundleIdentifier + suffix
            }
        }

        try zip(payloadURL, to: outputURL)
    }

    /// Applies `change` to the bundle's Info.plist and writes it back in its original format.
    private static func updateInfoPlist(inBundleAt bundleURL: URL, change: (inout [String: Any]) -> Void) throws {
        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        var format = PropertyListSerialization.PropertyListFormat.xml
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any]
        else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        change(&plist)

        // Installed bundles can be read-only, and the copy keeps their permissions.
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundleURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
        let patched = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try patched.write(to: plistURL, options: .atomic)
    }

    /// Zips the folder with the system archiver, which keeps the folder as the archive's top-level entry.
    private static func zip(_ folderURL: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folderURL, options: .forUploading, error: &coordinatorError) {
            zipURL in
            do {
                if fileManager.fileExists(atPath: outputURL.path) {
                    try fileManager.removeItem(at: outputURL)
                }
                try fileManager.copyItem(at: zipURL, to: outputURL)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError {
            throw error
        }
    }
}
