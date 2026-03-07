#!/usr/bin/env bash
# tmux-statusline: UserPromptSubmit hook
# Updates state to "working" when user submits a prompt

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

resolve_tmux_pane
require_jq
read_hook_input

debug_log "UserPromptSubmit: session=$SESSION_ID"

get_tmux_env

JSON=$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg pane_id "$TMUX_PANE" \
  --argjson tmux_pid "$TMUX_PID" \
  --arg tmux_session "$TMUX_SESSION" \
  --arg status "working" \
  --arg status_since "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{
    session_id: $session_id,
    pane_id: $pane_id,
    tmux_pid: $tmux_pid,
    tmux_session: $tmux_session,
    status: $status,
    status_since: $status_since,
    current_tool: null
  }')

write_state "$JSON"
rm -f "$ACK_FILE"

exit 0
