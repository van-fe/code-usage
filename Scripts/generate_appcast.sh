#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TOOLS_DIR="${CODEUSAGE_SPARKLE_TOOLS_DIR:-$PROJECT_DIR/.build-package/artifacts/sparkle/Sparkle/bin}"
KEY_ACCOUNT="${CODEUSAGE_SPARKLE_KEY_ACCOUNT:-com.van-fe.CodeUsage.updates}"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
APP_PATH="${CODEUSAGE_APP_PATH:-$PROJECT_DIR/dist-universal/CodeUsage.app}"
EXPECTED_KEY=$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$PROJECT_DIR/Config/Updates.plist")

if [[ ! -x "$TOOLS_DIR/generate_keys" || ! -x "$TOOLS_DIR/generate_appcast" ]]; then
  echo "Missing Sparkle tools. Run swift package --scratch-path .build-package resolve first." >&2
  exit 1
fi
# -p only reads the public key; it never creates, replaces, or exports a key.
PUBLIC_KEY=$("$TOOLS_DIR/generate_keys" --account "$KEY_ACCOUNT" -p)
if [[ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]]; then
  echo "Sparkle Keychain key does not match Config/Updates.plist. Do not generate a replacement key for an existing release channel." >&2
  exit 1
fi
if [[ "${1:-}" == "--validate-key" ]]; then
  echo "Update signing key matches the embedded public key"
  exit 0
fi
if (( $# != 0 )); then
  echo "Usage: generate_appcast.sh [--validate-key]" >&2
  exit 2
fi

VERSION=$(/usr/bin/plutil -extract version raw -o - "$PROJECT_DIR/version.json")
DMG_PATH="$PROJECT_DIR/dist/CodeUsage-$VERSION-macos-universal.dmg"
PLIST="$APP_PATH/Contents/Info.plist"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" == "$VERSION" ]]
[[ "$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$PLIST")" == "$PUBLIC_KEY" ]]
[[ "$(/usr/bin/plutil -extract SURequireSignedFeed raw -o - "$PLIST")" == "true" ]]
for ARCH in arm64 x86_64; do
  /usr/bin/lipo "$APP_PATH/Contents/MacOS/CodeUsage" -verify_arch "$ARCH"
done
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
/usr/bin/xcrun stapler validate "$APP_PATH"
/usr/sbin/spctl --assess --type execute "$APP_PATH"
/usr/bin/codesign --verify "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
/usr/sbin/spctl --assess --type open --context context:primary-signature "$DMG_PATH"

WORK_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageAppcast.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/archives" "$OUTPUT_DIR"
/usr/bin/ditto "$DMG_PATH" "$WORK_DIR/archives/${DMG_PATH:t}"

# Generate only from the final notarized DMG, after stapling has finished.
# Sparkle reads CFBundleVersion, minimum macOS and architectures from the app,
# signs both the archive and feed, and preserves their exact byte lengths.
"$TOOLS_DIR/generate_appcast" \
  --account "$KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/van-fe/code-usage/releases/download/v$VERSION/" \
  --link "https://github.com/van-fe/code-usage/releases/tag/v$VERSION" \
  --maximum-deltas 0 \
  --maximum-versions 1 \
  -o "$WORK_DIR/appcast.xml" \
  "$WORK_DIR/archives"
"$PROJECT_DIR/Scripts/verify_appcast.sh" "$APP_PATH" "$DMG_PATH" "$WORK_DIR/appcast.xml"
/usr/bin/ditto "$WORK_DIR/appcast.xml" "$OUTPUT_DIR/appcast.xml"
echo "$OUTPUT_DIR/appcast.xml"
