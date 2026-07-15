import Foundation

enum PackageAction: String {
    case check
    case versions
    case update
    case reinstall
    case indexVersions = "index_versions"
    case installPayloadZip = "install_payload_zip"
    case restorePipPackages = "restore_pip_packages"
    case removePackage = "remove_package"

    var initialStatusText: String {
        switch self {
        case .installPayloadZip:
            return "installing"
        case .restorePipPackages:
            return "restoring"
        case .removePackage:
            return "removing"
        case .update, .reinstall:
            return "updating"
        case .indexVersions:
            return "indexing"
        case .check, .versions:
            return "checking"
        }
    }
}

enum PackageSourceMode: String, CaseIterable, Identifiable {
    case stable
    case nightly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return String(localized: "packages.source.stable")
        case .nightly:
            return String(localized: "packages.source.nightly")
        case .custom:
            return String(localized: "packages.source.custom")
        }
    }
}

enum PackageSourceDefaults {
    private static let manifestFileName = "ManagedPipPackages"
    private static let manifestFileExtension = "txt"

    static let manifestURL: URL = {
        if let directURL = Bundle.main.url(
            forResource: manifestFileName,
            withExtension: manifestFileExtension
        ) {
            return directURL
        }

        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            preconditionFailure("Missing managed pip package manifest")
        }

        let expectedFileName = "\(manifestFileName).\(manifestFileExtension)"
        while let item = enumerator.nextObject() as? URL {
            guard item.lastPathComponent == expectedFileName else { continue }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return item
            }
        }

        preconditionFailure("Missing managed pip package manifest")
    }()

    private static let managedPackages: [(name: String, lockedVersion: String?)] = {
        let contents: String
        do {
            contents = try String(contentsOf: manifestURL, encoding: .utf8)
        } catch {
            preconditionFailure("Unable to read managed pip package manifest: \(error.localizedDescription)")
        }

        var packages: [(name: String, lockedVersion: String?)] = []
        var seenNames = Set<String>()
        for (offset, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let entry = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }

            let parsed = parseManifestEntry(entry, lineNumber: offset + 1)
            guard seenNames.insert(parsed.name.lowercased()).inserted else {
                preconditionFailure("Duplicate managed pip package on line \(offset + 1): \(parsed.name)")
            }
            packages.append(parsed)
        }

        guard !packages.isEmpty else {
            preconditionFailure("Managed pip package manifest is empty")
        }
        return packages
    }()

    static let managedPackageNames = managedPackages.map(\.name)
    static let runtimePackageNames = managedPackageNames.filter { $0.lowercased() != "pip" }
    static let lockablePackageNames = managedPackageNames
    static let customSpecs = managedPackages.map { package in
        guard let lockedVersion = package.lockedVersion else { return package.name }
        return "\(package.name)==\(lockedVersion)"
    }.joined(separator: "\n")

    static func normalizedAdditionalPackageName(_ value: String) -> String? {
        let packageName = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packageName.isEmpty,
              packageName.unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0)
              }),
              packageName.first?.isLetter == true || packageName.first?.isNumber == true,
              packageName.last?.isLetter == true || packageName.last?.isNumber == true else {
            return nil
        }

        return packageName.lowercased().replacingOccurrences(
            of: "[-_.]+",
            with: "-",
            options: .regularExpression
        )
    }

    static func normalizedAdditionalPackageNames(_ values: [String]) -> [String] {
        let builtInNames = Set(managedPackageNames.map { $0.lowercased() })
        var seenNames = builtInNames
        return values.compactMap { value in
            guard let packageName = normalizedAdditionalPackageName(value),
                  seenNames.insert(packageName).inserted else {
                return nil
            }
            return packageName
        }
    }

    static func allManagedPackageNames(additionalPackageNames: [String]) -> [String] {
        managedPackageNames + normalizedAdditionalPackageNames(additionalPackageNames)
    }

    static func allRuntimePackageNames(additionalPackageNames: [String]) -> [String] {
        allManagedPackageNames(additionalPackageNames: additionalPackageNames)
            .filter { $0.lowercased() != "pip" }
    }

    private static func parseManifestEntry(
        _ entry: String,
        lineNumber: Int
    ) -> (name: String, lockedVersion: String?) {
        var packageName = entry
        var lockedVersion: String?

        if entry.contains("[") || entry.contains("]") {
            guard let openingBracket = entry.firstIndex(of: "["),
                  openingBracket != entry.startIndex,
                  entry.last == "]",
                  entry.filter({ $0 == "[" }).count == 1 else {
                preconditionFailure("Invalid managed pip package entry on line \(lineNumber): \(entry)")
            }

            packageName = String(entry[..<openingBracket]).trimmingCharacters(in: .whitespacesAndNewlines)
            let versionStart = entry.index(after: openingBracket)
            let versionEnd = entry.index(before: entry.endIndex)
            let version = String(entry[versionStart..<versionEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, !version.contains("]") else {
                preconditionFailure("Invalid managed pip package entry on line \(lineNumber): \(entry)")
            }
            lockedVersion = version
        }

        guard !packageName.isEmpty, !packageName.contains(where: { $0.isWhitespace }) else {
            preconditionFailure("Invalid managed pip package entry on line \(lineNumber): \(entry)")
        }
        return (packageName, lockedVersion)
    }
}
