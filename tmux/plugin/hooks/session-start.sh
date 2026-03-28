#!/usr/bin/env bash
# tmux-statusline: SessionStart hook
# Creates state file when a Claude session starts

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "SessionStart hook started"
debug_log "  TMUX_PANE=$TMUX_PANE TMUX=$TMUX CLAUDE_SESSION_ID=$CLAUDE_SESSION_ID"

resolve_tmux_pane
require_jq
read_hook_input

SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
debug_log "  SESSION_ID=$SESSION_ID SOURCE=$SOURCE"

get_tmux_env

# Build state JSON
JSON=$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg pane_id "$TMUX_PANE" \
  --argjson tmux_pid "$TMUX_PID" \
  --arg tmux_session "$TMUX_SESSION" \
  --arg status "idle" \
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

# Override tmux default-command to bash for this window so agent subprocesses
# don't inherit nushell (which rejects && syntax in spawn commands)
if [ -n "$TMUX_PANE" ]; then
    tmux set-option -w -t "$TMUX_PANE" default-command "bash"
fi

# On resume, clean up stale state files from other sessions on this pane
if [ "$SOURCE" = "resume" ]; then
    for f in "$STATE_DIR"/*.json; do
        [ "$f" = "$STATE_FILE" ] && continue
        FILE_PANE=$(jq -r '.pane_id // empty' "$f" 2>/dev/null)
        if [ "$FILE_PANE" = "$TMUX_PANE" ]; then
            rm -f "$f" "${f%.json}.ack"
        fi
    done
fi

exit 0
