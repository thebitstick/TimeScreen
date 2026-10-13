#!/bin/bash
# Usage: Scripts/publish-appcast.sh v0.3.0 [--dry-run]
# Signs the release's zip with the Sparkle key in your keychain (account "TimeScreen") and attaches appcast.xml to
# that release. The app's feed is releases/latest/download/appcast.xml, so run this for every release.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TAG="${1:?usage: publish-appcast.sh vX.Y.Z [--dry-run]}"
DRY_RUN="${2:-}"
REPO="thebitstick/TimeScreen"
VERSION="${TAG#v}"
ZIP="TimeScreen-$TAG.zip"

gh_cmd() { if command -v gh >/dev/null; then gh "$@"; else nix shell nixpkgs#gh -c gh "$@"; fi; }

swift package resolve >/dev/null
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh_cmd release download "$TAG" --repo "$REPO" --pattern "$ZIP" --dir "$WORK"

SIGNATURE_ATTRIBUTES="$("$SIGN_UPDATE" --account TimeScreen "$WORK/$ZIP")"

cat > "$WORK/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>TimeScreen</title>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
            <enclosure url="https://github.com/$REPO/releases/download/$TAG/$ZIP" type="application/octet-stream" $SIGNATURE_ATTRIBUTES/>
        </item>
    </channel>
</rss>
XML

if [ "$DRY_RUN" = "--dry-run" ]; then
    cp "$WORK/appcast.xml" "$ROOT/build/appcast.xml"
    echo "Wrote build/appcast.xml (not uploaded)"
else
    gh_cmd release upload "$TAG" "$WORK/appcast.xml" --repo "$REPO" --clobber
    echo "Uploaded appcast.xml to $TAG"
fi
