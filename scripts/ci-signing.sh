#!/bin/bash
# Import credentials only on an ephemeral GitHub-hosted macOS release runner.
set -euo pipefail
set +x
umask 077

: "${RUNNER_TEMP:?}"
: "${GITHUB_WORKSPACE:?}"
: "${DEVELOPMENT_TEAM:?Missing DEVELOPMENT_TEAM secret}"
: "${APPLE_CERTIFICATE_P12_BASE64:?Missing APPLE_CERTIFICATE_P12_BASE64 secret}"
: "${APPLE_CERTIFICATE_PASSWORD:?Missing APPLE_CERTIFICATE_PASSWORD secret}"
: "${APPLE_ID:?Missing APPLE_ID secret}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Missing APPLE_APP_SPECIFIC_PASSWORD secret}"
: "${SPARKLE_PRIVATE_KEY:?Missing SPARKLE_PRIVATE_KEY secret}"

KEYCHAIN="$RUNNER_TEMP/knot-ci.keychain-db"
CERTIFICATE="$RUNNER_TEMP/knot-certificate.p12"
SPARKLE_KEY="$RUNNER_TEMP/knot-sparkle-key"
SPARKLE_BIN="$GITHUB_WORKSPACE/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
ACCOUNT="${SPARKLE_ACCOUNT:-app.baomi.knot}"
PASSWORD="$(openssl rand -hex 32)"
printf '::add-mask::%s\n' "$PASSWORD"
trap 'rm -f "$CERTIFICATE" "$SPARKLE_KEY"' EXIT

printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERTIFICATE"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 7200 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
security default-keychain -d user -s "$KEYCHAIN"
security import "$CERTIFICATE" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN"

xcrun notarytool store-credentials "${NOTARY_PROFILE:-KnotNotaryCI}" \
  --apple-id "$APPLE_ID" --team-id "$DEVELOPMENT_TEAM" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" --keychain "$KEYCHAIN"

# Import the existing Sparkle export, never generate a replacement signing key.
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$SPARKLE_KEY"
"$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -f "$SPARKLE_KEY"
# Allow both Sparkle tools to read this item without an interactive ACL prompt.
security add-generic-password -U -a "$ACCOUNT" -s 'https://sparkle-project.org' \
  -T "$SPARKLE_BIN/generate_keys" -T "$SPARKLE_BIN/generate_appcast" "$KEYCHAIN"
