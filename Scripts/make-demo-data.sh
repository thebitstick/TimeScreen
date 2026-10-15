#!/bin/bash
# Usage: Scripts/make-demo-data.sh <output dir> [yyyy-MM-dd]
# Writes a fictional day of screenshots plus a search index, for README screenshots and demos. Point the app at it with
#   TIMESCREEN_DATA_DIR=<output dir> and open the timeline with: -timelineDay <date> -timelineQuery <text>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: make-demo-data.sh <output dir> [yyyy-MM-dd]}"
DAY="${2:-$(date -v-1d +%Y-%m-%d)}"
BIN="$(mktemp -d)/demo-data"
swiftc -O -o "$BIN" "$ROOT/Scripts/demo-data/main.swift" "$ROOT/Sources/TimeScreen/Database.swift" "$ROOT/Sources/TimeScreen/SearchQuery.swift" "$ROOT/Sources/TimeScreen/SummaryInput.swift" "$ROOT/Sources/TimeScreen/CJKText.swift" "$ROOT/Sources/TimeScreen/Capturer.swift" -lsqlite3
"$BIN" "$OUT" "$DAY"
