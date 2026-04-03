#!/usr/bin/env bash
# tmux-statusline: Stop hook
# Updates state to "waiting" when Claude stops and needs input

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "Stop hook started"
debug_log "  TMUX_PANE=$TMUX_PANE"

resolve_tmux_pane
require_jq
read_hook_input

debug_log "  SESSION_ID=$SESSION_ID"

get_tmux_env

JSON=$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg pane_id "$TMUX_PANE" \
  --argjson tmux_pid "$TMUX_PID" \
  --arg tmux_session "$TMUX_SESSION" \
  --arg status "waiting" \
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

# Launch window title sync in the background (haiku call while API is idle)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
debug_log "  Title sync: SESSION_ID=$SESSION_ID CWD=$CWD TMUX_PANE=$TMUX_PANE"
if [ -n "$SESSION_ID" ] && [ -n "$TMUX_PANE" ]; then
    debug_log "  Title sync: launching sync_window_titles.py"
    nohup python3 ~/src/dotfiles/tmux/sync_window_titles.py \
        "$SESSION_ID" "$TMUX_PANE" "$CWD" \
        </dev/null >>~/.claude-tmux-statusline/debug.log 2>&1 &
    disown
else
    debug_log "  Title sync: skipped (missing SESSION_ID or TMUX_PANE)"
fi

exit 0
