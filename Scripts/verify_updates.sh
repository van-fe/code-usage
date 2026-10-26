#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="${1:-$PROJECT_DIR/dist/CodeUsage.app}"
PLIST="$APP_PATH/Contents/Info.plist"
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"

for KEY in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAutomaticallyUpdate \
  SUScheduledCheckInterval SUScheduledImpatientCheckInterval \
  SUVerifyUpdateBeforeExtraction SURequireSignedFeed \
  SUSignedFeedFailureExpirationInterval SUEnableSystemProfiling; do
  EXPECTED=$(/usr/bin/plutil -extract "$KEY" raw -o - "$PROJECT_DIR/Config/Updates.plist")
  ACTUAL=$(/usr/bin/plutil -extract "$KEY" raw -o - "$PLIST")
  [[ "$ACTUAL" == "$EXPECTED" ]] || {
    echo "Incorrect updater configuration: $KEY" >&2
    exit 1
  }
done

for COMPONENT in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater \
  XPCServices/Installer.xpc/Contents/MacOS/Installer \
  XPCServices/Downloader.xpc/Contents/MacOS/Downloader; do
  [[ -x "$FRAMEWORK/Versions/B/$COMPONENT" ]] || {
    echo "Missing Sparkle component: $COMPONENT" >&2
    exit 1
  }
  for ARCH in arm64 x86_64; do
    /usr/bin/lipo "$FRAMEWORK/Versions/B/$COMPONENT" -verify_arch "$ARCH"
  done
done
[[ -L "$FRAMEWORK/Sparkle" && -L "$FRAMEWORK/Versions/Current" ]]
/usr/bin/otool -l "$APP_PATH/Contents/MacOS/CodeUsage" | \
  /usr/bin/grep -F '@executable_path/../Frameworks' >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
echo "Updater bundle verification passed"
