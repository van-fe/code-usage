#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/CodeUsage.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$PROJECT_DIR/.build-package"

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
cp "$PROJECT_DIR/README.md" "$CONTENTS_DIR/Resources/README.md"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS_DIR/Resources/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR/Assets/provider-codex.svg" "$CONTENTS_DIR/Resources/provider-codex.svg"
cp "$PROJECT_DIR/Assets/provider-cursor.svg" "$CONTENTS_DIR/Resources/provider-cursor.svg"
cp "$PROJECT_DIR/Assets/provider-claude.svg" "$CONTENTS_DIR/Resources/provider-claude.svg"
cp "$PROJECT_DIR/Assets/provider-kiro.svg" "$CONTENTS_DIR/Resources/provider-kiro.svg"
cp "$PROJECT_DIR/Assets/provider-qoder.svg" "$CONTENTS_DIR/Resources/provider-qoder.svg"
cp "$PROJECT_DIR/Assets/github-mark.svg" "$CONTENTS_DIR/Resources/github-mark.svg"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

plutil -create xml1 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleExecutable -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleName -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDisplayName -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon.icns "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string 0.8.1 "$CONTENTS_DIR/Info.plist" 2>/dev/null || plutil -insert CFBundleShortVersionString -string 0.8.1 "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string 30 "$CONTENTS_DIR/Info.plist" 2>/dev/null || plutil -insert CFBundleVersion -string 30 "$CONTENTS_DIR/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "$CONTENTS_DIR/Info.plist"
plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
