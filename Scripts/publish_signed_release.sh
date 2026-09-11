#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION_FILE="$PROJECT_DIR/version.json"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
REMOTE="${CODEUSAGE_RELEASE_REMOTE:-origin}"
RELEASE_BRANCH="${CODEUSAGE_RELEASE_BRANCH:-main}"
CI_WORKFLOW="${CODEUSAGE_CI_WORKFLOW:-CI}"
RELEASE_WORKFLOW="${CODEUSAGE_RELEASE_WORKFLOW:-Release Please}"
WAIT_FOR_WORKFLOWS=1
VERIFY_ONLY=0
REQUESTED_TAG=""
VERIFY_DIR=""
VERIFY_DEVICE=""

cd "$PROJECT_DIR"

usage() {
  cat >&2 <<'EOF'
Usage: ./Scripts/publish_signed_release.sh [options]

Safely replaces an existing Release Please release with locally signed,
notarized Universal artifacts. This script never creates, moves, or deletes
Git tags or GitHub Releases.

Options:
  --tag vX.Y.Z          Release tag. Defaults to v<version.json>.
  --skip-workflow-wait  Do not wait for the CI and Release Please workflows.
  --verify-only         Only download and verify the existing release assets.
  -h, --help            Show this help.

Full publishing requires the same non-secret environment variables as
release_local.sh:
  CODEUSAGE_SIGNING_IDENTITY
  CODEUSAGE_BUNDLE_IDENTIFIER
  CODEUSAGE_NOTARY_PROFILE
  CODEUSAGE_PROVISIONING_PROFILE
  CODEUSAGE_WIDGET_PROVISIONING_PROFILE
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$VERIFY_DEVICE" ]]; then
    /usr/bin/hdiutil detach "$VERIFY_DEVICE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$VERIFY_DIR" && -d "$VERIFY_DIR" ]]; then
    rm -rf "$VERIFY_DIR"
  fi
}
trap cleanup EXIT

