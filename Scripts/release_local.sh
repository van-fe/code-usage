#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION_FILE="$PROJECT_DIR/version.json"
UNIVERSAL_APP="$PROJECT_DIR/dist-universal/CodeUsage.app"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
UPLOAD_TO_GITHUB=0

cd "$PROJECT_DIR"

usage() {
  echo "Usage: ./Scripts/release_local.sh [--upload]" >&2
  echo "" >&2
  echo "Required environment variables:" >&2
  echo "  CODEUSAGE_SIGNING_IDENTITY     Developer ID Application identity" >&2
  echo "  CODEUSAGE_BUNDLE_IDENTIFIER    Stable reverse-DNS bundle identifier" >&2
  echo "  CODEUSAGE_NOTARY_PROFILE       notarytool Keychain profile" >&2
}

for argument in "$@"; do
  case "$argument" in
    --upload) UPLOAD_TO_GITHUB=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $argument" >&2; usage; exit 2 ;;
  esac
done

SIGNING_IDENTITY="${CODEUSAGE_SIGNING_IDENTITY:-}"
BUNDLE_IDENTIFIER="${CODEUSAGE_BUNDLE_IDENTIFIER:-}"
NOTARY_PROFILE="${CODEUSAGE_NOTARY_PROFILE:-}"

if [[ -z "$SIGNING_IDENTITY" || -z "$BUNDLE_IDENTIFIER" || -z "$NOTARY_PROFILE" ]]; then
  usage
  exit 2
fi
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi
if [[ "${CODEUSAGE_ALLOW_DIRTY_RELEASE:-0}" != "1" ]] && \
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

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

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
  "$PROJECT_DIR/Scripts/package_universal.sh"

/usr/bin/codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$UNIVERSAL_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$UNIVERSAL_APP"

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
