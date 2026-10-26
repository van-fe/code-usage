#!/bin/zsh
set -euo pipefail

APP_PATH="${1:?Usage: sign_sparkle.sh APP_PATH SIGNING_IDENTITY}"
SIGNING_IDENTITY="${2:?Missing signing identity}"
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

# Sign inside out, without --deep or the host app's CloudKit entitlements.
# Keep the Downloader's own entitlements, as required by Sparkle.
for COMPONENT in XPCServices/Installer.xpc Autoupdate Updater.app; do
  /usr/bin/codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/$COMPONENT"
done
/usr/bin/codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements \
  "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
/usr/bin/codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
/usr/bin/codesign --verify --deep --strict "$FRAMEWORK"
