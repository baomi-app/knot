# In-app updates

Knot uses [Sparkle 2](https://sparkle-project.org/documentation/) to check for, download, verify, and install updates. Installing restarts the app; executable code is not replaced while it is running. Automatic checking and downloading can be changed in Settings → General.

The feed is the `appcast.xml` asset on the latest stable GitHub release. Each entry points to an immutable, versioned DMG. Both the feed and archive are EdDSA-signed; the app also retains Developer ID signing and notarization.

## One-time maintainer setup

Run `bash scripts/configure-updates.sh`, then put its **public** key in `project.yml` as `SUPublicEDKey` and run `xcodegen generate`. The private key stays in the developer's login Keychain under the Sparkle account `app.baomi.knot`. It is used only by release tools, never by the installed app. Back it up securely using Sparkle's documented export process; do not commit it.

`SPARKLE_BIN_DIR` can point to an existing Sparkle distribution's `bin` directory. Otherwise the scripts resolve the pinned package into `.build/SourcePackages`.

## Release

1. Increment both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Sparkle compares build numbers, so each distributed build must increase.
2. Commit, tag `vVERSION`, and push the code and tag.
3. With the existing signing/notarization configuration, run `DEVELOPMENT_TEAM=YOUR_TEAM bash scripts/release.sh --publish --notes-file PATH`.

Without `--publish`, the script only builds local artifacts. With it, the script uploads the DMG, checksum, and signed feed to a draft release, then publishes it as latest. It refuses to replace an existing release. Do not edit the generated appcast after signing.

The build uses `archive` followed by `-exportArchive` with the Developer ID export method. Export re-signs Sparkle's nested helpers individually and preserves their own entitlements. `verify-app-signing.sh` then checks the app, framework, and each helper for the expected Developer ID team, Hardened Runtime, and absence of debugging entitlements. Do not use `codesign --deep` for signing or apply Knot's entitlements to the helper processes.

Before publishing, verify a lower-build-number app against the new feed and test install/relaunch using notarized builds as described in [Sparkle's testing instructions](https://sparkle-project.org/documentation/#6-test-sparkle-out). Do not alter the installed app's Info.plist to simulate an older version: that invalidates its code signature.

Versions predating the updater need one manual installation. The first updater-enabled release must include `appcast.xml` before update checks can succeed.
