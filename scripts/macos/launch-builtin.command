#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP="$ROOT/build/deploy/Moonlight Mac VRR Dev.app"
RUNTIME="$ROOT/.runtime/builtin"
[[ -x "$APP/Contents/MacOS/Moonlight" ]] || { echo 'Run scripts/macos/build.sh first.' >&2; exit 1; }
"$ROOT/build/macos/display-probe" --check-builtin
mkdir -p "$RUNTIME/Moonlight Game Streaming Project"
chmod 700 "$RUNTIME"
touch "$RUNTIME/portable.dat"
INI="$RUNTIME/Moonlight Game Streaming Project/Moonlight.ini"
if [[ ! -f "$INI" ]]; then
    cat > "$INI" <<'SETTINGS'
[General]
width=1920
height=1200
fps=60
bitrate=30000
videocfg=2
videodec=1
renderer=2
vsync=true
framepacing=true
enablevrr=false
hdr=false
windowmode=1
uidisplaymode=0
richpresence=false
quitAppAfter=false
SETTINGS
fi
cd "$RUNTIME"
export MOONLIGHT_BUILTIN_DISPLAY_ONLY=1
exec "$APP/Contents/MacOS/Moonlight" "$@"
