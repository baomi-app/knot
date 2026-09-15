#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="$ROOT/.build/SourcePackages"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-app.baomi.knot}"

if [ ! -x "$SPARKLE_BIN_DIR/generate_keys" ]; then
    xcodebuild -resolvePackageDependencies \
        -project "$ROOT/Knot.xcodeproj" \
        -scheme Knot \
        -clonedSourcePackagesDirPath "$PACKAGES_DIR"
fi

if [ ! -x "$SPARKLE_BIN_DIR/generate_keys" ]; then
    echo "Sparkle tools not found. Set SPARKLE_BIN_DIR to the Sparkle distribution's bin directory." >&2
    exit 1
fi

echo "Set up the developer-only update signing key (account: $SPARKLE_ACCOUNT)."
echo "The private key stays in your login Keychain; Knot users never need it."
"$SPARKLE_BIN_DIR/generate_keys" --account "$SPARKLE_ACCOUNT"
echo "Add the printed public key as SUPublicEDKey in project.yml, then run xcodegen generate."
echo "Keep a secure backup using Sparkle's documented key-export process; never commit a private key."
