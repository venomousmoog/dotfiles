#!/usr/bin/env bash
# tmux-statusline: SessionEnd hook
# Cleans up state file when Claude session ends

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "SessionEnd hook started"
debug_log "  TMUX_PANE=$TMUX_PANE TMUX=$TMUX"

resolve_tmux_pane
require_jq
read_hook_input

debug_log "SessionEnd: session=$SESSION_ID"

get_tmux_env

rm -f "$STATE_FILE" "$ACK_FILE"

# Reset window title to automatic-rename so the shell manages it again
if [ -n "$TMUX_PANE" ]; then
    tmux set-option -w -t "$TMUX_PANE" automatic-rename on 2>/dev/null
    tmux set-option -wut "$TMUX_PANE" @title_source 2>/dev/null
fi

exit 0
