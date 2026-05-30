#!/bin/bash
# AC shell tab launcher — discovers the agent running in $PWD and
# attaches to (or creates) a tmux session named after it.
#
# Set as the custom shell command in AC Settings → UI → Linux shell → Custom:
#   ~/src/dotfiles/scripts/ac-shell.sh
#
# Behavior:
#   1. Queries `acd agent list` for an alive agent whose fbclonePath matches $PWD
#   2. Uses that agent's name as the tmux session name
#   3. Attaches to an existing tmux session with that name, or creates one
#   4. Falls back to a plain interactive shell if acd isn't available

set -euo pipefail

discover_agent_name() {
    command -v acd &>/dev/null || return 1
    acd agent list --json 2>/dev/null \
        | jq -r --arg cwd "$PWD" '
            [.hosts[].agents[]
             | select(.alive)
             | select(.fbclonePath == $cwd or (.fbclonePath != null and ($cwd | startswith(.fbclonePath))))]
            | sort_by(.fbclonePath | length) | reverse
            | .[0]
            | .name // .ptyId // empty
        ' 2>/dev/null
}

AGENT_NAME=$(discover_agent_name || true)

if [[ -z "$AGENT_NAME" ]]; then
    # No agent found — fall back to a plain shell
    exec "${SHELL:-/bin/bash}" -i
fi

exec tmux new-session -As "$AGENT_NAME"
