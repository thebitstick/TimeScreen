#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/TimeScreen.app"

swift build -c release --product TimeScreen
BIN="$(swift build -c release --show-bin-path)/TimeScreen"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TimeScreen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SIGN_IDENTITY (e.g. "Apple Development: you@example.com") keeps the Screen Recording grant across rebuilds;
# the ad-hoc default makes macOS ask again whenever the binary changes.
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built: $APP"
