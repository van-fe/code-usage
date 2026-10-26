#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="${1:?Usage: verify_appcast.sh APP_PATH DMG_PATH APPCAST_PATH}"
DMG_PATH="${2:?Missing DMG path}"
APPCAST_PATH="${3:?Missing appcast path}"
TOOLS_DIR="${CODEUSAGE_SPARKLE_TOOLS_DIR:-$PROJECT_DIR/.build-package/artifacts/sparkle/Sparkle/bin}"
KEY_ACCOUNT="${CODEUSAGE_SPARKLE_KEY_ACCOUNT:-com.van-fe.CodeUsage.updates}"

# Authenticate the feed before interpreting its contents.
"$TOOLS_DIR/sign_update" --account "$KEY_ACCOUNT" --verify "$APPCAST_PATH"
NS='http://www.andymatuschak.org/xml-namespaces/sparkle'
ITEM='/rss/channel/item'
ENCLOSURE="$ITEM/enclosure"
[[ "$(/usr/bin/xmllint --xpath "count($ITEM)" "$APPCAST_PATH")" == "1" ]]
VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$APP_PATH/Contents/Info.plist")
[[ "$(/usr/bin/xmllint --xpath "string($ITEM/*[local-name()='version' and namespace-uri()='$NS'])" "$APPCAST_PATH")" == "$BUILD" ]]
[[ "$(/usr/bin/xmllint --xpath "string($ENCLOSURE/@url)" "$APPCAST_PATH")" == \
  "https://github.com/van-fe/code-usage/releases/download/v$VERSION/CodeUsage-$VERSION-macos-universal.dmg" ]]
[[ "$(/usr/bin/xmllint --xpath "string($ENCLOSURE/@length)" "$APPCAST_PATH")" == "$(/usr/bin/stat -f%z "$DMG_PATH")" ]]
SIGNATURE=$(/usr/bin/xmllint --xpath \
  "string($ENCLOSURE/@*[local-name()='edSignature' and namespace-uri()='$NS'])" "$APPCAST_PATH")
"$TOOLS_DIR/sign_update" --account "$KEY_ACCOUNT" --verify "$DMG_PATH" "$SIGNATURE"
echo "Signed update feed and archive verification passed"
