#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_SVG="$PROJECT_DIR/Assets/AppIcon.svg"
SOURCE_PNG="$PROJECT_DIR/Assets/AppIcon-1024.png"
WORK_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageIcon.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
MODULE_CACHE_DIR="$PROJECT_DIR/.cache/icon-modulecache"
mkdir -p "$ICONSET_DIR"
mkdir -p "$MODULE_CACHE_DIR"

SWIFT_ARGS=(-module-cache-path "$MODULE_CACHE_DIR")
if [[ -n "${CODEUSAGE_SDK_PATH:-}" ]]; then
  SWIFT_ARGS+=(-sdk "$CODEUSAGE_SDK_PATH")
fi
swift "${SWIFT_ARGS[@]}" "$PROJECT_DIR/Scripts/generate_app_icon.swift" \
  "$SOURCE_SVG" \
  "$SOURCE_PNG"

while read -r filename pixels; do
  sips -z "$pixels" "$pixels" "$SOURCE_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
done <<'SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
SIZES

swift "${SWIFT_ARGS[@]}" "$PROJECT_DIR/Scripts/package_icns.swift" \
  "$PROJECT_DIR/Assets/AppIcon.icns" \
  icp4 "$ICONSET_DIR/icon_16x16.png" \
  icp5 "$ICONSET_DIR/icon_32x32.png" \
  icp6 "$ICONSET_DIR/icon_32x32@2x.png" \
  ic07 "$ICONSET_DIR/icon_128x128.png" \
  ic08 "$ICONSET_DIR/icon_256x256.png" \
  ic09 "$ICONSET_DIR/icon_512x512.png" \
  ic10 "$ICONSET_DIR/icon_512x512@2x.png"
echo "$PROJECT_DIR/Assets/AppIcon.icns"
