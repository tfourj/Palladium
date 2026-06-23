<div align="center">

<img src="Palladium/Resources/Assets.xcassets/palladium_dark.imageset/palladium_dark.png" alt="Palladium Logo" width="200">

# Palladium

On-device iOS media downloader powered by `yt-dlp`, `gallery-dl`, `ffmpeg`, and `PythonKit`.

</div>

<div align="center">
  <a href="https://getpalladium.app" style="text-decoration:none; font-size:18px;">
    getpalladium.app
  </a>
  <br>
  <br>
  <a href="https://apps.apple.com/us/app/palladium-media-manager/id6760206193">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store" height="48">
  </a>
</div>

## What It Does

- Downloads media directly on iPhone and iPad
- Uses `yt-dlp` for media extraction, `gallery-dl` for images, and `ffmpeg` for processing
- Runs Python tooling inside the app

> [!NOTE]
> **AI-assisted development:** Palladium is my third attempt at building a `yt-dlp` GUI for iOS. The first two (one built with Toga/BeeWare and another combining BeeWare with SwiftUI) were fully vibecoded prototypes. Palladium was also built heavily with AI assistance, but its code has been reviewed and refined more than previous prototypes. I originally needed it to avoid YouTube bot-protection issues in [Nickel](https://github.com/tfourj/Nickel).
> While it is actively tested and continuously improved, you may still encounter bugs.
> Feedback is greatly appreciated. If you find a bug, please open an issue and we’ll work to fix it.


## Download

- [Palladium Downloads](https://getpalladium.app/downloads) (AppStore, TestFlight, AltStore PAL, .ipa, ~~AltStore Classic~~)
- .ipa from GitHub
  - Stable: [GitHub Releases](https://github.com/tfourj/Palladium/releases)
  - Nightly: [GitHub Actions](https://github.com/tfourj/Palladium/actions)

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

Build instructions: [docs/BUILD.md](docs/BUILD.md).

Other documentation: [docs/ALLOWLISTS.md](docs/ALLOWLISTS.md) for custom URL allowlists and [docs/STRUCTURE.md](docs/STRUCTURE.md) for a project map.

## Credits & Acknowledgments


- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)
- [`gallery-dl`](https://github.com/mikf/gallery-dl)
- [`yt-dlp-apple-webkit-jsi`](https://github.com/grqz/yt-dlp-apple-webkit-jsi)
- [`ffmpeg`](https://ffmpeg.org/)
- [`PythonKit`](https://github.com/pvieito/PythonKit)
- [`python-apple-support`](https://github.com/beeware/Python-Apple-support)
- [`LAME`](https://lame.sourceforge.io/)
- [`SwiftFFmpeg-iOS`](https://github.com/tfourj/SwiftFFmpeg-iOS)

## License

This project is licensed under the GPLv3 - see the [License](LICENSE) file for details.
