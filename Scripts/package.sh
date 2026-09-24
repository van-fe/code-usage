#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/CodeUsage.app"
CONTENTS_DIR="$APP_DIR/Contents"
WIDGET_DIR="$CONTENTS_DIR/PlugIns/CodeUsageWidgets.appex"
WIDGET_CONTENTS_DIR="$WIDGET_DIR/Contents"
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

LOCAL_WIDGET_FALLBACK="${CODEUSAGE_LOCAL_WIDGET_FALLBACK:-1}"
if [[ "$LOCAL_WIDGET_FALLBACK" != "0" && "$LOCAL_WIDGET_FALLBACK" != "1" ]]; then
  echo "CODEUSAGE_LOCAL_WIDGET_FALLBACK must be 0 or 1" >&2
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
mkdir -p \
  "$CONTENTS_DIR/MacOS" \
  "$CONTENTS_DIR/Resources" \
  "$WIDGET_CONTENTS_DIR/MacOS" \
  "$WIDGET_CONTENTS_DIR/Resources"
cp "$BUILD_DIR/release/CodeUsage" "$CONTENTS_DIR/MacOS/CodeUsage"
cp "$BUILD_DIR/release/CodeUsageWidgets" \
  "$WIDGET_CONTENTS_DIR/MacOS/CodeUsageWidgets"
"$PROJECT_DIR/Scripts/verify_widget_entrypoint.sh" \
  "$WIDGET_CONTENTS_DIR/MacOS/CodeUsageWidgets"
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
WIDGET_ICON_ASSETS=(
  provider-codex.svg
  provider-cursor.svg
  provider-claude.svg
  provider-kiro.svg
  provider-qoder.svg
  statusbar-logo.svg
)
for WIDGET_ICON_ASSET in "${WIDGET_ICON_ASSETS[@]}"; do
  cp "$PROJECT_DIR/Assets/$WIDGET_ICON_ASSET" \
    "$WIDGET_CONTENTS_DIR/Resources/$WIDGET_ICON_ASSET"
