# Project Structure

This map covers tracked source and configuration files. Generated build products and locally installed frameworks are summarized by directory rather than listed file by file.

## Top Level

```text
Palladium/
├── .github/                 GitHub funding and build automation
├── docs/                    Project documentation
├── Palladium/               Main iOS app target
├── Palladium.xcodeproj/     Xcode project and Swift Package resolution
├── ShareExtension/          iOS share extension target
├── Version.xcconfig         Shared app version, build, and release-status settings
├── privacy-manifests/       Privacy manifests copied into the Python runtime
├── scripts/                 Build and validation helper scripts
├── Frameworks/              Local, untracked Python, FFmpeg, and curl-cffi dependencies
├── build_ipa.sh             Command-line IPA build script
├── CHANGELOG.md             Release history
├── LICENSE                  GPLv3 license text
└── README.md                Project overview and contributor entry point
```

## Automation and Project Configuration

| Path | Purpose |
| --- | --- |
| `.github/FUNDING.yml` | GitHub Sponsors configuration. |
| `.github/workflows/build_ipa.yml` | GitHub Actions workflow that downloads local dependencies and builds the IPA. |
| `.gitignore` | Files and local dependencies excluded from Git. |
| `Palladium.xcodeproj/project.pbxproj` | Targets, build phases, build settings, and file references for Xcode. |
| `Version.xcconfig` | Single source for the app version, build number, and final-build flag. |
| `Palladium.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | Workspace definition. |
| `Palladium.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Pinned Swift Package dependencies. |
| `build_ipa.sh` | Builds and exports an IPA outside Xcode. |
| `scripts/install_python_runtime.sh` | Copies Python runtime files and privacy manifests into the app bundle during builds. |
| `scripts/python_tests/` | Split Python unittest modules and shared helpers for package/runtime behavior. |
| `scripts/update_build_metadata.sh` | Writes Git commit and final-build metadata into the built app Info.plist. |
| `scripts/test_package_source_modes.py` | Compatibility runner for split Python package/runtime tests. |

## Main App: `Palladium/`

| Path | Purpose |
| --- | --- |
| `PalladiumApp.swift` | SwiftUI app entry point and root app configuration. |
| `Info.plist` | Main app bundle metadata and iOS configuration. |
| `PalladiumDebug.entitlements` | Debug signing capabilities. |
| `AppIntents/ShortcutDownloadIntents.swift` | App Shortcuts intents for starting downloads. |
| `Models/AppAppearanceMode.swift` | Appearance-mode setting model. |
| `Models/DownloadOptions.swift` | Download option model and persisted settings. |
| `Models/ImportedCookieFile.swift` | Imported cookie-file model. |
| `Models/LinkHistory.swift` | Previously used link model and history storage data. |
| `Models/PackageSourceMode.swift` | Package-source selection model. |
| `Models/URLAllowlist.swift` | URL allowlist model. |

### Views

| Path | Purpose |
| --- | --- |
| `Views/ContentView.swift` | Root UI, tab layout, and shared view state. |
| `Views/ContentView+Cookies.swift` | Cookie import and management UI logic. |
| `Views/ContentView+DownloadFlow.swift` | Download initiation and progress flow. |
| `Views/ContentView+History.swift` | Download and link history behavior. |
| `Views/ContentView+Notifications.swift` | Local notification handling. |
| `Views/ContentView+Packages.swift` | Python package management behavior. |
| `Views/ContentView+PostDownload.swift` | Actions performed after a download completes. |
| `Views/ContentView+Preferences.swift` | Shared preference access and updates. |
| `Views/ContentView+Storage.swift` | Download storage and file-management behavior. |
| `Views/ContentView+Support.swift` | Support, diagnostics, and helper UI behavior. |
| `Views/ContentView+URLAllowlists.swift` | URL allowlist UI behavior. |
| `Views/Tabs/DownloadTabView.swift` | Main download screen. |
| `Views/Tabs/PackagesTabView.swift` | Python package management screen. |
| `Views/Tabs/SavedDownloadsTabView.swift` | Saved-downloads browser. |
| `Views/Tabs/ConsoleTabView.swift` | In-app log console. |
| `Views/Tabs/SettingsTabView.swift` | Settings tab container and navigation. |
| `Views/Tabs/Settings/AfterDownloadSettingsView.swift` | Post-download settings screen. |
| `Views/Tabs/Settings/AdvancedSettingsView.swift` | Advanced runtime settings screen. |
| `Views/Tabs/Settings/AppearanceSettingsView.swift` | Appearance settings screen. |
| `Views/Tabs/Settings/CookiesSettingsView.swift` | Cookie settings screen. |
| `Views/Tabs/Settings/DownloadArgumentsSettingsView.swift` | Custom yt-dlp argument settings screen. |
| `Views/Tabs/Settings/DownloadBehaviorSettingsView.swift` | Download behavior settings screen. |
| `Views/Tabs/Settings/DownloadModesSettingsView.swift` | Download-mode settings screen. |
| `Views/Tabs/Settings/DownloadOptionsSettingsView.swift` | Download option settings screen. |
| `Views/Tabs/Settings/DownloadsTabSettingsView.swift` | Downloads-tab settings screen. |
| `Views/Tabs/Settings/HistorySettingsView.swift` | History settings screen. |
| `Views/Tabs/Settings/NotificationsSettingsView.swift` | Notification settings screen. |
| `Views/Tabs/Settings/PackageManagerSettingsView.swift` | Package-manager settings screen. |
| `Views/Tabs/Settings/PackagesSettingsView.swift` | Package source and package settings screen. |
| `Views/Tabs/Settings/StorageSettingsView.swift` | Storage settings screen. |
| `Views/Tabs/Settings/URLAllowlistsSettingsView.swift` | URL allowlist settings screen. |
| `Views/Tabs/Settings/UseInterfaceSettingsView.swift` | Interface-use settings screen. |
| `Views/Tabs/Settings/about.swift` | About screen. |

