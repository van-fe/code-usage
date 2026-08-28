#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/CodeUsage.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$PROJECT_DIR/.build-package"
VERSION_FILE="$PROJECT_DIR/version.json"
MODULE_CACHE_DIR="${CLANG_MODULE_CACHE_PATH:-$PROJECT_DIR/.cache/clang-module-cache}"

mkdir -p "$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi

APP_VERSION="${CODEUSAGE_VERSION:-$(/usr/bin/plutil -extract version raw -o - "$VERSION_FILE")}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid semantic version: $APP_VERSION" >&2
  exit 1
fi

VERSION_PARTS=("${(@s:.:)APP_VERSION}")
# Build 31 was the last integer-only build. Offset the SemVer major by 32 so
# the derived build remains monotonic without committing a CI counter
# (0.9.0 -> 32.9.0, 1.0.0 -> 33.0.0).
DEFAULT_BUILD_NUMBER="$((VERSION_PARTS[1] + 32)).${VERSION_PARTS[2]}.${VERSION_PARTS[3]}"
BUILD_NUMBER="${CODEUSAGE_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Invalid build number: $BUILD_NUMBER" >&2
  exit 1
fi

BUNDLE_IDENTIFIER="${CODEUSAGE_BUNDLE_IDENTIFIER:-com.van-fe.CodeUsage}"
if [[ -z "$BUNDLE_IDENTIFIER" ]]; then
  echo "Bundle identifier cannot be empty" >&2
  exit 1
fi

BUILD_ARGS=(
  --disable-sandbox
  --package-path "$PROJECT_DIR"
  --scratch-path "$BUILD_DIR"
  -c release
)
if [[ -n "${CODEUSAGE_SDK_PATH:-}" ]]; then
  BUILD_ARGS+=(--sdk "$CODEUSAGE_SDK_PATH")
fi
swift build "${BUILD_ARGS[@]}"
mkdir -p "$PROJECT_DIR/dist"
# Recreate the generated bundle so renamed or removed resources cannot survive
# from an earlier package run.
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/release/CodeUsage" "$CONTENTS_DIR/MacOS/CodeUsage"
cp "$PROJECT_DIR/LICENSE" "$CONTENTS_DIR/Resources/LICENSE"
cp "$PROJECT_DIR/README.md" "$CONTENTS_DIR/Resources/README.md"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS_DIR/Resources/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR/Assets/provider-codex.svg" "$CONTENTS_DIR/Resources/provider-codex.svg"
cp "$PROJECT_DIR/Assets/provider-cursor.svg" "$CONTENTS_DIR/Resources/provider-cursor.svg"
cp "$PROJECT_DIR/Assets/provider-claude.svg" "$CONTENTS_DIR/Resources/provider-claude.svg"
cp "$PROJECT_DIR/Assets/provider-kiro.svg" "$CONTENTS_DIR/Resources/provider-kiro.svg"
cp "$PROJECT_DIR/Assets/provider-qoder.svg" "$CONTENTS_DIR/Resources/provider-qoder.svg"
cp "$PROJECT_DIR/Assets/github-mark.svg" "$CONTENTS_DIR/Resources/github-mark.svg"
cp "$PROJECT_DIR/Assets/statusbar-logo.svg" "$CONTENTS_DIR/Resources/statusbar-logo.svg"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

plutil -create xml1 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleExecutable -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleName -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDisplayName -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon.icns "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "$CONTENTS_DIR/Info.plist"
plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
