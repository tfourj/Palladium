# Build

## Requirements

- Install Xcode
- Clone this repo
- Create `Frameworks` in the repo root if it does not exist

Required layout:

```text
Palladium/
  Frameworks/
    Python.xcframework
    SwiftFFmpeg-iOS/
```

## Python

### PythonKit

- Open `Palladium.xcodeproj`
- Let Xcode resolve packages
- If needed: `File -> Packages -> Resolve Package Versions`

### python-apple-support

- Download a `Python.xcframework` build from [python-apple-support](https://github.com/beeware/Python-Apple-support/releases/latest)
- Put it here:

```text
Frameworks/Python.xcframework
```

## FFmpeg

- Download `SwiftFFmpeg-iOS` from:

[tfourj/SwiftFFmpeg-iOS/releases](https://github.com/tfourj/SwiftFFmpeg-iOS/releases)

- Or build `SwiftFFmpeg-iOS` yourself
- Put the folder here:

```text
Frameworks/SwiftFFmpeg-iOS
```

- If `FFmpeg.xcframework` is missing, build it inside that folder:

```bash
cd Frameworks/SwiftFFmpeg-iOS
./Scripts/build-ffmpeg-ios.sh
```

- After build, this must exist:

```text
Frameworks/SwiftFFmpeg-iOS/FFmpeg.xcframework
```

## Build In Xcode

- Open `Palladium.xcodeproj`
- Check that `PythonKit` resolves
- Check that local package `Frameworks/SwiftFFmpeg-iOS` resolves
- Select scheme `Palladium`
- Set your signing team in Signing & Capabilities
- Choose an iPhone or Generic iOS Device
- Press `Run` or `Product -> Build`
