# Knot

English | [简体中文](README.zh-CN.md)

**A native macOS launcher, clipboard history, window manager, and screenshot tool—in one place.**

[Download for Mac](https://github.com/baomi-app/knot/releases/latest) · [Privacy](docs/privacy-policy.md) · [MIT license](LICENSE) · [Report an issue](https://github.com/baomi-app/knot/issues)

**macOS 14+ · Apple Silicon & Intel · No account required · MIT-licensed source**

Knot brings everyday Mac tasks into one keyboard-driven entry point: open an app, find copied text, arrange a window, or capture and annotate your screen without switching between separate utilities. It is built with SwiftUI and AppKit.

Core processing stays on your Mac. **Automatic update checks are enabled by default and connect to GitHub**; turn them off in Settings → General. Opening a Quicklink visits its destination website.

## Try it in a minute

1. Download the DMG, move Knot to Applications, and open it.
2. Use the launcher shortcut shown in Settings → Shortcuts to search for an app or calculate `12 * 8`.
3. Copy a non-sensitive sample sentence, then search for **Clipboard History** to find it again.
4. Try **Left Half** to arrange a window or **Capture & Annotate** to mark up a screenshot. These features need Accessibility and Screen Recording permission respectively.

The goal is a compact set of everyday tools, not a replacement for every feature in a dedicated launcher or screenshot editor.

## Features

- Search apps, commands, files, and Quicklinks
- Organize menu bar items
- Move and resize windows with shortcuts
- Keep encrypted local clipboard history
- Capture, annotate, and recognize text on screen
- Customize global shortcuts
- Check for and install updates in the app

Knot's core features run locally, require no account, and request macOS permissions only when needed.

## Install

Download the DMG from [Releases](https://github.com/baomi-app/knot/releases/latest) and drag Knot into Applications.

Requires macOS 14 or later. Supports Apple Silicon and Intel Macs.

## Build

Requires macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Tests and CI

After generating the project, run the unit tests on macOS:

```sh
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

[GitHub Actions](https://github.com/baomi-app/knot/actions/workflows/ci.yml) builds the app and runs unit tests on pushes and pull requests, using macOS 15 and Xcode 26.0. The workflow can also be run manually. Build/test logs and XCTest result bundles are retained as artifacts for 7 days. Ordinary CI runs do not sign or publish builds and do not validate interactive screen capture, Accessibility permissions, or menu-bar behavior. Pushes to the `release` branch additionally sign, notarize, and publish a GitHub Release after tests pass; see [release setup and required secrets](docs/UPDATES.md#automatic-releases-from-the-release-branch).

## Privacy and permissions

- No account, advertising, or analytics. Clipboard history uses local AES-GCM encryption with a key in macOS Keychain; OCR uses Apple's on-device Vision framework.
- Accessibility is used for window management and direct clipboard pasting. Screen Recording is used for screenshots and OCR. Launch at Login is optional.
- Automatic update checks connect to GitHub and its download CDN; those services receive standard connection information such as your IP address. Checks can be disabled in Settings → General. Manual checks and update downloads still require a network connection.
- Quicklinks open external destinations; a search Quicklink sends the query you choose to submit to that site.
- Clipboard filtering is best-effort, not a guarantee that passwords or secrets will never be recorded. Clearing history leaves encrypted recovery copies, if any, on disk. Screenshot files are not encrypted by Knot and are not removed when you clear the capture index.

See the [privacy policy](docs/privacy-policy.md) for retention rules, local file locations, and deletion instructions.

## License

Knot's own source code, including the shared Pop capture implementation, is available under the [MIT license](LICENSE). Third-party components retain their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
