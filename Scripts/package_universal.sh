#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${CODEUSAGE_OUTPUT_DIR:-$PROJECT_DIR/outputs}"
SDK_PATH="${CODEUSAGE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
NATIVE_APP="$PROJECT_DIR/dist/CodeUsage.app"
UNIVERSAL_APP="$PROJECT_DIR/dist-universal/CodeUsage.app"
X86_BUILD_DIR="$PROJECT_DIR/.build-x86-release"
MODULE_CACHE_DIR="${CLANG_MODULE_CACHE_PATH:-$PROJECT_DIR/.cache/clang-module-cache}"

mkdir -p "$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

CODEUSAGE_SDK_PATH="$SDK_PATH" "$PROJECT_DIR/Scripts/package.sh" >/dev/null

swift build \
  --disable-sandbox \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$X86_BUILD_DIR" \
  --configuration release \
  --sdk "$SDK_PATH" \
  --triple x86_64-apple-macosx13.0

X86_BINARY="$X86_BUILD_DIR/x86_64-apple-macosx/release/CodeUsage"
if [[ ! -f "$X86_BINARY" ]]; then
  echo "Missing x86_64 build product: $X86_BINARY" >&2
  exit 1
fi

rm -rf "$UNIVERSAL_APP"
mkdir -p "${UNIVERSAL_APP:h}"
/usr/bin/ditto "$NATIVE_APP" "$UNIVERSAL_APP"

/usr/bin/lipo -create \
  "$NATIVE_APP/Contents/MacOS/CodeUsage" \
  "$X86_BINARY" \
  -output "$UNIVERSAL_APP/Contents/MacOS/CodeUsage"

/usr/bin/codesign --force --deep --sign - "$UNIVERSAL_APP"
/usr/bin/codesign --verify --deep --strict "$UNIVERSAL_APP"

ARCHS=$(/usr/bin/lipo -archs "$UNIVERSAL_APP/Contents/MacOS/CodeUsage")
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
  echo "Universal verification failed: $ARCHS" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$UNIVERSAL_APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$UNIVERSAL_APP/Contents/Info.plist")
ZIP_ROOT="$PROJECT_DIR/dist-universal/CodeUsage-$VERSION"
OUTPUT_ZIP="$OUTPUT_DIR/CodeUsage-$VERSION-macos-universal.zip"

rm -rf "$ZIP_ROOT"
mkdir -p "$ZIP_ROOT" "$OUTPUT_DIR"
/usr/bin/ditto "$UNIVERSAL_APP" "$ZIP_ROOT/CodeUsage.app"
ln -s /Applications "$ZIP_ROOT/Applications"
INSTALL_GUIDE=(
  "CodeUsage $VERSION（build $BUILD）"
  ""
  "系统要求：macOS 13 或更新版本"
  "支持架构：Apple Silicon（arm64）与 Intel（x86_64）"
  ""
  "安装："
  "1. 将 CodeUsage.app 拖入“应用程序”文件夹。"
  "2. 第一次启动时，若 macOS 提示无法验证开发者："
  "   - 在 Finder 中右键 CodeUsage.app，选择“打开”；或"
  "   - 前往“系统设置 → 隐私与安全性”，选择“仍要打开”。"
  ""
  "说明："
  "- 当前构建没有 Apple Developer ID 签名和公证，因此首次启动会出现安全提示。"
  "- CodeUsage 只读取本机已登录工具的额度，不包含遥测，也不会输出登录令牌。"
  "- Codex、Cursor、Claude Code、Kiro、Qoder 均需在本机安装并登录后才会显示用量。"
  "- Qoder 仅安装 IDE 时，需要保持 Qoder IDE 正在运行以读取 Credits。"
  ""
  "安全建议：仅从你信任的发送者处接收并安装此构建。"
)
print -rC1 -- "${INSTALL_GUIDE[@]}" > "$ZIP_ROOT/安装说明.txt"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ZIP_ROOT" "$OUTPUT_ZIP"
/usr/bin/unzip -tqq "$OUTPUT_ZIP"

echo "$UNIVERSAL_APP"
echo "$OUTPUT_ZIP"
