#!/bin/bash
# Extracts the repo name (first dir component) under ~/src/temp/ from a path.
# Called by tmux window-status-format to show which temp repo a pane is in.
# Outputs nothing if the path is not under ~/src/temp/.
case "$1" in
    */src/temp/*)
        rest="${1#*/src/temp/}"
        printf '%s:' "${rest%%/*}"
        ;;
esac
