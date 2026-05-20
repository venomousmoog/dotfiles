#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# SessionEnd hook for AC-managed clown sessions.
# Commits uncommitted changes, syncs to commit cloud, then removes the
# enlistment and its workspace entry.
#
# Receives hook input JSON on stdin with { session_id, cwd, ... }.

set -uo pipefail

WORKSPACE_FILE="$HOME/src/monster.code-workspace"

INPUT=$(cat)
CLONE_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

if [[ -z "$CLONE_DIR" || ! -d "$CLONE_DIR" ]]; then
    exit 0
fi

# Only act on clown-managed directories
case "$CLONE_DIR" in
    "$HOME/src/clown/"*) ;;
    *) exit 0 ;;
esac

cd "$CLONE_DIR"

STATUS=$(sl status 2>/dev/null || true)
if [[ -n "$STATUS" ]]; then
    sl addremove 2>/dev/null || true
    sl commit -m "[WIP] Uncommitted changes from AC session" 2>/dev/null || true
fi

sl cloud sync 2>/dev/null || true

# Remove workspace entry
if [[ -f "$WORKSPACE_FILE" ]] && command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --arg path "$CLONE_DIR" '.folders |= map(select(.path != $path))' \
        "$WORKSPACE_FILE" > "$tmp" && mv "$tmp" "$WORKSPACE_FILE"
fi

# Remove the enlistment
cd "$HOME"
eden rm --yes "$CLONE_DIR" 2>/dev/null || rm -rf "$CLONE_DIR"
