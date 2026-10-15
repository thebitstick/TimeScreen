#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/TimeScreen.app"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --product TimeScreen
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/TimeScreen" "$APP/Contents/MacOS/TimeScreen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp THIRD-PARTY-NOTICES.md LICENSE.md "$APP/Contents/Resources/"
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
case "$IDENTITY" in
    "Apple Development:"*)
        # A development build: Sparkle still reports new versions but never installs one by itself, because a release
        # build would replace this copy and macOS would drop its Screen Recording permission.
        /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool false" -c "Add :TimeScreenDevBuild bool true" "$APP/Contents/Info.plist"
        ;;
esac
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/TimeScreen"

# Sign nested code first, then the app. A real identity keeps the Screen Recording grant across rebuilds, so the first
# "Apple Development" identity in the keychain is used unless SIGN_IDENTITY says otherwise (SIGN_IDENTITY=- forces
# ad-hoc, which is what CI and releases use and makes macOS ask again whenever the binary changes).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Updater.app" "$SPARKLE/Autoupdate" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --sign "$IDENTITY" "$nested"
done
codesign --force --options runtime --entitlements Resources/TimeScreen.entitlements --sign "$IDENTITY" "$APP"
echo "Built: $APP (signed with: ${IDENTITY/#-/ad-hoc})"
