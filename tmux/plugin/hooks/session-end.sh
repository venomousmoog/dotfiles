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

# Restore tmux default-command to global setting (nushell)
if [ -n "$TMUX_PANE" ]; then
    tmux set-option -wu -t "$TMUX_PANE" default-command
fi

exit 0
