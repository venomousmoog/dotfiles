#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

xcrun swift-format format -i -r "$ROOT/Sources" "$ROOT/SelfTest" "$ROOT/Package.swift"
xcrun swift-format lint -r "$ROOT/Sources" "$ROOT/SelfTest" "$ROOT/Package.swift"
bash -n "$ROOT/build-app.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/test.sh"
plutil -lint "$ROOT/Info.plist"
"$ROOT/install.sh" --dry-run
swift run --disable-sandbox --package-path "$ROOT" DevReserveSelfTest --live
