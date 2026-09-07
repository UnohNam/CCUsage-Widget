#!/bin/bash
# CCUsage.app + 내장 WidgetKit 익스텐션 빌드.
# 전체 Xcode 없이 Command Line Tools 만으로 만든다.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${CCUSAGE_DEST:-/Applications}/CCUsage.app"
AX="$APP/Contents/PlugIns/CCUsageWidget.appex"
TARGET="arm64-apple-macos14.0"

# Xcode 가 있으면 그쪽 SDK 를 쓴다. CLT SDK 는 버전이 뒤처져 WidgetKit 스텁이 낡을 수 있다.
XCODE_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [ -d "$XCODE_SDK" ]; then
  SDKFLAG=(-sdk "$XCODE_SDK")
  echo "▸ SDK: $(plutil -extract Version raw "$XCODE_SDK/SDKSettings.plist" 2>/dev/null) (Xcode)"
else
  SDKFLAG=()
  echo "▸ SDK: Command Line Tools"
fi

# ── 서명 신원 결정 ────────────────────────────────────────────
# Apple Development 인증서가 있으면 그걸 쓰고(Team ID 확보), 없으면 ad-hoc 으로 떨어진다.
# 위젯 갤러리 노출에는 Team ID 가 필요한 것으로 보이므로 실인증서가 있으면 반드시 쓴다.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -E "Apple Development|Developer ID Application" | head -1 \
  | sed -E 's/^ *[0-9]+\) ([0-9A-F]+) .*/\1/')

if [ -n "$IDENTITY" ]; then
  TEAMID=$(security find-certificate -c "$(security find-identity -v -p codesigning | grep -E "Apple Development|Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | grep -oE "OU *= *[A-Z0-9]{10}" | grep -oE "[A-Z0-9]{10}$")
  GROUP="${TEAMID:+$TEAMID.}group.local.ccusage"
  echo "▸ 서명 신원: $IDENTITY  (Team ID: ${TEAMID:-없음})"
else
  IDENTITY="-"
  GROUP="group.local.ccusage"
  echo "▸ 서명 신원: ad-hoc (Apple Development 인증서 없음 — 위젯 갤러리에 안 뜰 수 있음)"
fi
echo "▸ App Group: $GROUP"

# chronod 는 CFBundleVersion 이 같으면 디스크립터를 refetch 하지 않는다. 매 빌드마다 올린다.
BUILDVER=$(date +%s)
echo "▸ CFBundleVersion: $BUILDVER"

