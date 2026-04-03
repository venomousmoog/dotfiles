#!/usr/bin/env bash

# Use the same binary that started this server, so dev builds work.
TMUX_BIN="$(readlink /proc/$(echo "$TMUX" | cut -d, -f2)/exe 2>/dev/null || command -v tmux)"

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value="$($TMUX_BIN show-option -gqv "$option")"
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

update_theme() {
    # Get theme colors (allow customization)
    local bg_color=$(get_tmux_option "@minimal_theme_bg_color" "#1A1D23")
    local active_color=$(get_tmux_option "@minimal_theme_active_color" "#b4befe")
    local inactive_color=$(get_tmux_option "@minimal_theme_inactive_color" "#6c7086")
    local text_color=$(get_tmux_option "@minimal_theme_text_color" "#cdd6f4")
    local accent_color=$(get_tmux_option "@minimal_theme_accent_color" "#b4befe")
    local border_color=$(get_tmux_option "@minimal_theme_border_color" "#44475a")
    local icon_session=$(get_tmux_option "@minimal_theme_session_icon" "")
    local icon_dir=$(get_tmux_option "@minimal_theme_dir_icon" "")
    local icon_memory=$(get_tmux_option "@minimal_theme_memory_icon" "")
    local icon_date=$(get_tmux_option "@minimal_theme_date_icon" "")
    local icon_clock=$(get_tmux_option "@minimal_theme_clock_icon" "")
    local icon_battery=$(get_tmux_option "@minimal_theme_battery_icon" "")

    # Status bar setup
    # tmux set-option -g window-status-format '#[fg=$inactive_color,bg=$bg_color]#I:#{@claude}#W'
    # tmux set-option -g window-status-current-format '#[fg=$active_color,bg=$bg_color,bold] #I:#{@claude}#W'
    # tmux set-option -g window-status-separator '#[fg=$inactive_color,nobold] │ '
    $TMUX_BIN set-option -g status-interval 2
    $TMUX_BIN set-option -g window-status-format "#[fg=$inactive_color,bg=$bg_color]#I:#{@claude}#[italics]#{@temp_repo}#[noitalics]#W"
    $TMUX_BIN set-option -g window-status-current-format "#[fg=$active_color,bg=$bg_color,bold]#I:#{@claude}#[nobold,italics,fg=$inactive_color]#{@temp_repo}#[noitalics,bold,fg=$active_color]#W"
    $TMUX_BIN set-option -g window-status-separator '#[fg=#6c7086,nobold] │ '

    # status-left is now managed dynamically by claude_sessions.py

    # Status right: side-effect-only scripts (no visible output)
    # - sync_temp_repos: sets @temp_repo per-window for cloning dir display
    # - claude_sessions: cross-session status indicators
    # Note: window title sync is triggered by the Stop hook, not status-right
    $TMUX_BIN set-option -g status-right "#(~/src/dotfiles/tmux/sync_temp_repos.sh)#(python3 ~/src/dotfiles/tmux/claude_sessions.py)"

    # Bind ctrl-b w to show Claude icons in choose-tree view
    $TMUX_BIN bind-key w choose-tree -wf '#{?#{m:__tun_ctrl,#{session_name}},0,1}' -F "#{?#{session_format},#[bold]#{?#{@host},#{@host},#h}#[nobold],#{@claude}#[italics]#{@temp_repo}#[noitalics]#{window_name}#{window_flags}}"

    # Mouse click on secondary session status lines: switch to that session:window
    # User ranges in status-format[N] put the argument in #{mouse_status_range}
    # run-shell is needed because switch-client doesn't expand format variables
    # Gate on mouse_status_line != 0 so primary line clicks fall through to default
    $TMUX_BIN bind-key -n MouseDown1Status if-shell -F '#{!=:#{mouse_status_line},0}' \
        'run-shell "tmux switch-client -t \"#{mouse_status_range}\""' \
        'select-window -t ='
}

update_theme
