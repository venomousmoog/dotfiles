#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DevReserve"
APP_SOURCE="$ROOT/dist/$APP_NAME.app"
APP_DEST="$HOME/Applications/$APP_NAME.app"
LEGACY_LABEL="com.ddriver.devreserve"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ $# -gt 0 ]]; then
    printf 'usage: %s [--dry-run]\n' "$0" >&2
    exit 2
fi

"$ROOT/build-app.sh" release
codesign --verify --deep --strict "$APP_SOURCE"
plutil -lint "$APP_SOURCE/Contents/Info.plist" >/dev/null

if $DRY_RUN; then
    printf 'Would install %s to %s\n' "$APP_SOURCE" "$APP_DEST"
    printf 'The app registers itself with SMAppService on first launch.\n'
    exit 0
fi

mkdir -p "$HOME/Applications"
launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"

if pgrep -f "$APP_DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    osascript -e 'tell application id "com.ddriver.devreserve" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 25); do
        pgrep -f "$APP_DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.2
    done
fi
if pgrep -f "$APP_DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    printf 'DevReserve is still running. Quit it from the menu bar and rerun install.sh.\n' >&2
    exit 1
fi

rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

if ! launch_error=$(open -gj "$APP_DEST" 2>&1); then
    printf 'Could not launch DevReserve through LaunchServices: %s\n' "$launch_error" >&2
    exit 1
fi

for _ in $(seq 1 50); do
    if pgrep -f "$APP_DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        printf 'Installed and started %s\n' "$APP_DEST"
        printf 'Launch at login is managed by macOS SMAppService.\n'
        exit 0
    fi
    sleep 0.2
done

printf 'DevReserve did not start after installation.\n' >&2
exit 1
