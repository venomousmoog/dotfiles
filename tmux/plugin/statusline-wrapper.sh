#!/bin/bash
# Wraps meta-statusline-pro and appends a "last response" age indicator.
# The Stop hook writes an epoch timestamp to /tmp/claude-last-response-<session_id>.

input=$(cat)

# Find the real statusline script
for p in \
    /usr/local/claude-templates-cli/components/plugins/meta-statusline-pro/bin/statusline.sh \
    /opt/facebook/claude-templates-cli/components/plugins/meta-statusline-pro/bin/statusline.sh \
    "$(find "$HOME/.claude/plugins" -path '*/meta-statusline-pro/*/bin/statusline.sh' 2>/dev/null | sort -V | tail -1)"; do
    [ -f "$p" ] && { REAL_SCRIPT="$p"; break; }
done

if [ -z "$REAL_SCRIPT" ]; then
    echo "statusline-wrapper: meta-statusline-pro not found" >&2
    exit 1
fi

output=$(echo "$input" | bash "$REAL_SCRIPT")

# Derive session ID from transcript path
session_id=$(echo "$input" | jq -r '.transcript_path // empty' | xargs -I{} basename {} .jsonl 2>/dev/null)
ts_file="/tmp/claude-last-response-${session_id}"

if [ -n "$session_id" ] && [ -f "$ts_file" ]; then
    ts=$(cat "$ts_file")
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        now=$(date +%s)
        diff=$((now - ts))
        if [ $diff -lt 0 ]; then
            age="just now"
        elif [ $diff -lt 60 ]; then
            age="${diff}s ago"
        elif [ $diff -lt 3600 ]; then
            age="$((diff / 60))m ago"
        else
            age="$((diff / 3600))h $((diff % 3600 / 60))m ago"
        fi

        DIM='\033[2m'
        RESET='\033[0m'
        suffix="${DIM}@ ${age}${RESET}"

        # Append to the last line of output
        last_line=$(echo "$output" | tail -1)
        prefix=$(echo "$output" | head -n -1)
        if [ -n "$prefix" ]; then
            echo "$prefix"
        fi
        echo -e "${last_line} | ${suffix}"
        exit 0
    fi
fi

echo "$output"
