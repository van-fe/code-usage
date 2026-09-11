#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION_FILE="$PROJECT_DIR/version.json"
UNIVERSAL_APP="$PROJECT_DIR/dist-universal/CodeUsage.app"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
UPLOAD_TO_GITHUB=0
VALIDATE_CONFIG_ONLY=0

cd "$PROJECT_DIR"

usage() {
  echo "Usage: ./Scripts/release_local.sh [--upload] [--validate-config]" >&2
  echo "" >&2
  echo "Required environment variables:" >&2
  echo "  CODEUSAGE_SIGNING_IDENTITY     Developer ID Application identity" >&2
  echo "  CODEUSAGE_BUNDLE_IDENTIFIER    Stable reverse-DNS bundle identifier" >&2
  echo "  CODEUSAGE_NOTARY_PROFILE       notarytool Keychain profile" >&2
  echo "  CODEUSAGE_PROVISIONING_PROFILE Developer ID provisioning profile" >&2
  echo "  CODEUSAGE_WIDGET_PROVISIONING_PROFILE Widget Developer ID provisioning profile" >&2
  echo "" >&2
  echo "Optional environment variables:" >&2
  echo "  CODEUSAGE_ENTITLEMENTS         Entitlements plist override" >&2
  echo "  CODEUSAGE_WIDGET_ENTITLEMENTS  Widget entitlements plist override" >&2
}

for argument in "$@"; do
  case "$argument" in
    --upload) UPLOAD_TO_GITHUB=1 ;;
    --validate-config) VALIDATE_CONFIG_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $argument" >&2; usage; exit 2 ;;
  esac
done

SIGNING_IDENTITY="${CODEUSAGE_SIGNING_IDENTITY:-}"
BUNDLE_IDENTIFIER="${CODEUSAGE_BUNDLE_IDENTIFIER:-}"
NOTARY_PROFILE="${CODEUSAGE_NOTARY_PROFILE:-}"
PROVISIONING_PROFILE="${CODEUSAGE_PROVISIONING_PROFILE:-}"
WIDGET_PROVISIONING_PROFILE="${CODEUSAGE_WIDGET_PROVISIONING_PROFILE:-}"
ENTITLEMENTS="${CODEUSAGE_ENTITLEMENTS:-$PROJECT_DIR/Config/CodeUsage.entitlements}"
WIDGET_ENTITLEMENTS="${CODEUSAGE_WIDGET_ENTITLEMENTS:-$PROJECT_DIR/Config/CodeUsageWidgets.entitlements}"
ICLOUD_CONTAINER="iCloud.com.van-fe.CodeUsage"
APP_GROUP="group.com.van-fe.CodeUsage.shared"
WIDGET_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER.widgets"

if [[ -z "$SIGNING_IDENTITY" || -z "$BUNDLE_IDENTIFIER" || \
      -z "$NOTARY_PROFILE" || -z "$PROVISIONING_PROFILE" || \
      -z "$WIDGET_PROVISIONING_PROFILE" ]]; then
  usage
  exit 2
fi
if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
  echo "Missing provisioning profile: $PROVISIONING_PROFILE" >&2
  exit 1
fi
if [[ ! -f "$WIDGET_PROVISIONING_PROFILE" ]]; then
  echo "Missing widget provisioning profile: $WIDGET_PROVISIONING_PROFILE" >&2
  exit 1
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Missing entitlements file: $ENTITLEMENTS" >&2
  exit 1
fi
if [[ ! -f "$WIDGET_ENTITLEMENTS" ]]; then
  echo "Missing widget entitlements file: $WIDGET_ENTITLEMENTS" >&2
  exit 1
fi
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi
if [[ "$VALIDATE_CONFIG_ONLY" != "1" && \
      "${CODEUSAGE_ALLOW_DIRTY_RELEASE:-0}" != "1" ]] && \
   [[ -n "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal)" ]]; then
  echo "Refusing a signed release from a dirty working tree." >&2
  echo "Commit or stash changes, or set CODEUSAGE_ALLOW_DIRTY_RELEASE=1 intentionally." >&2
  exit 1
fi

