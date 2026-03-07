#!/usr/bin/env bash

# Tunnel-aware theme setup — uses claude_sessions_v2.py.
# To activate: source ~/src/dotfiles/tmux/update_theme_v2.sh
# To revert:   source ~/src/dotfiles/tmux/update_theme.sh

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
    local bg_color=$(get_tmux_option "@minimal_theme_bg_color" "#1A1D23")
    local active_color=$(get_tmux_option "@minimal_theme_active_color" "#b4befe")
    local inactive_color=$(get_tmux_option "@minimal_theme_inactive_color" "#6c7086")

    $TMUX_BIN set-option -g status-interval 2
    $TMUX_BIN set-option -g window-status-format "#[fg=$inactive_color,bg=$bg_color]#I:#{@claude}#W"
    $TMUX_BIN set-option -g window-status-current-format "#[fg=$active_color,bg=$bg_color,bold]#I:#{@claude}#W"
    $TMUX_BIN set-option -g window-status-separator '#[fg=#6c7086,nobold] │ '

    # Use the tunnel-aware v2 script
    $TMUX_BIN set-option -g status-right "#(python3 ~/src/dotfiles/tmux/claude_sessions_v2.py)"

    $TMUX_BIN bind-key w choose-tree -wf '#{?#{m:__tun_ctrl,#{session_name}},0,1}' -F "#{?#{session_format},#[bold]#{?#{@host},#{@host},#h}#[nobold],#{window_index}:#{@claude}#{window_name}#{window_flags}}"

    $TMUX_BIN bind-key -n MouseDown1Status if-shell -F '#{!=:#{mouse_status_line},0}' \
        'run-shell "tmux switch-client -t \"#{mouse_status_range}\""' \
        'select-window -t ='
}

update_theme
