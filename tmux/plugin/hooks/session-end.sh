#!/usr/bin/env bash
# tmux-statusline: SessionEnd hook
# Cleans up state file when Claude session ends.
# Also handles clown enlistment cleanup (commit, sync, prompt to remove).

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "SessionEnd hook started"

require_jq
read_hook_input

debug_log "SessionEnd: session=$SESSION_ID"

# --- Clown enlistment cleanup (runs before tmux code which may exit early) ---
CLONE_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
case "${CLONE_DIR:-}" in
    "$HOME/src/clown/"*)
        debug_log "SessionEnd: clown enlistment detected at $CLONE_DIR"
        CLOWN_SESSION_NAME=$(basename "$CLONE_DIR")
        WORKSPACE_FILE="$HOME/src/monster.code-workspace"

        if [ -d "$CLONE_DIR" ]; then
            cd "$CLONE_DIR" 2>/dev/null || true

            STATUS=$(sl status 2>/dev/null || true)
            if [ -n "$STATUS" ]; then
                debug_log "SessionEnd: committing uncommitted changes"
                sl addremove 2>/dev/null || true
                sl commit -m "[WIP] Uncommitted changes from claude session ${CLOWN_SESSION_NAME}" 2>/dev/null || true
            fi

            sl cloud sync 2>/dev/null || true

            cd "$HOME"

            RESPONSE="Y"
            if [ -e /dev/tty ]; then
                echo "" > /dev/tty
                echo "Session ${CLOWN_SESSION_NAME} finalized. Changes synced to commit cloud." > /dev/tty
                read -r -p "Remove clown enlistment ${CLONE_DIR}? [Y/n] " RESPONSE < /dev/tty 2>/dev/tty || true
                RESPONSE=${RESPONSE:-Y}
            fi

            if [[ "$RESPONSE" =~ ^[Yy] ]]; then
                if [ -f "$WORKSPACE_FILE" ] && command -v jq &>/dev/null; then
                    tmp=$(mktemp)
                    jq --arg path "$CLONE_DIR" '.folders |= map(select(.path != $path))' \
                        "$WORKSPACE_FILE" > "$tmp" && mv "$tmp" "$WORKSPACE_FILE"
                fi
                eden rm --yes "$CLONE_DIR" 2>/dev/null || rm -rf "$CLONE_DIR"
                debug_log "SessionEnd: clown enlistment removed"
                [ -e /dev/tty ] && echo "Enlistment removed." > /dev/tty
            else
                debug_log "SessionEnd: clown enlistment kept"
                [ -e /dev/tty ] && echo "Enlistment kept at ${CLONE_DIR}" > /dev/tty
            fi

            touch "/tmp/.clown-handled-${CLOWN_SESSION_NAME}" 2>/dev/null || true
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