VERSION=$(/usr/bin/plutil -extract version raw -o - "$VERSION_FILE")
TAG="v$VERSION"
ZIP_ROOT="$PROJECT_DIR/dist-universal/CodeUsage-$VERSION"
OUTPUT_ZIP="$OUTPUT_DIR/CodeUsage-$VERSION-macos-universal.zip"
OUTPUT_DMG="$PROJECT_DIR/dist/CodeUsage-$VERSION-macos-universal.dmg"
WORK_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageRelease.XXXXXX")
NOTARY_ZIP="$WORK_DIR/CodeUsage-$VERSION-notarization.zip"
PROFILE_PLIST="$WORK_DIR/provisioning-profile.plist"
WIDGET_PROFILE_PLIST="$WORK_DIR/widget-provisioning-profile.plist"
SIGNED_ENTITLEMENTS="$WORK_DIR/signed-entitlements.txt"
SIGNED_WIDGET_ENTITLEMENTS="$WORK_DIR/signed-widget-entitlements.txt"
ZIP_VERIFY_DIR="$WORK_DIR/zip-verify"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

/usr/bin/security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST" 2>/dev/null || \
  /usr/bin/openssl smime -verify -noverify -inform der \
    -in "$PROVISIONING_PROFILE" -out "$PROFILE_PLIST" 2>/dev/null
