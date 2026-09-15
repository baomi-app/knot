#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
PACKAGES_DIR="$ROOT/.build/SourcePackages"
TEAM_ID="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-KnotNotary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-app.baomi.knot}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin}"
REPOSITORY="${GITHUB_REPOSITORY:-baomi-app/knot}"
PUBLISH=false
NOTES_FILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --publish) PUBLISH=true; shift ;;
        --notes-file)
            [ "$#" -ge 2 ] || { echo "--notes-file requires a path" >&2; exit 1; }
            NOTES_FILE="$2"
            shift 2
            ;;
        *) echo "Usage: scripts/release.sh [--publish] [--notes-file PATH]" >&2; exit 1 ;;
    esac
done

if [[ ! "$REPOSITORY" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Invalid GitHub repository: $REPOSITORY" >&2
    exit 1
fi
if [ -n "$NOTES_FILE" ]; then
    [ -f "$NOTES_FILE" ] || { echo "Release notes not found: $NOTES_FILE" >&2; exit 1; }
    NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
fi
cd "$ROOT"
if "$PUBLISH"; then
    if [ -n "$(git status --porcelain)" ]; then
        echo "Commit all source changes before publishing a release." >&2
        exit 1
    fi
    SOURCE_COMMIT="$(git rev-parse HEAD)"
    command -v gh >/dev/null || { echo "GitHub CLI is required for --publish" >&2; exit 1; }
    gh auth status >/dev/null
fi

if ! security find-identity -v -p codesigning | grep -Fq "$IDENTITY"; then
    echo "Missing signing identity: $IDENTITY" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Missing or invalid notarytool profile: $NOTARY_PROFILE" >&2
    echo "Run scripts/configure-notarization.sh once, then retry." >&2
    exit 1
fi

mkdir -p "$ROOT/.build/release" "$DIST_DIR"
BUILD_DIR="$(mktemp -d "$ROOT/.build/release/build.XXXXXX")"
ARCHIVE_PATH="$BUILD_DIR/Knot.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
STAGE_DIR="$BUILD_DIR/dmg-root"
UPDATES_DIR="$BUILD_DIR/updates"

xcodegen generate
xcodebuild -resolvePackageDependencies \
    -project Knot.xcodeproj \
    -scheme Knot \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR"

if [ ! -x "$SPARKLE_BIN_DIR/generate_appcast" ] || [ ! -x "$SPARKLE_BIN_DIR/generate_keys" ]; then
    echo "Sparkle tools not found. Set SPARKLE_BIN_DIR to the Sparkle distribution's bin directory." >&2
    exit 1
fi

CONFIGURED_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Knot/Info.plist 2>/dev/null || true)
if [ -z "$CONFIGURED_KEY" ]; then
    echo "Configure update signing with scripts/configure-updates.sh before releasing." >&2
    exit 1
fi
SIGNING_PUBLIC_KEY=$("$SPARKLE_BIN_DIR/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
if [ "$SIGNING_PUBLIC_KEY" != "$CONFIGURED_KEY" ]; then
    echo "The Sparkle signing key does not match SUPublicEDKey. Release stopped." >&2
    exit 1
fi

xcodebuild archive \
    -project Knot.xcodeproj \
    -scheme Knot \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_USER_SCRIPT_SANDBOXING=NO

# Code Sign on Copy signs the framework but not Sparkle's nested helpers.
# Export performs the required inside-out re-signing, preserving each helper's
# entitlements and removing development-only permissions for distribution.
ditto "$ROOT/scripts/ExportOptions.plist" "$EXPORT_OPTIONS"
plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
plutil -replace signingCertificate -string "$IDENTITY" "$EXPORT_OPTIONS"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP="$EXPORT_PATH/Knot.app"
if [ ! -d "$APP" ]; then
    echo "Export did not contain Knot.app" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Release requires a numeric x.y.z version and monotonically increasing integer build number." >&2
    exit 1
fi
TAG="v$VERSION"
DMG="$DIST_DIR/Knot-$VERSION.dmg"
APPCAST="$DIST_DIR/appcast.xml"
EXPECTED_FEED="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
BUILT_FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP/Contents/Info.plist")
if [ "$BUILT_FEED" != "$EXPECTED_FEED" ]; then
    echo "SUFeedURL must match the publishing repository: $EXPECTED_FEED" >&2
    exit 1
fi
for setting in SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
    if [ "$(/usr/libexec/PlistBuddy -c "Print :$setting" "$APP/Contents/Info.plist")" != "true" ]; then
        echo "$setting must be enabled before release." >&2
        exit 1
    fi
done
if [ -e "$DMG" ]; then
    echo "Release artifact already exists: $DMG. Use a new version or move the previous artifact aside." >&2
    exit 1
fi
if "$PUBLISH"; then
    git rev-parse --verify "refs/tags/$TAG" >/dev/null
    if [ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" ] || [ -n "$(git status --porcelain)" ]; then
        echo "Source changed while building. Release stopped." >&2
        exit 1
    fi
    if [ "$(git rev-list -n 1 "$TAG")" != "$SOURCE_COMMIT" ]; then
        echo "$TAG does not point to the current checkout. Release stopped." >&2
        exit 1
    fi
    REMOTE_COMMIT="$(gh api "repos/$REPOSITORY/commits/$TAG" --jq .sha)"
    if [ "$REMOTE_COMMIT" != "$SOURCE_COMMIT" ]; then
        echo "GitHub tag $TAG does not match the source used for this build. Release stopped." >&2
        exit 1
    fi
    if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
        echo "GitHub release $TAG already exists. Existing release assets will not be overwritten." >&2
        exit 1
    fi
fi

bash "$ROOT/scripts/verify-app-signing.sh" "$APP" "$TEAM_ID"

ARCHS_FOUND=$(lipo -archs "$APP/Contents/MacOS/Knot")
if [[ "$ARCHS_FOUND" != *"arm64"* || "$ARCHS_FOUND" != *"x86_64"* ]]; then
    echo "Expected a universal binary, found: $ARCHS_FOUND" >&2
    exit 1
fi

mkdir -p "$STAGE_DIR"
ditto "$APP" "$STAGE_DIR/Knot.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "Knot $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG"

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)

# Generate from only this release, so every download URL remains immutable even
# when GitHub's /releases/latest pointer advances. Sparkle signs both the archive
# and feed because SURequireSignedFeed is enabled in the archived application.
mkdir -p "$UPDATES_DIR"
ditto "$DMG" "$UPDATES_DIR/$(basename "$DMG")"
"$SPARKLE_BIN_DIR/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
    --full-release-notes-url "https://github.com/$REPOSITORY/releases/tag/$TAG" \
    --link "https://github.com/$REPOSITORY" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o "$UPDATES_DIR/appcast.xml" \
    "$UPDATES_DIR"

xmllint --noout "$UPDATES_DIR/appcast.xml"
FEED_SIGNATURE=$(xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$UPDATES_DIR/appcast.xml")
FEED_VERSION=$(xmllint --xpath 'string(//*[local-name()="version"])' "$UPDATES_DIR/appcast.xml")
if [ -z "$FEED_SIGNATURE" ] || [ "$FEED_VERSION" != "$BUILD_NUMBER" ]; then
    echo "Appcast is missing the signed enclosure or correct build number. Release stopped." >&2
    exit 1
fi
ditto "$UPDATES_DIR/appcast.xml" "$APPCAST"

echo "Release ready: $DMG"
echo "Checksum: $DMG.sha256"
echo "Signed update feed: $APPCAST"

if "$PUBLISH"; then
    NOTES_ARGS=(--generate-notes)
    if [ -n "$NOTES_FILE" ]; then NOTES_ARGS=(--notes-file "$NOTES_FILE"); fi

    # Keep the previous latest feed intact until every new asset has uploaded.
    gh release create "$TAG" "$DMG" "$DMG.sha256" "$APPCAST" \
        --repo "$REPOSITORY" --verify-tag --draft \
        --title "Knot $VERSION" "${NOTES_ARGS[@]}"
    gh release edit "$TAG" --repo "$REPOSITORY" --draft=false --latest
    echo "Published: https://github.com/$REPOSITORY/releases/tag/$TAG"
else
    echo "Nothing was uploaded. Publish the DMG, checksum, and appcast.xml together in the next GitHub release."
fi
