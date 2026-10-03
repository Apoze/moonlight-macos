#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TOOLS=${MOONLIGHT_TOOLS_DIR:-"$ROOT/../.tools"}
QT="$TOOLS/Qt/6.11.1/macos"
export DYLD_LIBRARY_PATH="$ROOT/libs/mac/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export MOONLIGHT_VRR_TEST_EXPORT_COMMAND_BUFFER_TRACE="$ROOT/build/tests-macos/command-buffer.vrrtrace"
projects=(timingcontroller ratepolicy pacingworker replayconfig vrrrenderpolicy d3d11bindpolicy metalpresentation replay)
binaries=(tst_vrrtimingcontroller tst_vrrratepolicy tst_vrrpacingworker tst_vrrreplayconfig tst_vrrrenderpolicy tst_d3d11bindpolicy tst_metalpresentation vrrreplay)
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

python3 "$ROOT/tests/vrr/test_metal_pipeline.py"
"$ROOT/build/tests-macos/replay/vrrreplay" "$MOONLIGHT_VRR_TEST_EXPORT_COMMAND_BUFFER_TRACE" \
    --require-exact-baseline --output "$ROOT/build/tests-macos/command-buffer-replay.json"
echo "PASS: command-buffer present/cancel exact replay"
