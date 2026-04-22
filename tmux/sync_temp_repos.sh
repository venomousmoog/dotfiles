#!/bin/bash
# Sets @temp_repo per-window based on active pane's cwd.
# Called periodically from status-right. Produces no output.
TMUX_BIN="$(readlink /proc/$(echo "$TMUX" | cut -d, -f2)/exe 2>/dev/null || command -v tmux)"

while IFS= read -r line; do
    window_id="${line%%:*}"
    path="${line#*:}"
    case "$path" in
        */src/clown/*)
            rest="${path#*/src/clown/}"
            $TMUX_BIN set-option -wqt "$window_id" @temp_repo "${rest%%/*}:"
            ;;
        *)
            $TMUX_BIN set-option -wqut "$window_id" @temp_repo 2>/dev/null
            ;;
    esac
done < <($TMUX_BIN list-windows -a -F '#{window_id}:#{pane_current_path}')
