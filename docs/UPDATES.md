# In-app updates

Knot uses [Sparkle 2](https://sparkle-project.org/documentation/) to check for, download, verify, and install updates. Installing restarts the app; executable code is not replaced while it is running. Automatic checking and downloading can be changed in Settings → General.

The feed is the `appcast.xml` asset on the latest stable GitHub release. Each entry points to an immutable, versioned DMG. Both the feed and archive are EdDSA-signed; the app also retains Developer ID signing and notarization.

## One-time maintainer setup

Run `bash scripts/configure-updates.sh`, then put its **public** key in `project.yml` as `SUPublicEDKey` and run `xcodegen generate`. The private key stays in the developer's login Keychain under the Sparkle account `app.baomi.knot`. It is used only by release tools, never by the installed app. Back it up securely using Sparkle's documented export process; do not commit it.

`SPARKLE_BIN_DIR` can point to an existing Sparkle distribution's `bin` directory. Otherwise the scripts resolve the pinned package into `.build/SourcePackages`.

## Automatic releases from the `release` branch

The CI workflow builds and tests every push and pull request. A **push to the branch named `release`** additionally runs the release job after tests pass. Pull requests, other branches, and manual CI runs never publish. The job uses the GitHub Environment named `release`; configure required reviewers and restrict its deployment branches to `release` before enabling publishing. Protect the branch so only reviewed code can access signing credentials.

Configure these environment secrets (never commit their values):

| Secret | Value |
| --- | --- |
| `DEVELOPMENT_TEAM` | Apple Developer team ID |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application `.p12`, including its private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting the `.p12` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | Exact contents of the existing Sparkle private-key export (already base64 text, not base64-encoded again) |

Export the existing Sparkle key on the maintainer Mac using `generate_keys --account app.baomi.knot -x /secure/path/sparkle-key`. See the [pinned Sparkle tool's export/import options](https://github.com/sparkle-project/Sparkle/blob/2.10.0/generate_keys/main.swift). Transfer the file contents securely into the secret and remove the temporary export. Do not generate a new key: the release script verifies it against the public key embedded in the app.

Before each release, increment **both** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, regenerate the project, and commit the changes. Merge or push that commit to `release`. The workflow builds a universal DMG, signs it with Developer ID, notarizes and staples it, and generates the signed Sparkle feed. Only after these steps succeed does it create `vVERSION` at the exact triggering commit, upload the DMG, SHA-256 checksum, and `appcast.xml` to a draft GitHub Release, then publish it as latest with generated notes. No personal GitHub token is needed; the release job alone receives `contents: write` on `GITHUB_TOKEN`.

An existing release or a version tag pointing to another commit stops publishing. A failed upload can leave a draft release; inspect and remove that draft before retrying, rather than overwriting published assets. Release jobs are serialized and are not cancelled by newer pushes while running (GitHub may replace an older pending run). Signing credentials live in a temporary runner keychain and are cleaned up even on failure. No signing credentials or build directories are uploaded as workflow artifacts.

## Manual release

1. Increment both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Sparkle compares build numbers, so each distributed build must increase.
2. Commit, tag `vVERSION`, and push the code and tag.
3. With the existing signing/notarization configuration, run `DEVELOPMENT_TEAM=YOUR_TEAM bash scripts/release.sh --publish --notes-file PATH`.

Without `--publish`, the script only builds local artifacts. With it, the script uploads the DMG, checksum, and signed feed to a draft release, then publishes it as latest. It refuses to replace an existing release. Do not edit the generated appcast after signing.

The build uses `archive` followed by `-exportArchive` with the Developer ID export method. Export re-signs Sparkle's nested helpers individually and preserves their own entitlements. `verify-app-signing.sh` then checks the app, framework, and each helper for the expected Developer ID team, Hardened Runtime, and absence of debugging entitlements. Do not use `codesign --deep` for signing or apply Knot's entitlements to the helper processes.

Before publishing, verify a lower-build-number app against the new feed and test install/relaunch using notarized builds as described in [Sparkle's testing instructions](https://sparkle-project.org/documentation/#6-test-sparkle-out). Do not alter the installed app's Info.plist to simulate an older version: that invalidates its code signature.

Versions predating the updater need one manual installation. The first updater-enabled release must include `appcast.xml` before update checks can succeed.
