#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TOOLS=${MOONLIGHT_TOOLS_DIR:-"$ROOT/../.tools"}
QT="$TOOLS/Qt/6.11.1/macos"
BUILD="$ROOT/build/macos"
APP="$ROOT/build/deploy/Moonlight Mac VRR Dev.app"
[[ -x "$QT/bin/qmake" ]] || { echo 'Run scripts/macos/bootstrap.sh first.' >&2; exit 1; }
mkdir -p "$BUILD"
cd "$BUILD"
export CI_VERSION=6.1.0-vrr18-macos-dev
"$QT/bin/qmake" "$ROOT/moonlight-qt.pro" 'CONFIG+=release' QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j"${MOONLIGHT_BUILD_JOBS:-8}" release > build.log 2>&1 || { tail -60 build.log; exit 1; }
# Refuse to replace an application that is in use.
if /bin/ps -axo command= | /usr/bin/grep -F "$APP/Contents/MacOS/Moonlight" | /usr/bin/grep -v grep >/dev/null; then
    echo 'Close Moonlight Mac VRR Dev before deploying.' >&2
    exit 1
fi
mkdir -p "$ROOT/build/deploy"
# build/deploy is generated, never a user installation.
rm -rf "$APP"
ditto "$BUILD/app/Moonlight.app" "$APP"
# Deploy only plugin families used by the client. Qt's optional database drivers
# can depend on third-party installations that are not shipped with the SDK.
plugin_args=()
for family in platforms styles imageformats iconengines tls networkinformation; do
    if [[ -d "$QT/plugins/$family" ]]; then
        ditto "$QT/plugins/$family" "$APP/Contents/PlugIns/$family"
        for plugin in "$APP/Contents/PlugIns/$family/"*.dylib; do
            [[ -f "$plugin" ]] && plugin_args+=("-executable=$plugin")
        done
    fi
done
"$QT/bin/macdeployqt" "$APP" -qmldir="$ROOT/app/gui" -no-plugins -no-codesign \
    "${plugin_args[@]}" > deploy.log 2>&1
if grep -q '^ERROR:' deploy.log; then cat deploy.log; exit 1; fi
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.apoze.moonlight-macos-dev' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Moonlight Mac VRR Dev' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 13.0' "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
xcrun swiftc "$ROOT/scripts/macos/display-probe.swift" -o "$BUILD/display-probe"
echo "Built: $APP"
echo 'Launch with scripts/macos/launch-builtin.command (isolated settings, built-in display guard).'
