<p align="center">
  <img src="Knot/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="112" height="112" alt="Knot logo">
</p>

<h1 align="center">Knot</h1>

<p align="center">Your everyday Mac tools, tied together.</p>

<p align="center">
  <a href="https://github.com/baomi-app/knot/releases/latest">Download for Mac</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">macOS 14+ · Apple Silicon & Intel · MIT</p>

## Features

- Search apps, files, commands, and Quicklinks
- Encrypted clipboard history
- Window snapping and menu bar organization
- Screenshots, annotations, and on-device OCR
- Calculator and customizable global shortcuts

Built with SwiftUI and AppKit. No account, ads, or analytics.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Use `test -destination 'platform=macOS'` in place of `build` to run unit tests. [Release guide](docs/UPDATES.md).

## Privacy

Clipboard history is encrypted locally; OCR runs on device. Automatic update checks connect to GitHub by default and can be disabled in Settings → General. [Privacy policy](docs/privacy-policy.md).

## License

[MIT](LICENSE). [Third-party notices](THIRD_PARTY_NOTICES.md).
