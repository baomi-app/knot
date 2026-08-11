#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
ARCHIVE_PATH="$BUILD_DIR/Knot.xcarchive"
STAGE_DIR="$BUILD_DIR/dmg-root"
DIST_DIR="$ROOT/dist"
TEAM_ID="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-KnotNotary}"

cd "$ROOT"

if ! security find-identity -v -p codesigning | grep -Fq "$IDENTITY"; then
    echo "Missing signing identity: $IDENTITY" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Missing or invalid notarytool profile: $NOTARY_PROFILE" >&2
    echo "Run scripts/configure-notarization.sh once, then retry." >&2
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodegen generate

xcodebuild archive \
    -project Knot.xcodeproj \
    -scheme Knot \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_USER_SCRIPT_SANDBOXING=NO

APP="$ARCHIVE_PATH/Products/Applications/Knot.app"
if [ ! -d "$APP" ]; then
    echo "Archive did not contain Knot.app" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST_DIR/Knot-$VERSION.dmg"

codesign --verify --deep --strict --verbose=2 "$APP"

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

shasum -a 256 "$DMG" > "$DMG.sha256"

echo "Release ready: $DMG"
echo "Checksum: $DMG.sha256"
