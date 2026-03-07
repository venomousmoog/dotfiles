#!/usr/bin/env bash
# tmux-statusline: Shared hook library
# Sourced by all hook scripts to avoid boilerplate duplication.

# --- Debug logging ---
DEBUG_FLAG="$HOME/.claude-tmux-statusline/debug.enabled"
DEBUG_LOG="$HOME/.claude-tmux-statusline/debug.log"
debug_log() {
    if [ -f "$DEBUG_FLAG" ] || [ "$CLAUDE_TMUX_DEBUG" = "1" ]; then
        mkdir -p "$(dirname "$DEBUG_LOG")"
        echo "$(date): $*" >> "$DEBUG_LOG"
    fi
}

# --- Resolve TMUX_PANE via process tree walk ---
# Sets TMUX_PANE if not already set. Exits 0 if resolution fails.
resolve_tmux_pane() {
    if [ -n "$TMUX_PANE" ]; then
        return 0
    fi
    if [ -z "$TMUX" ]; then
        debug_log "  Exiting: not in tmux"
        exit 0
    fi
    _pane_pids=$(timeout 1 tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null)
    if [ -n "$_pane_pids" ]; then
        _pid=$$
        while [ "$_pid" -gt 1 ] 2>/dev/null; do
            _match=$(echo "$_pane_pids" | awk -v p="$_pid" '$1 == p {print $2}')
            if [ -n "$_match" ]; then
                TMUX_PANE="$_match"
                debug_log "  Got TMUX_PANE from proctree: $TMUX_PANE"
                break
            fi
            _pid=$(awk '{print $4}' /proc/$_pid/stat 2>/dev/null) || break
        done
    fi
    unset _pane_pids _pid _match
    if [ -z "$TMUX_PANE" ]; then
        debug_log "  Exiting: TMUX_PANE not set"
        exit 0
    fi
}

# --- Require jq ---
require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "tmux-statusline: jq required but not found" >&2
        exit 0  # Don't block Claude
    fi
}

# --- Read hook input from stdin and extract SESSION_ID ---
# Sets INPUT and SESSION_ID. Exits 0 if SESSION_ID is empty.
read_hook_input() {
    INPUT=$(cat)
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
    if [ -z "$SESSION_ID" ]; then
        debug_log "  Exiting: SESSION_ID empty"
        exit 0
    fi
}

# --- Get tmux environment and derive state paths ---
# Sets TMUX_PID, TMUX_SESSION, STATE_DIR, STATE_FILE, ACK_FILE.
# Exits 0 if tmux is unavailable or PID is invalid.
get_tmux_env() {
    TMUX_PID=$(timeout 1 tmux display-message -p '#{pid}' 2>/dev/null) || exit 0
    TMUX_SESSION=$(timeout 1 tmux display-message -p '#{session_name}' 2>/dev/null) || exit 0
    [[ ! "$TMUX_PID" =~ ^[0-9]+$ ]] && exit 0
    STATE_DIR="$HOME/.claude-tmux-statusline/state/$TMUX_PID"
    mkdir -p "$STATE_DIR"
    STATE_FILE="$STATE_DIR/${SESSION_ID}.json"
    ACK_FILE="$STATE_DIR/${SESSION_ID}.ack"
}

# --- Atomic state write ---
# Writes JSON to STATE_FILE via tmp+mv for atomicity.
write_state() {
    local json="$1"
    local tmp="${STATE_FILE}.tmp.$$"
    echo "$json" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}
