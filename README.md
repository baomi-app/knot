# Knot

**Your everyday Mac tools, tied together.**

Knot is a lightweight, native macOS utility that brings everyday tools into one fast command entry.

## Features

- Search apps, commands, files, and Quicklinks
- Organize menu bar items
- Move and resize windows with shortcuts
- Keep encrypted local clipboard history
- Capture, annotate, and recognize text on screen
- Customize global shortcuts

Knot works locally, requires no account, and requests macOS permissions only when a feature needs them.

## Build

Requires macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Privacy

Clipboard history is encrypted on the Mac, and OCR runs on device. See the [privacy policy](docs/privacy-policy.md) for details.

Third-party acknowledgements are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