### Services

| Path | Purpose |
| --- | --- |
| `Services/FFmpeg/SwiftFFmpegBridge.swift` | Swift interface to bundled FFmpeg functionality. |
| `Services/Logging/ConsoleLogStore.swift` | Store backing the in-app console. |
| `Services/Shortcuts/ShortcutDownloadRequestStore.swift` | Transfers download requests from App Shortcuts into the app. |
| `Services/Python/PythonFlowRunner.swift` | Runs bundled Python flows from Swift. |
| `Services/Python/PythonScripts.swift` | Locates and prepares bundled Python scripts. |
| `Services/Python/yt_dlp_flow.py` | Python flow that invokes yt-dlp for downloads. |
| `Services/Python/palladium_ytdlp/__init__.py` | Python package marker and exports. |
| `Services/Python/palladium_ytdlp/args.py` | Builds yt-dlp command arguments. |
| `Services/Python/palladium_ytdlp/entrypoints.py` | Stable public Python entry point facade used by Swift. |
| `Services/Python/palladium_ytdlp/ffmpeg_bridge.py` | Connects Python download work to FFmpeg. |
| `Services/Python/palladium_ytdlp/files.py` | Download file and path helpers. |
| `Services/Python/palladium_ytdlp/gallery.py` | gallery-dl installation, resolution, and download flows. |
| `Services/Python/palladium_ytdlp/maintenance.py` | Python runtime package maintenance flow. |
| `Services/Python/palladium_ytdlp/packages.py` | Python package installation and source helpers. |
| `Services/Python/palladium_ytdlp/runtime.py` | Runtime reset, module invalidation, and cancellation helpers. |
| `Services/Python/palladium_ytdlp/shared.py` | Shared Python helpers and constants. |
| `Services/Python/palladium_ytdlp/webkit_jsi.py` | WebKit JavaScript integration used by yt-dlp. |
| `Services/Python/palladium_ytdlp/ytdlp.py` | yt-dlp download flow and playlist progress tracking. |

### Resources

| Path | Purpose |
| --- | --- |
| `Resources/Assets.xcassets/Contents.json` | Asset catalog metadata. |
| `Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | Accent color definition. |
| `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | App icon metadata. |
| `Resources/Assets.xcassets/AppIcon.appiconset/*.png` | App icon variants. |
| `Resources/Assets.xcassets/palladium_dark.imageset/Contents.json` | Dark logo metadata. |
| `Resources/Assets.xcassets/palladium_dark.imageset/palladium_dark.png` | Dark logo image. |
| `Resources/Assets.xcassets/palladium_light.imageset/Contents.json` | Light logo metadata. |
| `Resources/Assets.xcassets/palladium_light.imageset/palladium_light.png` | Light logo image. |
| `Resources/Localizable.xcstrings` | Localized app strings. |

## Share Extension: `ShareExtension/`

| Path | Purpose |
| --- | --- |
| `ShareViewController.swift` | Receives shared URLs and forwards them to Palladium. |
| `Info.plist` | Share extension bundle metadata. |
| `ShareExtension.entitlements` | Share extension signing capabilities and app-group access. |
| `Base.lproj/MainInterface.storyboard` | Share extension interface definition. |

## Other Files and Directories

| Path | Purpose |
| --- | --- |
| `docs/ALLOWLISTS.md` | URL allowlist format and configuration instructions. |
| `docs/BUILD.md` | Local dependency setup and Xcode build instructions. |
| `docs/STRUCTURE.md` | This project map. |
| `privacy-manifests/python/_hashlib.xcprivacy` | Required-reason API declaration for Python's hashlib module. |
| `privacy-manifests/python/_ssl.xcprivacy` | Required-reason API declaration for Python's SSL module. |
| `CHANGELOG.md` | Versioned change history. |
| `LICENSE` | GPLv3 terms. |
| `Frameworks/Python.xcframework` | Locally installed Python runtime; required to build and intentionally untracked. |
| `Frameworks/SwiftFFmpeg-iOS` | Locally installed SwiftFFmpeg package and FFmpeg framework; required to build and intentionally untracked. |
| `Frameworks/SwiftCurlCffi-iOS` | Locally installed Swift package containing the iOS curl-cffi payload; required to build and intentionally untracked. |

## Typical Change Locations

- Download behavior: start with `Palladium/Views/ContentView+DownloadFlow.swift` and `Palladium/Services/Python/yt_dlp_flow.py`.
- yt-dlp options or package behavior: use `Palladium/Services/Python/palladium_ytdlp/`.
- UI screens: use `Palladium/Views/Tabs/`; settings screens are in `Palladium/Views/Tabs/Settings/`.
- Persistent app settings and models: use `Palladium/Models/` and `Palladium/Views/ContentView+Preferences.swift`.
- Build dependencies or build phases: use `docs/BUILD.md`, `scripts/install_python_runtime.sh`, and `Palladium.xcodeproj/project.pbxproj`.
