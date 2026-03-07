#!/usr/bin/env bash
# tmux-statusline: PreToolUse hook
# Updates state to "working" when Claude uses a tool

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "PreToolUse hook started"
debug_log "  TMUX_PANE=$TMUX_PANE TMUX=$TMUX"

resolve_tmux_pane
require_jq
read_hook_input

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
debug_log "PreToolUse: $TOOL_NAME (session=$SESSION_ID)"

# AskUserQuestion means we're waiting for user input, not working
if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
    STATUS="waiting"
else
    STATUS="working"
fi

get_tmux_env

# Build JSON with optional tool_name
if [ -n "$TOOL_NAME" ]; then
    JSON=$(jq -n \
      --arg session_id "$SESSION_ID" \
      --arg pane_id "$TMUX_PANE" \
      --argjson tmux_pid "$TMUX_PID" \
      --arg tmux_session "$TMUX_SESSION" \
      --arg status "$STATUS" \
      --arg status_since "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg current_tool "$TOOL_NAME" \
      '{
        session_id: $session_id,
        pane_id: $pane_id,
        tmux_pid: $tmux_pid,
        tmux_session: $tmux_session,
        status: $status,
        status_since: $status_since,
        current_tool: $current_tool
      }')
else
    JSON=$(jq -n \
      --arg session_id "$SESSION_ID" \
      --arg pane_id "$TMUX_PANE" \
      --argjson tmux_pid "$TMUX_PID" \
      --arg tmux_session "$TMUX_SESSION" \
      --arg status "$STATUS" \
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
fi

write_state "$JSON"

# Delete ack file only if agent is working again (not for waiting states)
if [ "$STATUS" = "working" ]; then
    rm -f "$ACK_FILE"
fi

exit 0
