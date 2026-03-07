#!/usr/bin/env bash
# tmux-statusline: Notification hook
# Updates state to "waiting" when Claude is waiting for user input
# Handles: permission_prompt, elicitation_dialog, idle_prompt

# Skip hooks for myclaw background sessions
[[ "$SESSION_TYPE" == "myclaw" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$HOOK_DIR/_lib.sh"

debug_log "Notification hook started"
debug_log "  TMUX_PANE=$TMUX_PANE"

resolve_tmux_pane
require_jq
read_hook_input

NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')
debug_log "  SESSION_ID=$SESSION_ID, NOTIFICATION_TYPE=$NOTIFICATION_TYPE"

# Only handle waiting-for-input notification types
case "$NOTIFICATION_TYPE" in
    permission_prompt|elicitation_dialog|idle_prompt)
        debug_log "  Handling $NOTIFICATION_TYPE as waiting state"
        ;;
    *)
        debug_log "  Ignoring notification type: $NOTIFICATION_TYPE"
        exit 0
        ;;
esac

get_tmux_env

# Determine new status based on notification type and previous state
if [ "$NOTIFICATION_TYPE" = "idle_prompt" ] && [ -f "$STATE_FILE" ]; then
    PREV_STATUS=$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null)
    case "$PREV_STATUS" in
        working)
            NEW_STATUS="acknowledged"
            debug_log "  idle_prompt from working state -> acknowledged (user canceled)"
            ;;
        waiting|acknowledged|idle|"")
            NEW_STATUS="waiting"
            ;;
        *)
            NEW_STATUS="waiting"
            debug_log "  WARNING: Invalid previous status '$PREV_STATUS', treating as waiting"
            ;;
    esac
else
    NEW_STATUS="waiting"
fi

JSON=$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg pane_id "$TMUX_PANE" \
  --argjson tmux_pid "$TMUX_PID" \
  --arg tmux_session "$TMUX_SESSION" \
  --arg status "$NEW_STATUS" \
  --arg status_since "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg notification_type "$NOTIFICATION_TYPE" \
  '{
    session_id: $session_id,
    pane_id: $pane_id,
    tmux_pid: $tmux_pid,
    tmux_session: $tmux_session,
    status: $status,
    status_since: $status_since,
    current_tool: $notification_type
  }')

write_state "$JSON"

exit 0
