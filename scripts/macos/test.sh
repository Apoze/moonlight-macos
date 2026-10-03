#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TOOLS=${MOONLIGHT_TOOLS_DIR:-"$ROOT/../.tools"}
QT="$TOOLS/Qt/6.11.1/macos"
export DYLD_LIBRARY_PATH="$ROOT/libs/mac/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
projects=(timingcontroller ratepolicy pacingworker replayconfig vrrrenderpolicy d3d11bindpolicy replay)
binaries=(tst_vrrtimingcontroller tst_vrrratepolicy tst_vrrpacingworker tst_vrrreplayconfig tst_vrrrenderpolicy tst_d3d11bindpolicy vrrreplay)
for index in "${!projects[@]}"; do
    project=${projects[$index]}
    directory="$ROOT/build/tests-macos/$project"
    mkdir -p "$directory"
    cd "$directory"
    "$QT/bin/qmake" "$ROOT/tests/vrr/$project.pro" 'CONFIG+=release' QMAKE_APPLE_DEVICE_ARCHS=arm64 > configure.log 2>&1
    make -j"${MOONLIGHT_BUILD_JOBS:-8}" > build.log 2>&1 || { tail -40 build.log; exit 1; }
    if [[ $project == replay ]]; then
        "./${binaries[$index]}" --help > test.log 2>&1
    else
        "./${binaries[$index]}" > test.log 2>&1 || { cat test.log; exit 1; }
    fi
    echo "PASS: ${binaries[$index]}"
done
