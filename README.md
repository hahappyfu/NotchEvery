# NotchEvery

Transform your MacBook's notch into a convenient file drop zone.

[简体中文 🇨🇳](./Resources/i18n/zh-Hans/README.md)

For Developers: You can use [NotchNotification](https://github.com/Lakr233/NotchNotification) in your app.

## 👀 Preview

![Screenshot](./Resources/截屏2024-07-08%2003.14.34.png)

## 🌟 Key Features

- [x] Should work with your menu bar managers
- [x] Drag and drop files to the notch
- [x] Open AirDrop directly from the notch
- [x] Automatically save files for 1 day, can be configured
- [x] Open files with a simple click
- [x] Delete files by holding the option key and clicking the x mark
- [x] Fully open source and privacy-focused
- [x] Free of charge if you do it yourself

## 🚀 Usage

Download the latest version from [Releases](https://github.com/hahappyfu/NotchEvery/releases).

## 🔨 Building from Source

### Prerequisites
- macOS with Xcode installed
- Xcode Command Line Tools

### Build Instructions

#### For Personal Daily Use (Production Build)

This creates a production-optimized build that you can use daily on your Mac.

1. Clone the repository:
```bash
git clone https://github.com/hahappyfu/NotchEvery.git
cd NotchEvery
```

2. Build the app in Release configuration:
```bash
xcodebuild -project NotchDrop.xcodeproj \
  -scheme NotchDrop \
  -configuration Release \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

3. Copy the built app to your Applications folder:
```bash
xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release \
  -derivedDataPath /tmp/NotchDrop-build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
cp -R /tmp/NotchDrop-build/Build/Products/Release/NotchDrop.app ~/Applications/
```

4. Launch the app:
```bash
open ~/Applications/NotchDrop.app
```

**Note:** On first launch, macOS may show a security warning. To open:
- Right-click on `NotchDrop.app` in Applications
- Select "Open"
- Click "Open" in the security dialog

After the first time, the app will open normally.

#### What This Build Does

- **Release Configuration**: Builds with optimizations enabled for better performance
- **Self-Signed**: Uses ad-hoc code signing (no Apple Developer account needed)
- **Production Ready**: Suitable for daily use on your Mac
- **Binary Size**: ~5.1MB
- **Location**: `~/Applications/NotchDrop.app`

#### For Development

For development work, open the project in Xcode:
```bash
open NotchDrop.xcodeproj
```

Then build and run using Xcode (⌘R).

## 🧑‍⚖️ License

[MIT License](./LICENSE)

## 🥰 Acknowledgements

Special thanks to [NotchNook](https://lo.cafe/notchnook) for providing the initial inspiration. This open-source project focuses more on my own needs, simplifies various configurations, and improves compatibility with the software I prefer.

## Sponsor

[LookInside](https://lookinside-app.com/) helps you inspect a running iOS or macOS app UI from your Mac.

---

Copyright © 2026 hahappyfu. All Rights Reserved.
