#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ] || [[ ! "$2" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Usage: scripts/verify-app-signing.sh PATH_TO_KNOT_APP TEAM_ID" >&2
    exit 1
fi

APP="$1"
TEAM_ID="$2"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
COMPONENTS=(
    "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    "$SPARKLE/Versions/B/Autoupdate"
    "$SPARKLE/Versions/B/Updater.app"
    "$SPARKLE"
    "$APP"
)

for component in "${COMPONENTS[@]}"; do
    [ -e "$component" ] || { echo "Missing signed component: $component" >&2; exit 1; }
    codesign --verify --strict --all-architectures --verbose=2 "$component"
    metadata=$(codesign --display --verbose=4 "$component" 2>&1)
    component_team=$(printf '%s\n' "$metadata" | awk -F= '$1 == "TeamIdentifier" { print $2 }')
    if [ "$component_team" != "$TEAM_ID" ] || [[ "$metadata" != *"Authority=Developer ID Application:"* ]]; then
        echo "Expected a Developer ID signature from the app's team on: $component" >&2
        exit 1
    fi
    code_directory=$(printf '%s\n' "$metadata" | awk '/^CodeDirectory / { print }')
    if [[ "$code_directory" != *"(runtime)"* && "$code_directory" != *"(runtime,"* &&
          "$code_directory" != *",runtime)"* && "$code_directory" != *",runtime,"* ]]; then
        echo "Hardened Runtime is not enabled on: $component" >&2
        exit 1
    fi

    # Newer macOS releases default to a human-readable representation.
    # Request XML explicitly so validation does not depend on that default.
    entitlements=$(codesign --display --entitlements - --xml "$component" 2>/dev/null)
    if [ -n "$entitlements" ]; then
        permits_debugging=$(printf '%s\n' "$entitlements" | xmllint --xpath \
            'boolean(//key[text()="com.apple.security.get-task-allow"]/following-sibling::*[1][self::true])' -)
        if [ "$permits_debugging" = "true" ]; then
            echo "Distribution component still permits debugging: $component" >&2
            exit 1
        fi
    fi
done

# --deep is useful for verification, not signing. Signing is handled by
# Xcode's export step with each nested component's own entitlements.
codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
echo "Verified Knot and all Sparkle components with the expected Developer ID team."
