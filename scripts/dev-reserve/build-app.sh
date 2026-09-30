#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/dist/DevReserve.app"

swift build --disable-sandbox --package-path "$ROOT" -c "$CONFIGURATION" --product DevReserve
BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DevReserve" "$APP/Contents/MacOS/DevReserve"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$APP" >/dev/null

printf 'Built %s\n' "$APP"