# Xcode 산출물과 동일한 빌드 메타데이터를 채운다.
if [ -d "$XCODE_SDK" ]; then
  DT_SDKVER=$(plutil -extract Version raw "$XCODE_SDK/SDKSettings.plist" 2>/dev/null)
  DT_SDKBUILD=$(plutil -extract ProductBuildVersion raw "$XCODE_SDK/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null)
  DT_XCODEVER=$(plutil -extract CFBundleShortVersionString raw /Applications/Xcode.app/Contents/version.plist 2>/dev/null)
  DT_XCODEBUILD=$(plutil -extract ProductBuildVersion raw /Applications/Xcode.app/Contents/version.plist 2>/dev/null)
  DT_XCODE=$(printf "%04d" "$(echo "$DT_XCODEVER" | awk -F. '{printf "%d%d%d", $1, $2, ($3==""?0:$3)}')")
fi
: "${DT_SDKVER:=26.0}" "${DT_SDKBUILD:=25A000}" "${DT_XCODE:=2600}" "${DT_XCODEBUILD:=17A000}"
OSBUILD=$(sw_vers -buildVersion)

echo "▸ 기존 번들 정리"
# KeepAlive 가 걸려 있으면 pkill 로는 곧바로 되살아나 서명이 "Operation not permitted" 로
# 실패한다. 에이전트를 내렸다가 마지막에 다시 올린다.
launchctl bootout "gui/$(id -u)/local.ccusage.widget" 2>/dev/null || true
pkill -x CCUsage 2>/dev/null || true
pkill -f "CCUsageWidget.appex/Contents/MacOS/CCUsageWidget" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$AX/Contents/MacOS"

# ── 컨테이너 앱 Info.plist ─────────────────────────────────────
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CCUsage</string>
  <key>CFBundleDisplayName</key><string>CCUsage</string>
  <key>CFBundleIdentifier</key><string>local.ccusage.app</string>
  <key>CFBundleExecutable</key><string>CCUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>__BUILDVER__</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>BuildMachineOSBuild</key><string>__OSBUILD__</string>
  <key>DTCompiler</key><string>com.apple.compilers.llvm.clang.1_0</string>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>__DT_SDKVER__</string>
  <key>DTPlatformBuild</key><string>__DT_SDKBUILD__</string>
  <key>DTSDKName</key><string>macosx__DT_SDKVER__</string>
  <key>DTSDKBuild</key><string>__DT_SDKBUILD__</string>
  <key>DTXcode</key><string>__DT_XCODE__</string>
  <key>DTXcodeBuild</key><string>__DT_XCODEBUILD__</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CCUsageAppGroup</key><string>__GROUP__</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# ── 위젯 익스텐션 Info.plist ───────────────────────────────────
cat > "$AX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CCUsageWidget</string>
  <key>CFBundleDisplayName</key><string>CCUsage</string>
  <key>CFBundleIdentifier</key><string>local.ccusage.app.widget</string>
  <key>CFBundleExecutable</key><string>CCUsageWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>__BUILDVER__</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>BuildMachineOSBuild</key><string>__OSBUILD__</string>
  <key>DTCompiler</key><string>com.apple.compilers.llvm.clang.1_0</string>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>__DT_SDKVER__</string>
  <key>DTPlatformBuild</key><string>__DT_SDKBUILD__</string>
  <key>DTSDKName</key><string>macosx__DT_SDKVER__</string>
  <key>DTSDKBuild</key><string>__DT_SDKBUILD__</string>
  <key>DTXcode</key><string>__DT_XCODE__</string>
  <key>DTXcodeBuild</key><string>__DT_XCODEBUILD__</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CCUsageAppGroup</key><string>__GROUP__</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict></plist>
PLIST

# 히어독은 따옴표로 감쌌으므로 치환으로 주입한다.
sed -i '' "s|__GROUP__|$GROUP|; s|__BUILDVER__|$BUILDVER|; s|__OSBUILD__|$OSBUILD|; \
  s|__DT_SDKVER__|$DT_SDKVER|g; s|__DT_SDKBUILD__|$DT_SDKBUILD|g; \
  s|__DT_XCODE__|$DT_XCODE|; s|__DT_XCODEBUILD__|$DT_XCODEBUILD|" \
  "$APP/Contents/Info.plist" "$AX/Contents/Info.plist"

# ── 엔타이틀먼트 ──────────────────────────────────────────────
# 위젯: 샌드박스 필수(없으면 시스템이 익스텐션을 등록조차 하지 않음) + App Group 으로 데이터 수신
cat > /tmp/ccusage-widget.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
PLIST
# 앱: ~/.claude/projects 를 읽어야 하므로 비샌드박스. App Group 컨테이너에는 직접 경로로 쓴다.
cat > /tmp/ccusage-app.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
PLIST

# ── 집계 스크립트를 번들에 포함 ────────────────────────────
echo "▸ 스크립트 번들에 복사"
cp "$DIR/collect.py" "$DIR/limits.py" "$DIR/codex.py" "$APP/Contents/Resources/"

# ── 앱 아이콘 ────────────────────────────────────────────────
echo "▸ 아이콘 생성"
ICONSET=$(mktemp -d)/CCUsage.iconset
mkdir -p "$ICONSET"
swiftc -O -swift-version 5 -o /tmp/ccusage-makeicon "$DIR/src/makeicon.swift"
/tmp/ccusage-makeicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# ── 컴파일 ────────────────────────────────────────────────────
echo "▸ 위젯 익스텐션 컴파일"
# 앱 익스텐션은 엔트리 포인트가 NSExtensionMain 이어야 한다. Swift 의 @main 이 만든
# 기본 main 으로 들어가면 ExtensionFoundation 이 확장 타입을 판정하지 못하고
# "Unrecognized extension type" 으로 죽어, chronod 가 세션을 못 맺는다.
swiftc -O -swift-version 5 -target "$TARGET" "${SDKFLAG[@]}" -parse-as-library \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework WidgetKit -framework SwiftUI \
  -o "$AX/Contents/MacOS/CCUsageWidget" \
  "$DIR/src/Shared.swift" "$DIR/src/Widget/Widget.swift"

echo "▸ 앱 컴파일"
swiftc -O -swift-version 5 -target "$TARGET" "${SDKFLAG[@]}" \
  -framework AppKit -framework WidgetKit \
  -o "$APP/Contents/MacOS/CCUsage" \
  "$DIR/src/Shared.swift" "$DIR/src/App/Panel.swift" "$DIR/src/App/main.swift"

# ── 서명 (안쪽부터) ───────────────────────────────────────────
echo "▸ 서명"
codesign --force -s "$IDENTITY" --options runtime --entitlements /tmp/ccusage-widget.entitlements "$AX" 2>&1 | grep -v "replacing" || true
codesign --force -s "$IDENTITY" --options runtime --entitlements /tmp/ccusage-app.entitlements "$APP" 2>&1 | grep -v "replacing" || true

# ── 시스템 등록 ───────────────────────────────────────────────
echo "▸ LaunchServices / PlugInKit 등록"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$APP"
# 이미 떠 있는 익스텐션 프로세스는 옛 번들을 물고 있다. 그대로 두면 WidgetKit 아카이버가
# "Bundle version did not match" 로 타임라인 저장을 거부해서 — 익스텐션은 매번 정상적으로
# 타임라인을 돌려주는데도 — 위젯 화면이 옛 값에 그대로 얼어붙는다. chronod 가 새 번들로
# 다시 띄우도록 여기서 정리한다.
pkill -f "CCUsageWidget.appex/Contents/MacOS/CCUsageWidget" 2>/dev/null || true
pluginkit -e use -i local.ccusage.app.widget 2>/dev/null || true
pluginkit -a "$AX" 2>/dev/null || true
sleep 1

if pluginkit -mAvv -p com.apple.widgetkit-extension 2>/dev/null | grep -q "local.ccusage.app.widget"; then
  echo "✅ 위젯 등록됨 — 바탕화면 우클릭 → '위젯 편집…' 에서 CCUsage 확인"
else
  echo "⚠️  위젯이 아직 등록되지 않았습니다. 앱을 한 번 실행한 뒤 다시 확인하세요."
fi
echo "빌드 완료: $APP"

# ── 로그인 항목 등록 ─────────────────────────────────────────
# 위젯은 앱이 살아 있는 동안에만 갱신된다(앱이 60초마다 집계 → 스냅샷 → 타임라인 리로드).
# 앱이 종료되면 위젯은 마지막 스냅샷을 그대로 붙들고 있으므로, 로그인 시 자동 실행하고
# KeepAlive 로 죽으면 되살린다.
echo "▸ 로그인 항목 등록"
AGENT=~/Library/LaunchAgents/local.ccusage.widget.plist
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.ccusage.widget</string>
  <key>ProgramArguments</key><array><string>/Applications/CCUsage.app/Contents/MacOS/CCUsage</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <!-- launchd 기본 PATH 에는 ~/.local/bin 이 없어 claude CLI 를 못 찾는다. -->
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/local.ccusage.widget" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/local.ccusage.widget" 2>/dev/null || true
