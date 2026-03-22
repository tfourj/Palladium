//
//  ContentView+Preferences.swift
//  Palladium
//

import Foundation
import Darwin

extension ContentView {
    func buildPresetArgumentsJSON() -> String {
        let payload: [String: String] = [
            "custom": customArgsText
        ]
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

    func persistPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(rememberSelectedPreset, forKey: Self.rememberSelectedPresetDefaultsKey)
        if rememberSelectedPreset {
            defaults.set(selectedPreset.rawValue, forKey: Self.presetDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.presetDefaultsKey)
        }
        defaults.set(customArgsText, forKey: Self.customArgsDefaultsKey)
        defaults.set(extraArgsText, forKey: Self.extraArgsDefaultsKey)
        defaults.set(afterDownloadBehavior.rawValue, forKey: Self.afterDownloadBehaviorDefaultsKey)
        defaults.removeObject(forKey: Self.askUserAfterDownloadDefaultsKey)
        defaults.removeObject(forKey: Self.selectedPostDownloadActionDefaultsKey)
        defaults.set(notificationsEnabled, forKey: Self.notificationsEnabledDefaultsKey)
        defaults.set(autoDownloadOnPaste, forKey: Self.autoDownloadOnPasteDefaultsKey)
        defaults.set(detailedProgressEnabled, forKey: Self.detailedProgressEnabledDefaultsKey)
        defaults.set(shareSheetDownloadMode.rawValue, forKey: Self.shareSheetDownloadModeDefaultsKey)
        defaults.set(downloadPlaylist, forKey: Self.downloadPlaylistDefaultsKey)
        defaults.set(downloadSubtitles, forKey: Self.downloadSubtitlesDefaultsKey)
        defaults.set(embedThumbnail, forKey: Self.embedThumbnailDefaultsKey)
        defaults.set(subtitleLanguagePattern, forKey: Self.subtitleLanguagePatternDefaultsKey)
        defaults.set(customSubtitleLanguagePattern, forKey: Self.customSubtitleLanguagePatternDefaultsKey)
        defaults.set(linkHistoryEnabled, forKey: Self.linkHistoryEnabledDefaultsKey)
        defaults.set(appAppearanceMode.rawValue, forKey: Self.appAppearanceModeDefaultsKey)
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

    static func loadDetailedProgressEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: detailedProgressEnabledDefaultsKey) == nil {
            return false
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

    static func loadLinkHistoryEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: linkHistoryEnabledDefaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: linkHistoryEnabledDefaultsKey)
    }

    static func loadLinkHistoryEntries() -> [LinkHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: linkHistoryEntriesDefaultsKey),
              let decoded = try? JSONDecoder().decode([LinkHistoryEntry].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(10))
    }

    static func loadAppAppearanceMode() -> AppAppearanceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: appAppearanceModeDefaultsKey),
              let mode = AppAppearanceMode(rawValue: rawValue) else {
            return .system
        }
        return mode
    }

    static func loadCachedPackageVersionsText() -> String {
        let fallback = "yt-dlp: unknown\nyt-dlp-apple-webkit-jsi: unknown"
        guard let value = UserDefaults.standard.string(forKey: packageVersionsTextDefaultsKey),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }
}
