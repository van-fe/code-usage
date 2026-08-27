#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
APP_PLIST="${CODEUSAGE_APP_PLIST:-$PROJECT_DIR/dist-universal/CodeUsage.app/Contents/Info.plist}"

if [[ ! -f "$APP_PLIST" ]]; then
  echo "Missing version source: $APP_PLIST" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")
OUTPUT_ZIP="$OUTPUT_DIR/CodeUsage-${VERSION}-source.zip"
WORK_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageSource.XXXXXX")
STAGING_DIR="$WORK_DIR/staging"
TEMP_ZIP="$WORK_DIR/CodeUsage-${VERSION}-source.zip"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/Assets" "$OUTPUT_DIR"

for file in \
  LICENSE \
  Package.swift \
  README.md \
  RELEASING.md \
  THIRD_PARTY_NOTICES.md \
  version.json \
  release-please-config.json \
  .release-please-manifest.json; do
  /usr/bin/ditto "$PROJECT_DIR/$file" "$STAGING_DIR/$file"
done

/usr/bin/ditto "$PROJECT_DIR/Sources" "$STAGING_DIR/Sources"
/usr/bin/ditto "$PROJECT_DIR/Scripts" "$STAGING_DIR/Scripts"
/usr/bin/ditto "$PROJECT_DIR/.github" "$STAGING_DIR/.github"

for asset in \
  AppIcon.svg \
  AppIcon-1024.png \
  AppIcon.icns \
  provider-codex.svg \
  provider-cursor.svg \
  provider-claude.svg \
  provider-kiro.svg \
  provider-qoder.svg \
  github-mark.svg \
  statusbar-logo.svg \
  dmg-background-imagegen-v1.png \
  dmg-background-final.png \
  dmg-background-final@2x.png; do
  /usr/bin/ditto "$PROJECT_DIR/Assets/$asset" "$STAGING_DIR/Assets/$asset"
done

pushd "$STAGING_DIR" >/dev/null
/usr/bin/zip -qry -X "$TEMP_ZIP" \
  LICENSE \
  Package.swift \
  README.md \
  RELEASING.md \
  THIRD_PARTY_NOTICES.md \
  version.json \
  release-please-config.json \
  .release-please-manifest.json \
  .github \
  Sources \
  Assets \
  Scripts
popd >/dev/null

/usr/bin/unzip -tqq "$TEMP_ZIP"
/bin/mv -f "$TEMP_ZIP" "$OUTPUT_ZIP"

echo "$OUTPUT_ZIP"
