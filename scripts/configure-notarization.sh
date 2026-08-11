#!/bin/bash
set -euo pipefail

PROFILE="${NOTARY_PROFILE:-KnotNotary}"
TEAM_ID="${DEVELOPMENT_TEAM:-HA3AN589MD}"

read -r -p "Apple ID: " APPLE_ID
read -r -s -p "App-specific password: " APP_PASSWORD
printf '\n'

xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD"

unset APP_PASSWORD
echo "Saved notarization credentials as Keychain profile: $PROFILE"
