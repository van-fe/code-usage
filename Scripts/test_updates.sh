#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TOOLS_DIR="$PROJECT_DIR/.build-package/artifacts/sparkle/Sparkle/bin"
FRAMEWORK_DIR="$PROJECT_DIR/.build-package/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
CACHE_DIR="$PROJECT_DIR/.cache/update-tests"
WORK_DIR=$(mktemp -d "${TMPDIR%/}/CodeUsageUpdateTest.XXXXXX")
SERVER_PID=""
typeset -a TEST_DOMAINS
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  for DOMAIN in "${TEST_DOMAINS[@]}"; do
    /usr/bin/defaults delete "$DOMAIN" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Caches/$DOMAIN"
  done
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
mkdir -p "$CACHE_DIR"
[[ -x "$TOOLS_DIR/sign_update" ]] || {
  echo "Resolve the Sparkle package with scratch path .build-package first." >&2
  exit 1
}

for LOCALIZATION in "$PROJECT_DIR/Sources/CodeUsage/Resources"/*.lproj/Localizable.strings; do
  /usr/bin/plutil -lint "$LOCALIZATION" >/dev/null
  for KEY in '检查更新…' '自动检查更新' '自动下载并安装更新' '无法启动应用更新' \
    '更新会在后台下载并校验，在退出时安装；也可选择立即安装并重新启动。'; do
    /usr/bin/grep -Fq "\"$KEY\" =" "$LOCALIZATION"
  done
done

swiftc -module-cache-path "$CACHE_DIR" -parse-as-library \
  -F "$FRAMEWORK_DIR" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$PROJECT_DIR/Sources/CodeUsage/Localization.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/AppUpdateManager.swift" \
  "$PROJECT_DIR/Scripts/UpdateTest.swift" \
  -o "$WORK_DIR/UpdateTest"
DYLD_FRAMEWORK_PATH="$FRAMEWORK_DIR" "$WORK_DIR/UpdateTest" --fixtures "$WORK_DIR"

# An ephemeral localhost server serves only disposable signed test fixtures.
/usr/bin/python3 - "$WORK_DIR" <<'PY' >"$WORK_DIR/server.log" 2>&1 &
import functools, http.server, pathlib, sys
root = pathlib.Path(sys.argv[1])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
with http.server.HTTPServer(('127.0.0.1', 0), handler) as server:
    (root / 'port').write_text(str(server.server_port))
    server.serve_forever()
PY
SERVER_PID=$!
for ATTEMPT in {1..50}; do
  [[ -f "$WORK_DIR/port" ]] && break
  sleep 0.1
done
PORT=$(cat "$WORK_DIR/port")
TEST_APP="$WORK_DIR/UpdateTest.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Frameworks"
/usr/bin/ditto "$FRAMEWORK_DIR/Sparkle.framework" "$TEST_APP/Contents/Frameworks/Sparkle.framework"
cp "$WORK_DIR/UpdateTest" "$TEST_APP/Contents/MacOS/UpdateTest"

# Use real Sparkle startup and parsing, with no access to production settings
# or downloads. Information-only probes can never install an app.
for SCENARIO in preferences found current rejected archive-rejected invalid-config; do
  /usr/bin/python3 - "$PROJECT_DIR" "$WORK_DIR" "$SCENARIO" "$PORT" <<'PY'
import pathlib, plistlib, sys, uuid
project, root = map(pathlib.Path, sys.argv[1:3])
scenario, port = sys.argv[3:]
with (project / 'Config/Updates.plist').open('rb') as f:
    info = plistlib.load(f)
info.update(CFBundleIdentifier='com.van-fe.CodeUsage.UpdateTest.' + uuid.uuid4().hex,
            CFBundleExecutable='UpdateTest', CFBundleName='UpdateTest',
            CFBundlePackageType='APPL', CFBundleVersion='1.0.0',
            CFBundleShortVersionString='1.0.0', LSUIElement=True,
            SUFeedURL=f'http://127.0.0.1:{port}/{scenario}.xml',
            SUPublicEDKey=(root / 'test-public-key').read_text(),
            NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
if scenario == 'invalid-config':
    info['SUPublicEDKey'] = 'invalid-public-key'
with (root / 'UpdateTest.app/Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
version = '1.0.0' if scenario == 'current' else '99.0.0'
(root / (scenario + '.xml')).write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>CodeUsage update test</title><item>
<sparkle:version>{version}</sparkle:version>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="http://127.0.0.1:{port}/payload.zip" length="1" type="application/octet-stream" />
</item></channel></rss>
''')
PY
  if [[ "$SCENARIO" == "archive-rejected" ]]; then
    print -rn -- a > "$WORK_DIR/payload.zip"
    ARCHIVE_SIGNATURE=$("$TOOLS_DIR/sign_update" --ed-key-file "$WORK_DIR/test-key" -p "$WORK_DIR/payload.zip")
    /usr/bin/sed -i '' "s|length=\"1\"|sparkle:edSignature=\"$ARCHIVE_SIGNATURE\" length=\"1\"|" "$WORK_DIR/$SCENARIO.xml"
    # Same byte length, different contents: the archive signature must fail.
    print -rn -- b > "$WORK_DIR/payload.zip"
  fi
  "$TOOLS_DIR/sign_update" --ed-key-file "$WORK_DIR/test-key" "$WORK_DIR/$SCENARIO.xml" >/dev/null
  if [[ "$SCENARIO" == "rejected" ]]; then
    /usr/bin/sed -i '' 's/99.0.0/98.0.0/' "$WORK_DIR/$SCENARIO.xml"
  fi
  /usr/bin/codesign --force --sign - "$TEST_APP" >/dev/null 2>&1
  TEST_DOMAINS+=("$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$TEST_APP/Contents/Info.plist")")
  case "$SCENARIO" in
    preferences|invalid-config) "$TEST_APP/Contents/MacOS/UpdateTest" "--$SCENARIO" ;;
    *) "$TEST_APP/Contents/MacOS/UpdateTest" --probe "$SCENARIO" ;;
  esac
done

# Exercise our release-feed verifier with a disposable signing tool adapter.
# No test reads or changes the publisher's real Keychain key.
mkdir -p "$WORK_DIR/signing-tools"
cat > "$WORK_DIR/signing-tools/sign_update" <<'SH'
#!/bin/zsh
set -euo pipefail
shift 2 # --account <account>; use the disposable file instead.
exec "$UPDATE_TEST_SIGN_TOOL" --ed-key-file "$UPDATE_TEST_KEY_PATH" "$@"
SH
chmod +x "$WORK_DIR/signing-tools/sign_update"
export UPDATE_TEST_SIGN_TOOL="$TOOLS_DIR/sign_update"
export UPDATE_TEST_KEY_PATH="$WORK_DIR/test-key"
export CODEUSAGE_SPARKLE_TOOLS_DIR="$WORK_DIR/signing-tools"
ARCHIVE="$WORK_DIR/CodeUsage-1.0.0-macos-universal.dmg"
print -rn -- fixture > "$ARCHIVE"
ARCHIVE_SIGNATURE=$("$TOOLS_DIR/sign_update" --ed-key-file "$WORK_DIR/test-key" -p "$ARCHIVE")
cat > "$WORK_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><sparkle:version>1.0.0</sparkle:version>
<enclosure url="https://github.com/van-fe/code-usage/releases/download/v1.0.0/CodeUsage-1.0.0-macos-universal.dmg" sparkle:edSignature="$ARCHIVE_SIGNATURE" length="7" />
</item></channel></rss>
XML
"$TOOLS_DIR/sign_update" --ed-key-file "$WORK_DIR/test-key" "$WORK_DIR/appcast.xml" >/dev/null
"$PROJECT_DIR/Scripts/verify_appcast.sh" "$TEST_APP" "$ARCHIVE" "$WORK_DIR/appcast.xml"
print -rn -- altered > "$ARCHIVE"
if "$PROJECT_DIR/Scripts/verify_appcast.sh" "$TEST_APP" "$ARCHIVE" "$WORK_DIR/appcast.xml" >/dev/null 2>&1; then
  echo "Feed verifier accepted a tampered archive" >&2
  exit 1
fi
print -rn -- fixture > "$ARCHIVE"
/usr/bin/sed -i '' 's/length="7"/length="8"/' "$WORK_DIR/appcast.xml"
"$TOOLS_DIR/sign_update" --ed-key-file "$WORK_DIR/test-key" "$WORK_DIR/appcast.xml" >/dev/null
if "$PROJECT_DIR/Scripts/verify_appcast.sh" "$TEST_APP" "$ARCHIVE" "$WORK_DIR/appcast.xml" >/dev/null 2>&1; then
  echo "Feed verifier accepted an incorrect archive length" >&2
  exit 1
fi
echo "Release feed tampering and length checks passed"
echo "Updater integration tests passed"
