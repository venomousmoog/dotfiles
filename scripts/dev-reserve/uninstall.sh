#!/bin/bash
set -euo pipefail

APP_NAME="DevReserve"
APP="$HOME/Applications/$APP_NAME.app"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ $# -gt 0 ]]; then
    printf 'usage: %s [--dry-run]\n' "$0" >&2
    exit 2
fi

if $DRY_RUN; then
    printf 'Would unregister the login item and remove %s\n' "$APP"
    exit 0
fi

if [[ -x "$APP/Contents/MacOS/$APP_NAME" ]]; then
    if ! unregister_output=$(
        "$APP/Contents/MacOS/$APP_NAME" --unregister-login-item 2>&1
    ); then
        printf 'Warning: could not unregister the login item: %s\n' "$unregister_output" >&2
    fi
fi
osascript -e 'tell application id "com.ddriver.devreserve" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 25); do
    pgrep -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.2
done
if pgrep -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    printf 'DevReserve is still running. Quit it from the menu bar and rerun uninstall.sh.\n' >&2
    exit 1
fi
rm -rf "$APP"
printf 'Uninstalled %s\n' "$APP_NAME"
