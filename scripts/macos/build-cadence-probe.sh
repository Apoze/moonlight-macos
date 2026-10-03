#!/bin/bash
# Standalone diagnostic; does not build, launch or configure Moonlight.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP="$ROOT/build/tests-macos/Metal Cadence Probe.app"
mkdir -p "$APP/Contents/MacOS"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump(dict(CFBundleIdentifier='io.github.apoze.metal-cadence-probe',
                      CFBundleExecutable='metal-cadence-probe',
                      CFBundleName='Metal Cadence Probe', CFBundlePackageType='APPL',
                      NSHighResolutionCapable=True, LSMinimumSystemVersion='14.0',
                      LSApplicationCategoryType='public.app-category.games'), output)
PY
xcrun clang++ -std=c++17 -fblocks -Wall -Wextra -mmacosx-version-min=14.0 \
    -framework AppKit -framework Metal -framework QuartzCore \
    -framework CoreGraphics "$ROOT/tests/macos/metal-cadence-probe.mm" \
    -o "$APP/Contents/MacOS/metal-cadence-probe"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
