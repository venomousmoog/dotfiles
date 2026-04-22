#!/bin/bash
# Extracts the repo name (first dir component) under ~/src/clown/ from a path.
# Called by tmux window-status-format to show which temp repo a pane is in.
# Outputs nothing if the path is not under ~/src/clown/.
case "$1" in
    */src/clown/*)
        rest="${1#*/src/clown/}"
        printf '%s:' "${rest%%/*}"
        ;;
esac
