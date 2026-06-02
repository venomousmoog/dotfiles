#!/usr/bin/env bash
# tmux-statusline: SessionEnd hook
# Cleans up state file when Claude session ends.
# Also preserves clown enlistment work (commit + cloud sync).

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "SessionEnd hook started"

require_jq
read_hook_input

debug_log "SessionEnd: session=$SESSION_ID"

# --- Clown enlistment: preserve work (commit + cloud sync, no deletion) ---
CLONE_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
case "${CLONE_DIR:-}" in
    "$HOME/src/clown/"*)
        debug_log "SessionEnd: clown enlistment detected at $CLONE_DIR"
        CLOWN_SESSION_NAME=$(basename "$CLONE_DIR")

        if [ -d "$CLONE_DIR" ]; then
            cd "$CLONE_DIR" 2>/dev/null || true

            STATUS=$(sl status 2>/dev/null || true)
            if [ -n "$STATUS" ]; then
                debug_log "SessionEnd: committing uncommitted changes"
                sl addremove 2>/dev/null || true
                sl commit -m "[WIP] Uncommitted changes from claude session ${CLOWN_SESSION_NAME}" 2>/dev/null || true
            fi

            sl cloud sync 2>/dev/null || true
            debug_log "SessionEnd: clown enlistment synced to commit cloud"

            cd "$HOME"
        fi
        ;;
esac

# --- tmux state cleanup ---
if [ -z "${TMUX:-}" ]; then
    debug_log "  Not in tmux, skipping tmux cleanup"
    exit 0
fi

debug_log "  TMUX_PANE=${TMUX_PANE:-} TMUX=${TMUX:-}"

resolve_tmux_pane
get_tmux_env

rm -f "$STATE_FILE" "$ACK_FILE"

if [ -n "$TMUX_PANE" ]; then
    tmux set-option -w -t "$TMUX_PANE" automatic-rename on 2>/dev/null
    tmux set-option -wut "$TMUX_PANE" @title_source 2>/dev/null
fi

exit 0
