//
//  ContentView+Preferences.swift
//  Palladium
//

import Foundation
import Darwin

extension ContentView {
    func buildPresetArgumentsJSON() -> String {
        var payload = DownloadQualityPreferences.load().presetArguments()
        payload["custom"] = customArgsText
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    var resolvedSubtitleLanguagePattern: String {
        if subtitleLanguagePattern == SubtitleLanguageOption.custom.subtitlePattern {
            let trimmed = customSubtitleLanguagePattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? SubtitleLanguageOption.english.subtitlePattern : trimmed
        }
        return subtitleLanguagePattern
    }

    var visibleDownloadPresets: [DownloadPreset] {
        DownloadOptions.visiblePresets(from: downloadPresetSettings)
    }

    func persistPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(rememberSelectedPreset, forKey: Self.rememberSelectedPresetDefaultsKey)
        if rememberSelectedPreset {
            defaults.set(selectedPreset.rawValue, forKey: Self.presetDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.presetDefaultsKey)
        }
        defaults.set(customArgsText, forKey: Self.customArgsDefaultsKey)
        if let data = try? JSONEncoder().encode(downloadPresetSettings) {
            defaults.set(data, forKey: Self.downloadPresetSettingsDefaultsKey)
        }
        defaults.set(extraArgsText, forKey: Self.extraArgsDefaultsKey)
        defaults.set(afterDownloadBehavior.rawValue, forKey: Self.afterDownloadBehaviorDefaultsKey)
        defaults.removeObject(forKey: Self.askUserAfterDownloadDefaultsKey)
        defaults.removeObject(forKey: Self.selectedPostDownloadActionDefaultsKey)
        defaults.set(notificationsEnabled, forKey: Self.notificationsEnabledDefaultsKey)
        defaults.set(autoDownloadOnPaste, forKey: Self.autoDownloadOnPasteDefaultsKey)
        defaults.set(detailedProgressEnabled, forKey: Self.detailedProgressEnabledDefaultsKey)
        defaults.set(shareSheetDownloadMode.rawValue, forKey: Self.shareSheetDownloadModeDefaultsKey)
        defaults.set(showShareSheetFormatButton, forKey: Self.showShareSheetFormatButtonDefaultsKey)
        defaults.set(showShareSheetFillURLButton, forKey: Self.showShareSheetFillURLButtonDefaultsKey)
        defaults.set(downloadPlaylist, forKey: Self.downloadPlaylistDefaultsKey)
        defaults.set(downloadSubtitles, forKey: Self.downloadSubtitlesDefaultsKey)
        defaults.set(embedThumbnail, forKey: Self.embedThumbnailDefaultsKey)
        defaults.set(defaultDownloadPlaylist, forKey: Self.defaultDownloadPlaylistDefaultsKey)
        defaults.set(defaultDownloadSubtitles, forKey: Self.defaultDownloadSubtitlesDefaultsKey)
        defaults.set(defaultEmbedThumbnail, forKey: Self.defaultEmbedThumbnailDefaultsKey)
        defaults.set(defaultUseCookies, forKey: Self.defaultUseCookiesDefaultsKey)
        defaults.set(restoreDownloadDefaults, forKey: Self.restoreDownloadDefaultsDefaultsKey)
        defaults.set(autoRetryFailedDownloads, forKey: Self.autoRetryFailedDownloadsDefaultsKey)
        defaults.set(subtitleLanguagePattern, forKey: Self.subtitleLanguagePatternDefaultsKey)
        defaults.set(customSubtitleLanguagePattern, forKey: Self.customSubtitleLanguagePatternDefaultsKey)
        defaults.set(useCookies, forKey: Self.useCookiesDefaultsKey)
        defaults.set(selectedCookieFileName, forKey: Self.selectedCookieFileNameDefaultsKey)
        defaults.set(linkHistoryEnabled, forKey: Self.linkHistoryEnabledDefaultsKey)
        defaults.set(linkHistoryLimit, forKey: Self.linkHistoryLimitDefaultsKey)
        defaults.set(hideHistoryCount, forKey: Self.hideHistoryCountDefaultsKey)
        defaults.set(appAppearanceMode.rawValue, forKey: Self.appAppearanceModeDefaultsKey)
        defaults.set(showTemporaryDownloads, forKey: Self.showTemporaryDownloadsDefaultsKey)
        defaults.set(checkPackageUpdatesOnLaunch, forKey: Self.checkPackageUpdatesOnLaunchDefaultsKey)
        defaults.set(autoUpdatePackagesOnLaunch, forKey: Self.autoUpdatePackagesOnLaunchDefaultsKey)
        defaults.set(packageSourceMode.rawValue, forKey: Self.packageSourceModeDefaultsKey)
        defaults.set(customPackageSpecsText, forKey: Self.customPackageSpecsDefaultsKey)
        let normalizedLocks = Self.normalizedLockedPackageVersions(lockedPackageVersions)
        if normalizedLocks.isEmpty {
            defaults.removeObject(forKey: Self.lockedPackageVersionsDefaultsKey)
        } else if let data = try? JSONEncoder().encode(normalizedLocks) {
            defaults.set(data, forKey: Self.lockedPackageVersionsDefaultsKey)
        }
        defaults.set(youtubePatchMode.rawValue, forKey: Self.youtubePatchModeDefaultsKey)
    }