while (( $# > 0 )); do
  case "$1" in
    --tag)
      (( $# >= 2 )) || die "--tag requires a value"
      REQUESTED_TAG="$2"
      shift 2
      ;;
    --skip-workflow-wait)
      WAIT_FOR_WORKFLOWS=0
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

for command in git gh xcrun hdiutil codesign spctl unzip shasum cmp tar; do
  command -v "$command" >/dev/null 2>&1 || die "Required command is missing: $command"
done
[[ -f "$VERSION_FILE" ]] || die "Missing version file: $VERSION_FILE"

if [[ "$VERIFY_ONLY" != "1" ]] && \
   [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  die "Refusing a signed release from a dirty working tree"
fi

gh auth status >/dev/null
git fetch "$REMOTE" "$RELEASE_BRANCH" --tags --prune

if [[ "$VERIFY_ONLY" != "1" && "$(git branch --show-current)" == "$RELEASE_BRANCH" ]]; then
  git merge --ff-only "$REMOTE/$RELEASE_BRANCH"
fi

VERSION=$(/usr/bin/plutil -extract version raw -o - "$VERSION_FILE")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid version: $VERSION"
TAG="${REQUESTED_TAG:-v$VERSION}"
[[ "$TAG" == "v$VERSION" ]] || die "Tag $TAG does not match version.json ($VERSION)"

TAG_COMMIT=$(git rev-parse "$TAG^{commit}" 2>/dev/null) || die "Local tag does not exist: $TAG"
HEAD_COMMIT=$(git rev-parse HEAD)
[[ "$HEAD_COMMIT" == "$TAG_COMMIT" ]] || \
  die "HEAD ($HEAD_COMMIT) must match $TAG ($TAG_COMMIT)"

remote_tag_commit() {
  local commit
  commit=$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG^{}" | \
    /usr/bin/awk 'NR == 1 { print $1 }')
  if [[ -z "$commit" ]]; then
    commit=$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG" | \
      /usr/bin/awk 'NR == 1 { print $1 }')
  fi
  print -r -- "$commit"
}

REMOTE_TAG_COMMIT=$(remote_tag_commit)
[[ -n "$REMOTE_TAG_COMMIT" ]] || die "Remote tag does not exist: $TAG"
[[ "$REMOTE_TAG_COMMIT" == "$TAG_COMMIT" ]] || \
  die "Remote tag $TAG points to $REMOTE_TAG_COMMIT, expected $TAG_COMMIT"

RELEASE_TARGET=$(gh release view "$TAG" --json targetCommitish --jq '.targetCommitish')
[[ "$RELEASE_TARGET" == "$TAG_COMMIT" ]] || \
  die "GitHub Release target is $RELEASE_TARGET, expected $TAG_COMMIT"

wait_for_workflow() {
  local workflow="$1"
  local run_id
  run_id=$(gh run list \
    --workflow "$workflow" \
    --commit "$TAG_COMMIT" \
    --event push \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty')
  [[ -n "$run_id" ]] || die "No $workflow workflow run found for $TAG_COMMIT"
  gh run watch "$run_id" --exit-status --interval 10
}

require_release_assets() {
  local names
  names=$(gh release view "$TAG" --json assets --jq '.assets[].name')
  for name in \
    "CodeUsage-$VERSION-macos-universal.dmg" \
    "CodeUsage-$VERSION-macos-universal.zip" \
    "CodeUsage-$VERSION-source.zip"; do
    print -r -- "$names" | /usr/bin/grep -Fxq "$name" || \
      die "GitHub Release is missing expected asset: $name"
  done
}

if [[ "$VERIFY_ONLY" != "1" ]]; then
  if [[ "$WAIT_FOR_WORKFLOWS" == "1" ]]; then
    wait_for_workflow "$CI_WORKFLOW"
    wait_for_workflow "$RELEASE_WORKFLOW"
  fi
  require_release_assets

  "$PROJECT_DIR/Scripts/release_local.sh" --validate-config

  notary_ready=0
  for attempt in 1 2 3; do
    if /usr/bin/xcrun notarytool history \
      --keychain-profile "$CODEUSAGE_NOTARY_PROFILE" >/dev/null; then
      notary_ready=1
      break
    fi
    if (( attempt < 3 )); then sleep 5; fi
  done
  [[ "$notary_ready" == "1" ]] || die "Could not validate the notarytool Keychain profile"

  "$PROJECT_DIR/Scripts/release_local.sh" --upload
  "$PROJECT_DIR/Scripts/package_source.sh"
  gh release upload "$TAG" "$OUTPUT_DIR/CodeUsage-$VERSION-source.zip" --clobber
fi

require_release_assets

LOCAL_APP="$PROJECT_DIR/dist-universal/CodeUsage.app"
LOCAL_DMG="$PROJECT_DIR/dist/CodeUsage-$VERSION-macos-universal.dmg"
LOCAL_ZIP="$OUTPUT_DIR/CodeUsage-$VERSION-macos-universal.zip"
LOCAL_SOURCE="$OUTPUT_DIR/CodeUsage-$VERSION-source.zip"
[[ -d "$LOCAL_APP" ]] || die "Missing local signed app: $LOCAL_APP"
[[ -f "$LOCAL_DMG" ]] || die "Missing local signed DMG: $LOCAL_DMG"
[[ -f "$LOCAL_ZIP" ]] || die "Missing local signed ZIP: $LOCAL_ZIP"

VERIFY_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageReleaseVerify.XXXXXX")
MOUNT_DIR="$VERIFY_DIR/mount"
APP_EXTRACT_DIR="$VERIFY_DIR/app"
SOURCE_EXTRACT_DIR="$VERIFY_DIR/source"
EXPECTED_SOURCE_DIR="$VERIFY_DIR/expected-source"
mkdir -p \
  "$MOUNT_DIR" \
  "$APP_EXTRACT_DIR" \
  "$SOURCE_EXTRACT_DIR" \
  "$EXPECTED_SOURCE_DIR"

git archive --format=tar "$TAG_COMMIT" \
  LICENSE \
  Package.swift \
  README.md \
  RELEASING.md \
  THIRD_PARTY_NOTICES.md \
  version.json \
  release-please-config.json \
  .release-please-manifest.json \
  .github \
  Config \
  Sources \
  Scripts \
  Assets | \
  /usr/bin/tar -xf - -C "$EXPECTED_SOURCE_DIR"

gh release download "$TAG" --pattern "CodeUsage-$VERSION-*" --dir "$VERIFY_DIR"
REMOTE_DMG="$VERIFY_DIR/CodeUsage-$VERSION-macos-universal.dmg"
REMOTE_ZIP="$VERIFY_DIR/CodeUsage-$VERSION-macos-universal.zip"
REMOTE_SOURCE="$VERIFY_DIR/CodeUsage-$VERSION-source.zip"
[[ -f "$REMOTE_DMG" && -f "$REMOTE_ZIP" && -f "$REMOTE_SOURCE" ]] || \
  die "Downloaded release assets are incomplete"

/usr/bin/cmp "$LOCAL_DMG" "$REMOTE_DMG"
/usr/bin/cmp "$LOCAL_ZIP" "$REMOTE_ZIP"
if [[ -f "$LOCAL_SOURCE" && "$VERIFY_ONLY" != "1" ]]; then
  /usr/bin/cmp "$LOCAL_SOURCE" "$REMOTE_SOURCE"
fi
/usr/bin/shasum -a 256 "$REMOTE_DMG" "$REMOTE_ZIP" "$REMOTE_SOURCE"

/usr/bin/unzip -tqq "$REMOTE_ZIP"
/usr/bin/unzip -q "$REMOTE_ZIP" -d "$APP_EXTRACT_DIR"
DOWNLOADED_APP="$APP_EXTRACT_DIR/CodeUsage-$VERSION/CodeUsage.app"
[[ -d "$DOWNLOADED_APP" ]] || die "Downloaded ZIP is missing CodeUsage.app"
APP_VERSION=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$DOWNLOADED_APP/Contents/Info.plist")
[[ "$APP_VERSION" == "$VERSION" ]] || die "Downloaded app version is $APP_VERSION"
APP_ARCHS=$(/usr/bin/lipo -archs "$DOWNLOADED_APP/Contents/MacOS/CodeUsage")
[[ "$APP_ARCHS" == *arm64* && "$APP_ARCHS" == *x86_64* ]] || \
  die "Downloaded app is not Universal: $APP_ARCHS"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$DOWNLOADED_APP"
/usr/bin/xcrun stapler validate "$DOWNLOADED_APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$DOWNLOADED_APP"

/usr/bin/hdiutil verify "$REMOTE_DMG"
/usr/bin/codesign --verify --verbose=2 "$REMOTE_DMG"
/usr/bin/xcrun stapler validate "$REMOTE_DMG"
/usr/sbin/spctl --assess --type open \
  --context context:primary-signature \
  --verbose=2 "$REMOTE_DMG"

ATTACH_OUTPUT=$(/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$MOUNT_DIR" \
  "$REMOTE_DMG")
VERIFY_DEVICE=$(print -r -- "$ATTACH_OUTPUT" | \
  /usr/bin/awk '/Apple_HFS/ { print $1; exit }')
[[ -n "$VERIFY_DEVICE" ]] || die "Could not mount downloaded DMG"
[[ -d "$MOUNT_DIR/CodeUsage.app" ]] || die "DMG is missing CodeUsage.app"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || \
  die "DMG Applications link is invalid"
/usr/bin/cmp \
  "$EXPECTED_SOURCE_DIR/Assets/dmg-background-final@2x.png" \
  "$MOUNT_DIR/.background/installer-background@2x.png"
/usr/bin/strings -a "$MOUNT_DIR/.DS_Store" | \
  /usr/bin/grep -Fq 'installer-background@2x.png' || \
  die "DMG Finder metadata is missing the background reference"
/usr/bin/hdiutil detach "$VERIFY_DEVICE" >/dev/null
VERIFY_DEVICE=""

/usr/bin/unzip -tqq "$REMOTE_SOURCE"
/usr/bin/unzip -q "$REMOTE_SOURCE" -d "$SOURCE_EXTRACT_DIR"
SOURCE_TOP_LEVEL_FILES=(
  LICENSE
  Package.swift
  README.md
  RELEASING.md
  THIRD_PARTY_NOTICES.md
  version.json
  release-please-config.json
  .release-please-manifest.json
)
for file in "${SOURCE_TOP_LEVEL_FILES[@]}"; do
  /usr/bin/cmp "$EXPECTED_SOURCE_DIR/$file" "$SOURCE_EXTRACT_DIR/$file"
done
/usr/bin/diff -qr "$EXPECTED_SOURCE_DIR/.github" "$SOURCE_EXTRACT_DIR/.github"
/usr/bin/diff -qr "$EXPECTED_SOURCE_DIR/Config" "$SOURCE_EXTRACT_DIR/Config"
/usr/bin/diff -qr "$EXPECTED_SOURCE_DIR/Sources" "$SOURCE_EXTRACT_DIR/Sources"
/usr/bin/diff -qr "$EXPECTED_SOURCE_DIR/Scripts" "$SOURCE_EXTRACT_DIR/Scripts"
SOURCE_ASSETS=(
  AppIcon.svg
  AppIcon-1024.png
  AppIcon.icns
  provider-codex.svg
  provider-cursor.svg
  provider-claude.svg
  provider-kiro.svg
  provider-qoder.svg
  github-mark.svg
  statusbar-logo.svg
  dmg-background-imagegen-v1.png
  dmg-background-final.png
  dmg-background-final@2x.png
)
EXPECTED_ASSET_LIST="$VERIFY_DIR/expected-assets.txt"
ACTUAL_ASSET_LIST="$VERIFY_DIR/actual-assets.txt"
print -rl -- "${SOURCE_ASSETS[@]}" | /usr/bin/sort > "$EXPECTED_ASSET_LIST"
/usr/bin/find "$SOURCE_EXTRACT_DIR/Assets" -maxdepth 1 -type f -exec \
  /usr/bin/basename {} \; | /usr/bin/sort > "$ACTUAL_ASSET_LIST"
/usr/bin/cmp "$EXPECTED_ASSET_LIST" "$ACTUAL_ASSET_LIST"
for asset in "${SOURCE_ASSETS[@]}"; do
  /usr/bin/cmp \
    "$EXPECTED_SOURCE_DIR/Assets/$asset" \
    "$SOURCE_EXTRACT_DIR/Assets/$asset"
done

FINAL_TARGET=$(gh release view "$TAG" --json targetCommitish --jq '.targetCommitish')
[[ "$FINAL_TARGET" == "$TAG_COMMIT" ]] || die "Release target changed during publishing"
FINAL_REMOTE_TAG=$(remote_tag_commit)
[[ "$FINAL_REMOTE_TAG" == "$TAG_COMMIT" ]] || die "Remote tag changed during publishing"

RELEASE_URL=$(gh release view "$TAG" --json url --jq '.url')
echo "Signed release verification passed: $RELEASE_URL"
echo "$LOCAL_APP"
echo "$LOCAL_ZIP"
if [[ -f "$LOCAL_SOURCE" ]]; then echo "$LOCAL_SOURCE"; fi
echo "$LOCAL_DMG"
