#!/bin/bash
# Quit any running TimeScreen, rebuild, install into ~/Applications and launch it. Signed with your Apple Development
# identity when you have one, so macOS keeps the Screen Recording permission between rebuilds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLED="$HOME/Applications/TimeScreen.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

pkill -f "TimeScreen.app/Contents/MacOS/TimeScreen" || true
sleep 1
"$ROOT/Scripts/build-app.sh"

mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED"
ditto "$ROOT/build/TimeScreen.app" "$INSTALLED"
"$LSREGISTER" -u "$ROOT/build/TimeScreen.app" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
open "$INSTALLED"
echo "Installed and launched $INSTALLED"