    static func loadSelectedPreset(rememberSelection: Bool) -> DownloadPreset {
        guard rememberSelection else {
            return .autoVideo
        }
        guard let rawValue = UserDefaults.standard.string(forKey: presetDefaultsKey),
              let preset = DownloadPreset(rawValue: rawValue) else {
            return .autoVideo
        }
        return preset
    }

    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let mibCount = u_int(mib.count)
        var size = MemoryLayout<kinfo_proc>.stride

        let result = mib.withUnsafeMutableBufferPointer { mibPointer in
            sysctl(mibPointer.baseAddress, mibCount, &info, &size, nil, 0)
        }

        if result != 0 {
            return false
        }

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    static func loadCustomArgs() -> String {
        UserDefaults.standard.string(forKey: customArgsDefaultsKey) ?? ""
    }

    static func loadDownloadPresetSettings() -> [DownloadPresetSetting] {
        if let data = UserDefaults.standard.data(forKey: downloadPresetSettingsDefaultsKey),
           let decoded = try? JSONDecoder().decode([DownloadPresetSetting].self, from: data) {
            // Reconcile against the current set of presets: keep stored order, drop unknown
            // entries, and append any preset that was added in a newer app version.
            var reconciled = decoded.filter { stored in
                DownloadPreset.allCases.contains(stored.preset)
            }
            for preset in DownloadPreset.allCases where !reconciled.contains(where: { $0.preset == preset }) {
                reconciled.append(DownloadPresetSetting(preset: preset, isVisible: preset != .custom))
            }
            return reconciled
        }

        // Migration: honor the legacy "show custom" toggle on first launch.
        let showCustom = UserDefaults.standard.bool(forKey: showCustomDownloadOptionDefaultsKey)
        return DownloadPreset.defaultSettings.map { setting in
            setting.preset == .custom ? DownloadPresetSetting(preset: .custom, isVisible: showCustom) : setting
        }
    }

    static func clampShareSheetMode(
        _ mode: ShareSheetDownloadMode,
        visiblePresets: [DownloadPreset]
    ) -> ShareSheetDownloadMode {
        guard let preset = mode.preset else { return mode }
        return visiblePresets.contains(preset) ? mode : .ask
    }

    static func loadExtraArgs() -> String {
        UserDefaults.standard.string(forKey: extraArgsDefaultsKey) ?? ""
    }

    static func loadAfterDownloadBehavior() -> AfterDownloadBehavior {
        if let rawValue = UserDefaults.standard.string(forKey: afterDownloadBehaviorDefaultsKey),
           let behavior = AfterDownloadBehavior(rawValue: rawValue) {
            return behavior
        }
        if loadAskUserAfterDownloadLegacy() {
            return .ask
        }
        switch loadSelectedPostDownloadActionLegacy() {
        case .saveToPhotos:
            return .saveToPhotos
        case .openShareSheet:
            return .openShareSheet
        case .saveToApplicationFolder:
            return .saveToApplicationFolder
        }
    }

    static func loadAskUserAfterDownloadLegacy() -> Bool {
        if UserDefaults.standard.object(forKey: askUserAfterDownloadDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: askUserAfterDownloadDefaultsKey)
    }

