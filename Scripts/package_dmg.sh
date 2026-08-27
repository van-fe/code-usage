#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_SOURCE="${CODEUSAGE_APP_PATH:-$PROJECT_DIR/dist-universal/CodeUsage.app}"
BACKGROUND_SOURCE="$PROJECT_DIR/Assets/dmg-background-final@2x.png"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
PLIST="$APP_SOURCE/Contents/Info.plist"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Missing app bundle: $APP_SOURCE" >&2
  exit 1
fi
if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
  echo "Missing DMG background: $BACKGROUND_SOURCE" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
VOLUME_NAME="CodeUsage 安装器"
OUTPUT_DMG="$OUTPUT_DIR/CodeUsage-${VERSION}-macos-universal.dmg"
WORK_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageDMG.XXXXXX")
STAGING_DIR="$WORK_DIR/root"
RW_DMG="$WORK_DIR/CodeUsage-rw.dmg"
DEVICE=""
VERIFY_DEVICE=""
VERIFY_MOUNT_POINT="$WORK_DIR/verify"

cleanup() {
  if [[ -n "$VERIFY_DEVICE" ]]; then
    /usr/bin/hdiutil detach "$VERIFY_DEVICE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$DEVICE" ]]; then
    /usr/bin/hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/.background" "$OUTPUT_DIR"
/usr/bin/ditto "$APP_SOURCE" "$STAGING_DIR/CodeUsage.app"
cp "$BACKGROUND_SOURCE" "$STAGING_DIR/.background/installer-background@2x.png"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
ln -s /Applications "$STAGING_DIR/应用程序"

/usr/bin/hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov "$RW_DMG" >/dev/null

ATTACH_OUTPUT=$(/usr/bin/hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
DEVICE=$(echo "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { $1=$2=""; sub(/^  */, ""); print; exit }')
if [[ -z "$DEVICE" || -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Could not mount writable DMG" >&2
  exit 1
fi

/usr/bin/xcrun SetFile -a V "$MOUNT_POINT/.background"
/usr/bin/xcrun SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"
/usr/bin/xcrun SetFile -a C "$MOUNT_POINT"

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  -- Resolve the exact mounted folder. Addressing the disk only by its display
  -- name can target an older same-name DMG that is still mounted.
  set targetFolder to folder (POSIX file "$MOUNT_POINT" as alias)
  open targetFolder

  set targetWindow to missing value
  repeat 20 times
    try
      set targetWindow to container window of targetFolder
      exit repeat
    on error
      delay 0.25
    end try
  end repeat
  if targetWindow is missing value then error "Could not open the writable DMG window"

  set current view of targetWindow to icon view
  set toolbar visible of targetWindow to false
  set statusbar visible of targetWindow to false
  set bounds of targetWindow to {120, 100, 900, 630}

  set viewOptions to icon view options of targetWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 128
  set text size of viewOptions to 14
  set label position of viewOptions to bottom
  set shows item info of viewOptions to false
  set shows icon preview of viewOptions to true
  set backgroundImage to POSIX file "$MOUNT_POINT/.background/installer-background@2x.png" as alias
  set background picture of viewOptions to backgroundImage

  set position of item "CodeUsage.app" of targetFolder to {204, 337}
  set position of item "应用程序" of targetFolder to {573, 337}
  update targetFolder without registering applications
  delay 2
  close targetWindow
  delay 3
end tell
APPLESCRIPT

/bin/sync

# Finder persists icon positions, window bounds, and the background alias in
# .DS_Store asynchronously. Never publish a DMG until that exact mounted
# volume contains a non-empty record for our background.
for attempt in {1..60}; do
  if [[ -s "$MOUNT_POINT/.DS_Store" ]] && \
     /usr/bin/strings -a "$MOUNT_POINT/.DS_Store" | \
       /usr/bin/grep -Fq "installer-background@2x.png"; then
    break
  fi
  sleep 0.25
done

if [[ ! -s "$MOUNT_POINT/.DS_Store" ]]; then
  echo "Finder did not write .DS_Store to the mounted DMG: $MOUNT_POINT" >&2
  exit 1
fi
if ! /usr/bin/strings -a "$MOUNT_POINT/.DS_Store" | \
     /usr/bin/grep -Fq "installer-background@2x.png"; then
  echo "Finder .DS_Store is missing the DMG background record" >&2
  exit 1
fi

/bin/sync
sleep 1
/usr/bin/hdiutil detach "$DEVICE" >/dev/null
DEVICE=""

/usr/bin/hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$OUTPUT_DMG" >/dev/null
/usr/bin/hdiutil verify "$OUTPUT_DMG" >/dev/null

# Re-open the final read-only image and validate the files that recipients
# actually receive, rather than trusting only the writable staging volume.
mkdir -p "$VERIFY_MOUNT_POINT"
VERIFY_ATTACH_OUTPUT=$(/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$VERIFY_MOUNT_POINT" \
  "$OUTPUT_DMG")
VERIFY_DEVICE=$(echo "$VERIFY_ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')
if [[ -z "$VERIFY_DEVICE" || ! -d "$VERIFY_MOUNT_POINT" ]]; then
  echo "Could not mount the final DMG for verification" >&2
  exit 1
fi

if [[ ! -s "$VERIFY_MOUNT_POINT/.DS_Store" ]]; then
  echo "Final DMG is missing .DS_Store" >&2
  exit 1
fi
if [[ ! -f "$VERIFY_MOUNT_POINT/.background/installer-background@2x.png" ]]; then
  echo "Final DMG is missing its background image" >&2
  exit 1
fi
if ! /usr/bin/strings -a "$VERIFY_MOUNT_POINT/.DS_Store" | \
     /usr/bin/grep -Fq "installer-background@2x.png"; then
  echo "Final DMG .DS_Store is missing the background record" >&2
  exit 1
fi
if [[ ! -d "$VERIFY_MOUNT_POINT/CodeUsage.app" ]] || \
   [[ "$(readlink "$VERIFY_MOUNT_POINT/应用程序")" != "/Applications" ]]; then
  echo "Final DMG payload verification failed" >&2
  exit 1
fi

/usr/bin/hdiutil detach "$VERIFY_DEVICE" >/dev/null
VERIFY_DEVICE=""

echo "$OUTPUT_DMG"
