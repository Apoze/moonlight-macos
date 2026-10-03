#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TOOLS=${MOONLIGHT_TOOLS_DIR:-"$ROOT/../.tools"}
QT="$TOOLS/Qt/6.11.1/macos"
[[ $(uname -s) == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
xcode-select -p >/dev/null
if [[ ! -x "$QT/bin/qmake" ]]; then
    python3 -m venv "$TOOLS/aqt"
    "$TOOLS/aqt/bin/python" -m pip install 'aqtinstall==3.3.0'
    "$TOOLS/aqt/bin/aqt" install-qt mac desktop 6.11.1 clang_64 \
        --outputdir "$TOOLS/Qt" --archives qtbase qtdeclarative qtsvg qttools qttranslations
fi
cd "$ROOT"
git submodule update --init --recursive
if [[ ! -f libs/mac/include/SDL2/SDL.h ]]; then
    python3 setup-deps.py
fi
"$QT/bin/qmake" -v