    static func loadSelectedPostDownloadActionLegacy() -> PostDownloadAction {
        guard let raw = UserDefaults.standard.string(forKey: selectedPostDownloadActionDefaultsKey),
              let action = PostDownloadAction(rawValue: raw) else {
            return .openShareSheet
        }
        return action
    }

    static func loadNotificationsEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: notificationsEnabledDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: notificationsEnabledDefaultsKey)
    }

    static func loadRememberSelectedPreset() -> Bool {
        if UserDefaults.standard.object(forKey: rememberSelectedPresetDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: rememberSelectedPresetDefaultsKey)
    }

    static func loadAutoDownloadOnPaste() -> Bool {
        if UserDefaults.standard.object(forKey: autoDownloadOnPasteDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: autoDownloadOnPasteDefaultsKey)
    }

    static func loadShareSheetDownloadMode() -> ShareSheetDownloadMode {
        guard let rawValue = UserDefaults.standard.string(forKey: shareSheetDownloadModeDefaultsKey),
              let mode = ShareSheetDownloadMode(rawValue: rawValue) else {
            return .ask
        }
        return mode
    }

    static func loadShowShareSheetFormatButton() -> Bool {
        if UserDefaults.standard.object(forKey: showShareSheetFormatButtonDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: showShareSheetFormatButtonDefaultsKey)
    }

    static func loadShowShareSheetFillURLButton() -> Bool {
        if UserDefaults.standard.object(forKey: showShareSheetFillURLButtonDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: showShareSheetFillURLButtonDefaultsKey)
    }

    static func loadDetailedProgressEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: detailedProgressEnabledDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: detailedProgressEnabledDefaultsKey)
    }

    static func loadDownloadPlaylist() -> Bool {
        if UserDefaults.standard.object(forKey: downloadPlaylistDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: downloadPlaylistDefaultsKey)
    }

    static func loadDownloadSubtitles() -> Bool {
        if UserDefaults.standard.object(forKey: downloadSubtitlesDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: downloadSubtitlesDefaultsKey)
    }

    static func loadEmbedThumbnail() -> Bool {
        if UserDefaults.standard.object(forKey: embedThumbnailDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: embedThumbnailDefaultsKey)
    }

    static func loadDefaultDownloadPlaylist() -> Bool {
        if UserDefaults.standard.object(forKey: defaultDownloadPlaylistDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: defaultDownloadPlaylistDefaultsKey)
    }

    static func loadDefaultDownloadSubtitles() -> Bool {
        if UserDefaults.standard.object(forKey: defaultDownloadSubtitlesDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: defaultDownloadSubtitlesDefaultsKey)
    }

    static func loadDefaultEmbedThumbnail() -> Bool {
        if UserDefaults.standard.object(forKey: defaultEmbedThumbnailDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: defaultEmbedThumbnailDefaultsKey)
    }

    static func loadDefaultUseCookies() -> Bool {
        if UserDefaults.standard.object(forKey: defaultUseCookiesDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: defaultUseCookiesDefaultsKey)
    }

    static func loadRestoreDownloadDefaults() -> Bool {
        if UserDefaults.standard.object(forKey: restoreDownloadDefaultsDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: restoreDownloadDefaultsDefaultsKey)
    }

    static func loadAutoRetryFailedDownloads() -> Bool {
        if UserDefaults.standard.object(forKey: autoRetryFailedDownloadsDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: autoRetryFailedDownloadsDefaultsKey)
    }

    static func loadSubtitleLanguagePattern() -> String {
        guard let rawValue = UserDefaults.standard.string(forKey: subtitleLanguagePatternDefaultsKey) else {
            return SubtitleLanguageOption.english.subtitlePattern
        }
        if rawValue == "en.*" {
            return SubtitleLanguageOption.english.subtitlePattern
        }
        if SubtitleLanguageOption.allCases.contains(where: { $0.subtitlePattern == rawValue }) {
            return rawValue
        }
        return SubtitleLanguageOption.custom.subtitlePattern
    }

    static func loadCustomSubtitleLanguagePattern() -> String {
        if let explicitValue = UserDefaults.standard.string(forKey: customSubtitleLanguagePatternDefaultsKey) {
            return explicitValue
        }
        guard let rawValue = UserDefaults.standard.string(forKey: subtitleLanguagePatternDefaultsKey) else {
            return ""
        }
        if rawValue == "en.*" || SubtitleLanguageOption.allCases.contains(where: { $0.subtitlePattern == rawValue }) {
            return ""
        }
        return rawValue
    }

    static func loadUseCookies() -> Bool {
        if UserDefaults.standard.object(forKey: useCookiesDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: useCookiesDefaultsKey)
    }

    static func loadLinkHistoryEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: linkHistoryEnabledDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: linkHistoryEnabledDefaultsKey)
    }

    static func loadLinkHistoryLimit() -> Int {
        if UserDefaults.standard.object(forKey: linkHistoryLimitDefaultsKey) == nil {
            return defaultLinkHistoryLimit
        }
        let storedLimit = UserDefaults.standard.integer(forKey: linkHistoryLimitDefaultsKey)
        return max(0, min(storedLimit, maxLinkHistoryLimit))
    }

    static func loadHideHistoryCount() -> Bool {
        UserDefaults.standard.bool(forKey: hideHistoryCountDefaultsKey)
    }

    static func loadLinkHistoryEntries(limit: Int = maxLinkHistoryLimit) -> [LinkHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: linkHistoryEntriesDefaultsKey),
              let decoded = try? JSONDecoder().decode([LinkHistoryEntry].self, from: data) else {
            return []
        }
        let clampedLimit = max(0, min(limit, maxLinkHistoryLimit))
        return Array(decoded.prefix(clampedLimit))
    }

    static func loadAppAppearanceMode() -> AppAppearanceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: appAppearanceModeDefaultsKey),
              let mode = AppAppearanceMode(rawValue: rawValue) else {
            return .system
        }
        return mode
    }

    static func loadShowTemporaryDownloads() -> Bool {
        if UserDefaults.standard.object(forKey: showTemporaryDownloadsDefaultsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: showTemporaryDownloadsDefaultsKey)
    }

    static func loadCachedPackageVersionsText() -> String {
        let fallback = PackageSourceDefaults.runtimePackageNames
            .map { "\($0): unknown" }
            .joined(separator: "\n")
        guard let value = UserDefaults.standard.string(forKey: packageVersionsTextDefaultsKey),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }

    static func loadCheckPackageUpdatesOnLaunch() -> Bool {
        if UserDefaults.standard.object(forKey: checkPackageUpdatesOnLaunchDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: checkPackageUpdatesOnLaunchDefaultsKey)
    }

    static func loadAutoUpdatePackagesOnLaunch() -> Bool {
        if UserDefaults.standard.object(forKey: autoUpdatePackagesOnLaunchDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: autoUpdatePackagesOnLaunchDefaultsKey)
    }

    static func loadPackageSourceMode() -> PackageSourceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: packageSourceModeDefaultsKey),
              let mode = PackageSourceMode(rawValue: rawValue) else {
            return .stable
        }
        return mode
    }

    static func loadCustomPackageSpecsText() -> String {
        guard let value = UserDefaults.standard.string(forKey: customPackageSpecsDefaultsKey),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PackageSourceDefaults.customSpecs
        }
        return value
    }

    static func loadLockedPackageVersions() -> [String: String] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: lockedPackageVersionsDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return normalizedLockedPackageVersions(decoded)
        }

        if let dictionary = defaults.dictionary(forKey: lockedPackageVersionsDefaultsKey) as? [String: String] {
            return normalizedLockedPackageVersions(dictionary)
        }

        return [:]
    }

    static func normalizedLockedPackageVersions(_ versions: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for packageName in PackageSourceDefaults.lockablePackageNames {
            let version = versions[packageName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !version.isEmpty {
                normalized[packageName] = version
            }
        }
        return normalized
    }

    static func loadYouTubePatchMode() -> YouTubePatchMode {
        let defaults = UserDefaults.standard
        if let rawValue = defaults.string(forKey: youtubePatchModeDefaultsKey),
           let mode = YouTubePatchMode(rawValue: rawValue) {
            return mode
        }
        if defaults.bool(forKey: disableWebKitJSIPatchDefaultsKey) {
            return .off
        }
        return .webkit
    }
}
