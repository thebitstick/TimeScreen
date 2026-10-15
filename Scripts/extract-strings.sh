#!/bin/bash
# Pulls every localizable string out of the Swift sources into Resources/Localizable.xcstrings, marking strings the code no
# longer uses as stale. Run it after adding or changing a user-visible string, then fill in the translations.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CATALOG="Resources/Localizable.xcstrings"
DATA="$ROOT/build/stringsdata"
[ -f "$CATALOG" ] || echo '{"sourceLanguage":"en","strings":{},"version":"1.0"}' > "$CATALOG"

rm -rf "$DATA" "$ROOT/build/strings-scratch"
mkdir -p "$DATA"
swift build --scratch-path "$ROOT/build/strings-scratch" --product TimeScreen \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$DATA" >/dev/null
FILES=()
while IFS= read -r file; do FILES+=("$file"); done < <(find "$DATA" -name '*.stringsdata')
xcrun xcstringstool sync "$CATALOG" --stringsdata "${FILES[@]}"
rm -rf "$DATA" "$ROOT/build/strings-scratch"
echo "Updated $CATALOG"
