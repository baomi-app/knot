# Knot

**Your everyday Mac tools, tied together.**

Knot is a focused, native macOS utility suite. It keeps the fast command entry people love while avoiding the weight of a large extension platform.

## Modules

- **Knot Search**: global app, command, and Quicklink search
- **Knot Bar**: menu bar organization
- **Knot Window**: keyboard-driven window management
- **Knot Clipboard**: local clipboard history
- **Knot Capture**: screenshots and on-device OCR
- **Quicklinks**: memorable shortcuts for frequently used URLs

## Current MVP

The first runnable slice includes:

- configurable global launcher (defaults to `Option + Space`)
- local application discovery
- Spotlight-backed file name search
- application and file icons
- safe local arithmetic evaluation
- usage-weighted result ranking
- built-in module commands
- Quicklinks
- encrypted, persistent text and image clipboard history
- pinned clipboard entries protected from automatic cleanup
- direct paste back into the previously active application
- privacy filtering for password managers and concealed pasteboard content
- configurable clipboard retention, history limits, and application exclusions
- active-window layouts through macOS Accessibility APIs
- interactive area capture to a file or the clipboard
- full-screen and interactive window capture
- searchable capture history with file-safe index clearing
- on-device OCR using Apple Vision
- configurable screenshot folder, filename prefix, PNG/JPEG output, and copy-after-save
- native screenshot annotation with pen, arrow, rectangle, colors, and undo
- editable Quicklinks with keyword arguments and URL templates
- versioned JSON import and export for Quicklinks
- native shortcut recording for the launcher, capture, and every window layout
- keyboard navigation and execution
- menu bar lifecycle
- first-run permission guidance with live permission status
- optional launch at login using the native macOS login-item service
- Hidden Bar-style collapsible status-item separator with auto-hide and hover reveal

Clipboard history, including image data, is encrypted with AES-GCM. Its device-only key is stored in Keychain, and the history never leaves the Mac. Content from common password managers and pasteboard items marked concealed or transient is ignored.

Clipboard settings can keep 25-250 entries for a selected retention period. Pinned items survive retention cleanup. Adding an excluded bundle identifier also removes that application's existing entries.

## Build

Knot uses XcodeGen to keep the Xcode project reproducible.

```sh
xcodegen generate
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Open `Knot.xcodeproj` in Xcode to run the app. The app targets macOS 14 or newer.

## Release

Knot's direct-download release is a universal, Developer ID-signed and notarized DMG.
The signing team is `HA3AN589MD` and notarization credentials remain in the login
Keychain rather than in the repository.

Configure notarization once with an Apple app-specific password:

```sh
scripts/configure-notarization.sh
```

Then create, sign, notarize, staple, and verify a release:

```sh
scripts/release.sh
```

The final DMG and its SHA-256 checksum are written to `dist/`. Override the default
Keychain profile with `NOTARY_PROFILE=name` when needed.

Tagged builds can also be released by `.github/workflows/release.yml`. Configure
these GitHub Actions secrets before pushing the first `v*` tag:

- `BUILD_CERTIFICATE_BASE64`: Base64-encoded Developer ID Application `.p12`
- `P12_PASSWORD`: Password used when exporting the `.p12`
- `APPLE_ID`: Apple Developer account email
- `APPLE_ID_PASSWORD`: App-specific password for notarization
- `TEAM_ID`: Apple Developer team ID (`HA3AN589MD`)

The workflow publishes stable asset names, `Knot.dmg` and `Knot.dmg.sha256`, to
the matching GitHub Release.

## baomi.app

Product content for baomi.app lives in `baomi.json`; its icon and bilingual
privacy policies are kept in this repository. The website only needs this app
registration in its `src/data/apps.ts`:

```ts
{ id: "knot", repo: "baomi-app/knot" },
```

The website then reads the metadata from this repository and sends the Download
button to the latest GitHub Release. Push a new website deployment after adding
the registration. Screenshots are optional and can be added later through the
`screenshots` field in `baomi.json`.

Window commands request Accessibility access when first used. Capture commands request Screen Recording access through macOS. After granting either permission, run the command again. Captures are copied to the clipboard by default and are only written to disk when automatic saving is enabled in Capture settings or Save is chosen manually in the annotation editor.

Quicklinks can contain a `{query}` placeholder. For example, a keyword of `g` with `https://www.google.com/search?q={query}` lets `g knot app` open that search directly. Manage Quicklinks from the Knot menu bar item.

Quicklinks can be moved between Macs with the import and export buttons. Imports merge safely and skip duplicate IDs, duplicate keywords, unsupported versions, and invalid URLs.

Launcher, capture, clipboard, and window shortcuts are global and can be recorded under Knot Settings. Capture & Annotate defaults to Command-Shift-X, and Clipboard History defaults to Command-Shift-V. If a new combination is already assigned, Knot swaps the two actions instead of leaving a conflict.

## Product principles

1. Native before extensible
2. One shortcut, few decisions
3. Local by default
4. Modules stay useful on their own
5. Permissions are requested only when a feature is used

## Status

All initial modules now have a native, runnable implementation. Knot Capture shares Pop's ScreenCaptureKit selection and in-place annotation flow. Knot Bar adapts Hidden Bar's MIT-licensed separator-length mechanism; see `THIRD_PARTY_NOTICES.md`. Hold Command while dragging menu bar items to place the less-used group left of Knot Bar's separator.