done
for LOCALIZATION_DIR in "$PROJECT_DIR/Sources/CodeUsage/Resources"/*.lproj; do
  /usr/bin/ditto "$LOCALIZATION_DIR" \
    "$CONTENTS_DIR/Resources/${LOCALIZATION_DIR:t}"
  /usr/bin/ditto "$LOCALIZATION_DIR" \
    "$WIDGET_CONTENTS_DIR/Resources/${LOCALIZATION_DIR:t}"
done

# SwiftPM does not run Xcode's App Intents metadata extraction step. WidgetKit
# needs this bundle to expose the native Edit Widget metric picker.
WIDGET_CONST_PROTOCOLS_FILE="$BUILD_DIR/CodeUsageWidgets_const_extract_protocols.json"
WIDGET_CONST_VALUES_FILE="$BUILD_DIR/CodeUsageWidgets.swiftconstvalues"
WIDGET_CONST_VALUES_LIST="$BUILD_DIR/CodeUsageWidgets.constvalues.list"
WIDGET_SOURCE_FILES_LIST="$BUILD_DIR/CodeUsageWidgets.sources.list"
WIDGET_METADATA_OBJECT="$BUILD_DIR/CodeUsageWidgets.o"
SELECTED_DEVELOPER_PATH="$(xcode-select -p)"
SELECTED_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SELECTED_XCODE_BUILD_VERSION="$(xcodebuild -version | /usr/bin/awk '/Build version/ { print $3 }')"
NATIVE_BUILD_ARCH="$(uname -m)"
WIDGET_TARGET_TRIPLE="$NATIVE_BUILD_ARCH-apple-macosx14.0"

print -r -- '["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider"]' \
  > "$WIDGET_CONST_PROTOCOLS_FILE"
print -r -- "$WIDGET_CONST_VALUES_FILE" > "$WIDGET_CONST_VALUES_LIST"
print -r -- "$PROJECT_DIR/Sources/CodeUsageWidgets/CodeUsageWidgets.swift" \
  > "$WIDGET_SOURCE_FILES_LIST"

xcrun --sdk macosx swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -parse-as-library \
  -module-name CodeUsageWidgets \
  -swift-version 5 \
  -target "$WIDGET_TARGET_TRIPLE" \
  -sdk "$SELECTED_SDK_PATH" \
  -I "$BUILD_DIR/release" \
  -I "$BUILD_DIR/$NATIVE_BUILD_ARCH-apple-macosx/release/Modules" \
  -emit-object \
  -emit-const-values \
  -Xfrontend -const-gather-protocols-file \
  -Xfrontend "$WIDGET_CONST_PROTOCOLS_FILE" \
  -emit-const-values-path "$WIDGET_CONST_VALUES_FILE" \
  "$PROJECT_DIR/Sources/CodeUsageWidgets/CodeUsageWidgets.swift" \
  -o "$WIDGET_METADATA_OBJECT"

xcrun appintentsmetadataprocessor \
  --output "$WIDGET_CONTENTS_DIR/Resources" \
  --toolchain-dir "$SELECTED_DEVELOPER_PATH/Toolchains/XcodeDefault.xctoolchain" \
  --module-name CodeUsageWidgets \
  --sdk-root "$SELECTED_SDK_PATH" \
  --xcode-version "$SELECTED_XCODE_BUILD_VERSION" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple "$WIDGET_TARGET_TRIPLE" \
  --source-file-list "$WIDGET_SOURCE_FILES_LIST" \
  --swift-const-vals-list "$WIDGET_CONST_VALUES_LIST" \
  --force

test -f "$WIDGET_CONTENTS_DIR/Resources/Metadata.appintents/extract.actionsdata"
WIDGET_APP_INTENTS_DATA="$WIDGET_CONTENTS_DIR/Resources/Metadata.appintents/extract.actionsdata"
test "$(plutil -extract actions.UsageWidgetConfigurationIntent.identifier raw -o - \
  "$WIDGET_APP_INTENTS_DATA")" = "UsageWidgetConfigurationIntent"
test "$(plutil -extract actions.UsageWidgetConfigurationIntent.parameters.0.name raw -o - \
  "$WIDGET_APP_INTENTS_DATA")" = "firstMetricID"

plutil -create xml1 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleExecutable -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleName -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDisplayName -string CodeUsage "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' \
  "$CONTENTS_DIR/Info.plist"
plutil -insert DTPlatformName -string macosx "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleLocalizations -json \
  '["zh-Hans","zh-Hant","en","fr","de","ja","ko"]' \
  "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleAllowMixedLocalizations -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon.icns "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
plutil -insert LSMinimumSystemVersion -string 13.0 "$CONTENTS_DIR/Info.plist"
plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleURLTypes -json \
  '[{"CFBundleURLName":"com.van-fe.CodeUsage","CFBundleURLSchemes":["codeusage"]}]' \
  "$CONTENTS_DIR/Info.plist"
if [[ "$LOCAL_WIDGET_FALLBACK" == "1" ]]; then
  plutil -insert CodeUsageLocalWidgetSnapshot -bool true \
    "$CONTENTS_DIR/Info.plist"
fi

plutil -create xml1 "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleExecutable -string CodeUsageWidgets \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string "$BUNDLE_IDENTIFIER.widgets" \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleName -string "CodeUsage Widgets" \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDisplayName -string CodeUsage \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert DTPlatformName -string macosx \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleLocalizations -json \
  '["zh-Hans","zh-Hant","en","fr","de","ja","ko"]' \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleAllowMixedLocalizations -bool true \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundlePackageType -string XPC! \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 \
  "$WIDGET_CONTENTS_DIR/Info.plist"
plutil -insert NSExtension -json \
  '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' \
  "$WIDGET_CONTENTS_DIR/Info.plist"
if [[ "$LOCAL_WIDGET_FALLBACK" == "1" ]]; then
  plutil -insert CodeUsageLocalWidgetSnapshot -bool true \
    "$WIDGET_CONTENTS_DIR/Info.plist"
fi

codesign \
  --force \
  --sign - \
  --entitlements "$PROJECT_DIR/Config/CodeUsageWidgetsLocal.entitlements" \
  "$WIDGET_DIR"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