PROFILE_APP_ID=$(/usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")
if [[ "$PROFILE_APP_ID" != *".$BUNDLE_IDENTIFIER" ]]; then
  echo "Provisioning profile App ID does not match $BUNDLE_IDENTIFIER: $PROFILE_APP_ID" >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' \
  "$PROFILE_PLIST" | /usr/bin/grep -Fq "$ICLOUD_CONTAINER"; then
  echo "Provisioning profile does not contain $ICLOUD_CONTAINER" >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.security.application-groups' \
  "$PROFILE_PLIST" | /usr/bin/grep -Fq "$APP_GROUP"; then
  echo "Provisioning profile does not contain App Group $APP_GROUP" >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.developer.icloud-services' \
  "$PROFILE_PLIST" | /usr/bin/grep -Eq 'CloudKit|\\*'; then
  echo "Provisioning profile does not enable CloudKit" >&2
  exit 1
fi
PROFILE_ENVIRONMENT=$(/usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.developer.icloud-container-environment' \
  "$PROFILE_PLIST")
if [[ "$PROFILE_ENVIRONMENT" != "Production" ]]; then
  echo "Developer ID release profile must use the Production iCloud environment." >&2
  exit 1
fi

/usr/bin/security cms -D -i "$WIDGET_PROVISIONING_PROFILE" \
  > "$WIDGET_PROFILE_PLIST" 2>/dev/null || \
  /usr/bin/openssl smime -verify -noverify -inform der \
    -in "$WIDGET_PROVISIONING_PROFILE" -out "$WIDGET_PROFILE_PLIST" 2>/dev/null
WIDGET_PROFILE_APP_ID=$(/usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.application-identifier' \
  "$WIDGET_PROFILE_PLIST")
if [[ "$WIDGET_PROFILE_APP_ID" != *".$WIDGET_BUNDLE_IDENTIFIER" ]]; then
  echo "Widget provisioning profile App ID does not match $WIDGET_BUNDLE_IDENTIFIER: $WIDGET_PROFILE_APP_ID" >&2
  exit 1
fi
if ! /usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.security.application-groups' \
  "$WIDGET_PROFILE_PLIST" | /usr/bin/grep -Fq "$APP_GROUP"; then
  echo "Widget provisioning profile does not contain App Group $APP_GROUP" >&2
  exit 1
fi
if ! /usr/bin/security find-identity -v -p codesigning | \
  /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
  echo "Signing identity is not available in the current Keychain: $SIGNING_IDENTITY" >&2
  exit 1
fi
if [[ "$VALIDATE_CONFIG_ONLY" == "1" ]]; then
  echo "Developer ID, CloudKit, App Group, and widget provisioning profile configuration is valid."
  exit 0
fi

if [[ "$UPLOAD_TO_GITHUB" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is required for --upload" >&2
    exit 1
  fi
  if ! git -C "$PROJECT_DIR" tag --points-at HEAD | /usr/bin/grep -Fxq "$TAG"; then
    echo "HEAD must point at release tag $TAG before --upload" >&2
    exit 1
  fi
  gh release view "$TAG" >/dev/null
fi

CODEUSAGE_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
CODEUSAGE_LOCAL_WIDGET_FALLBACK=0 \
  "$PROJECT_DIR/Scripts/package_universal.sh"

/usr/bin/ditto "$PROVISIONING_PROFILE" \
  "$UNIVERSAL_APP/Contents/embedded.provisionprofile"
WIDGET_APP="$UNIVERSAL_APP/Contents/PlugIns/CodeUsageWidgets.appex"
if [[ ! -d "$WIDGET_APP" ]]; then
  echo "Packaged app is missing its widget extension: $WIDGET_APP" >&2
  exit 1
fi
/usr/bin/ditto "$WIDGET_PROVISIONING_PROFILE" \
  "$WIDGET_APP/Contents/embedded.provisionprofile"

# Downloaded provisioning profiles can carry quarantine and provenance
# metadata that should not be part of a signed release bundle.
/usr/bin/xattr -cr "$UNIVERSAL_APP"

/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$WIDGET_ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$WIDGET_APP"
/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$UNIVERSAL_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$UNIVERSAL_APP"
/usr/bin/codesign -d --entitlements - "$UNIVERSAL_APP" \
  > "$SIGNED_ENTITLEMENTS" 2>/dev/null
if ! /usr/bin/grep -Fq "$ICLOUD_CONTAINER" "$SIGNED_ENTITLEMENTS"; then
  echo "Signed app is missing its iCloud container entitlement" >&2
  exit 1
fi
if ! /usr/bin/grep -Fq "$APP_GROUP" "$SIGNED_ENTITLEMENTS"; then
  echo "Signed app is missing its App Group entitlement" >&2
  exit 1
fi
/usr/bin/codesign -d --entitlements - "$WIDGET_APP" \
  > "$SIGNED_WIDGET_ENTITLEMENTS" 2>/dev/null
if ! /usr/bin/grep -Fq "$APP_GROUP" "$SIGNED_WIDGET_ENTITLEMENTS"; then
  echo "Signed widget is missing its App Group entitlement" >&2
  exit 1
fi

# Notarize and staple the app before placing it in the final ZIP and DMG.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$UNIVERSAL_APP" "$NOTARY_ZIP"
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
/usr/bin/xcrun stapler staple "$UNIVERSAL_APP"
/usr/bin/xcrun stapler validate "$UNIVERSAL_APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$UNIVERSAL_APP"

# Recreate the ZIP so it contains the signed and stapled app rather than the
# ad-hoc app produced during the universal build.
rm -rf "$ZIP_ROOT"
mkdir -p "$ZIP_ROOT" "$OUTPUT_DIR"
/usr/bin/ditto "$UNIVERSAL_APP" "$ZIP_ROOT/CodeUsage.app"
ln -s /Applications "$ZIP_ROOT/Applications"
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$UNIVERSAL_APP/Contents/Info.plist")
INSTALL_GUIDE=(
  "CodeUsage $VERSION（build $BUILD）"
  ""
  "系统要求：macOS 13 或更新版本"
  "支持架构：Apple Silicon（arm64）与 Intel（x86_64）"
  ""
  "安装："
  "1. 将 CodeUsage.app 拖入“应用程序”文件夹。"
  "2. 应用已使用 Apple Developer ID 签名并完成 Apple 公证。"
)
print -rC1 -- "${INSTALL_GUIDE[@]}" > "$ZIP_ROOT/安装说明.txt"
rm -f "$OUTPUT_ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ZIP_ROOT" "$OUTPUT_ZIP"
/usr/bin/unzip -tqq "$OUTPUT_ZIP"
mkdir -p "$ZIP_VERIFY_DIR"
/usr/bin/unzip -q "$OUTPUT_ZIP" -d "$ZIP_VERIFY_DIR"
/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 \
  "$ZIP_VERIFY_DIR/${ZIP_ROOT:t}/CodeUsage.app"
/usr/bin/xcrun stapler validate \
  "$ZIP_VERIFY_DIR/${ZIP_ROOT:t}/CodeUsage.app"

CODEUSAGE_APP_PATH="$UNIVERSAL_APP" \
  "$PROJECT_DIR/Scripts/package_dmg.sh"
/usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_DMG"
/usr/bin/codesign --verify --verbose=2 "$OUTPUT_DMG"
/usr/bin/xcrun notarytool submit "$OUTPUT_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
/usr/bin/xcrun stapler staple "$OUTPUT_DMG"
/usr/bin/xcrun stapler validate "$OUTPUT_DMG"
/usr/sbin/spctl --assess --type open \
  --context context:primary-signature \
  --verbose=2 "$OUTPUT_DMG"

if [[ "$UPLOAD_TO_GITHUB" == "1" ]]; then
  gh release upload "$TAG" "$OUTPUT_ZIP" "$OUTPUT_DMG" --clobber
fi

echo "$UNIVERSAL_APP"
echo "$OUTPUT_ZIP"
echo "$OUTPUT_DMG"
