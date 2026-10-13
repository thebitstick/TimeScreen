#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/TimeScreen.app"
IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --product TimeScreen
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/TimeScreen" "$APP/Contents/MacOS/TimeScreen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp THIRD-PARTY-NOTICES.md LICENSE.md "$APP/Contents/Resources/"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/TimeScreen"

# Sign nested code first, then the app. SIGN_IDENTITY (e.g. "Apple Development: you@example.com") keeps the
# Screen Recording grant across rebuilds; the ad-hoc default makes macOS ask again whenever the binary changes.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Updater.app" "$SPARKLE/Autoupdate" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --sign "$IDENTITY" "$nested"
done
codesign --force --options runtime --entitlements Resources/TimeScreen.entitlements --sign "$IDENTITY" "$APP"
echo "Built: $APP"
