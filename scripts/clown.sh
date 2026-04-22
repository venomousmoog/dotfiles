#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Launches Claude Code in a fresh clone. On exit, ensures all changes are
# committed and synced to commit cloud, then prompts to remove the enlistment.
#
# Usage:
#   clown.sh [options] <repo> [-- claude args...]
#   clown.sh -i fbsource             # interactive in new tmux window
#   clown.sh -i --no-tmux configerator  # interactive, no tmux
#   clown.sh -b fbsource -p "do X"   # background via dashboard
#   clown.sh --clean                  # remove inactive clones from ~/src/clown

set -euo pipefail

TEMP_BASE="$HOME/src/clown"
WORKSPACE_FILE="$HOME/src/monster.code-workspace"

# --- Workspace file helpers ---
add_to_workspace() {
    local dir="$1"
    command -v jq &>/dev/null || return 0
    if [[ ! -f "$WORKSPACE_FILE" ]]; then
        mkdir -p "$(dirname "$WORKSPACE_FILE")"
        echo '{"folders": []}' > "$WORKSPACE_FILE"
        echo "Created workspace file ${WORKSPACE_FILE}."
    fi
    local tmp
    tmp=$(mktemp)
    jq --arg path "$dir" '.folders += [{"path": $path}]' "$WORKSPACE_FILE" > "$tmp" && mv "$tmp" "$WORKSPACE_FILE"
    echo "Added ${dir} to workspace."
}

remove_from_workspace() {
    local dir="$1"
    if [[ -f "$WORKSPACE_FILE" ]] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg path "$dir" '.folders |= map(select(.path != $path))' "$WORKSPACE_FILE" > "$tmp" && mv "$tmp" "$WORKSPACE_FILE"
    fi
}

# --- Clean mode: remove inactive clones ---
clean_clones() {
    mkdir -p "$TEMP_BASE"
    local removed=0
    local kept=0
    local total=0

    echo "Scanning ${TEMP_BASE} for inactive clones..."
    echo ""

    for dir in "${TEMP_BASE}"/*/; do
        [[ -d "$dir" ]] || continue
        total=$((total + 1))
        local name
        name=$(basename "$dir")
        local real_dir
        real_dir=$(realpath "$dir")

        # Check if any claude process has this directory as its cwd
        local active=false
        while IFS= read -r pid; do
            [[ -n "$pid" ]] || continue
            local proc_cwd
            proc_cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)
            if [[ "$proc_cwd" == "$real_dir" || "$proc_cwd" == "${real_dir}/"* ]]; then
                active=true
                break
            fi
        done < <(pgrep -f "claude" 2>/dev/null || true)

        if [[ "$active" == true ]]; then
            echo "  ACTIVE  ${name}  (claude process using ${dir})"
            kept=$((kept + 1))
        else
            echo "  INACTIVE  ${name}  — removing..."
            remove_from_workspace "${dir%/}"
            eden rm --yes "$dir" 2>/dev/null || rm -rf "$dir"
            removed=$((removed + 1))
        fi
    done

    echo ""
    echo "Done. ${removed} removed, ${kept} kept (${total} total)."
    exit 0
}

# --- Parse options ---
MODE="interactive"
USE_TMUX=true
REPO_TYPE=""
CLAUDE_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            clean_clones
            ;;
        -b|--background|-bg)
            MODE="background"
            shift
            ;;
        -i|--interactive)
            MODE="interactive"
            shift
            ;;
        --no-tmux)
            USE_TMUX=false
            shift
            ;;
        fbsource|fbs|f)
            REPO_TYPE="fbsource"
            shift
            ;;
        configerator|config|c)
            REPO_TYPE="configerator"
            shift
            ;;
        --)
            shift
            CLAUDE_ARGS+=("$@")
            break
            ;;
        -h|--help)
            echo "Usage: $0 [options] <repo> [-- claude args...]"
            echo ""
            echo "Repos: fbsource (f/fbs), configerator (c/config)"
            echo ""
            echo "Options:"
            echo "  -i, --interactive   Interactive Claude session (default)"
            echo "  -b, --background    Background session via dashboard"
            echo "  --no-tmux           Don't create a new tmux window (interactive only)"
            echo "  --clean             Remove inactive clones from ~/src/clown"
            echo ""
            echo "Extra args after -- are passed to claude/claude_wrapper."
            exit 0
            ;;
        *)
            CLAUDE_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$REPO_TYPE" ]]; then
    echo "Error: specify a repo: fbsource (f) or configerator (c)"
    echo "Run $0 --help for usage."
    exit 1
fi

PREFIX="${REPO_TYPE:0:1}"
mkdir -p "$TEMP_BASE"

# Find next available slot (f1, f2, ... or c1, c2, ...)
N=1
while [[ -d "${TEMP_BASE}/${PREFIX}${N}" ]]; do
    N=$((N + 1))
done
CLONE_DIR="${TEMP_BASE}/${PREFIX}${N}"
SESSION_NAME="${PREFIX}${N}"

# --- Finalize function (used by non-tmux modes and embedded in tmux wrapper) ---
finalize() {
    echo ""
    echo "Finalizing session ${SESSION_NAME}..."

    if [[ ! -d "$CLONE_DIR" ]]; then
        echo "Clone directory gone, nothing to finalize."
        return
    fi

    cd "$CLONE_DIR"

    # Check for uncommitted changes
    local status
    status=$(sl status --reason "check uncommitted changes | sl help status" 2>/dev/null || true)

    if [[ -n "$status" ]]; then
        echo "Uncommitted changes detected, creating placeholder commit..."
        sl addremove --reason "track new files before placeholder commit | sl help addremove" 2>/dev/null || true
        sl commit --reason "placeholder commit for cloud sync | sl help commit" \
            -m "[WIP] Uncommitted changes from claude session ${SESSION_NAME}" 2>/dev/null || true
    fi

    echo "Syncing to commit cloud..."
    sl cloud sync --reason "sync work to commit cloud | sl help cloud" 2>/dev/null || true

    echo ""
    echo "Session ${SESSION_NAME} finalized."

    # Prompt to remove the enlistment (default: remove)
    cd "$HOME"
    local response
    if [[ -t 0 ]]; then
        read -r -p "Remove enlistment ${CLONE_DIR}? [Y/n] " response
        response=${response:-Y}
    else
        response="Y"
    fi

    if [[ "$response" =~ ^[Yy] ]]; then
        remove_from_workspace "$CLONE_DIR"
        eden rm  --yes "$CLONE_DIR" 2>/dev/null || rm -rf "$CLONE_DIR"
        echo "Enlistment removed."
    else
        echo "Enlistment kept at ${CLONE_DIR}"
    fi
}

# --- Launch ---
if [[ "$USE_TMUX" == true && -n "${TMUX:-}" && "$MODE" == "interactive" ]]; then
    # Interactive tmux mode: open window immediately so caller's terminal is free.
    # The wrapper handles fbclone + claude + finalize entirely in the new window.
    WRAPPER="/tmp/claude_session_wrapper_${SESSION_NAME}.sh"

    # Serialize CLAUDE_ARGS with proper quoting for the wrapper script
    QUOTED_ARGS=""
    for arg in "${CLAUDE_ARGS[@]:+${CLAUDE_ARGS[@]}}"; do
        escaped=$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")
        QUOTED_ARGS="${QUOTED_ARGS} '${escaped}'"
    done

    cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
set -euo pipefail

CLONE_DIR="${CLONE_DIR}"
SESSION_NAME="${SESSION_NAME}"
REPO_TYPE="${REPO_TYPE}"
WORKSPACE_FILE="${WORKSPACE_FILE}"

add_to_workspace() {
    local dir="\$1"
    command -v jq &>/dev/null || return 0
    if [[ ! -f "\$WORKSPACE_FILE" ]]; then
        mkdir -p "\$(dirname "\$WORKSPACE_FILE")"
        echo '{"folders": []}' > "\$WORKSPACE_FILE"
        echo "Created workspace file \${WORKSPACE_FILE}."
    fi
    local tmp
    tmp=\$(mktemp)
    jq --arg path "\$dir" '.folders += [{"path": \$path}]' "\$WORKSPACE_FILE" > "\$tmp" && mv "\$tmp" "\$WORKSPACE_FILE"
    echo "Added \${dir} to workspace."
}

remove_from_workspace() {
    local dir="\$1"
    if [[ -f "\$WORKSPACE_FILE" ]] && command -v jq &>/dev/null; then
        local tmp
        tmp=\$(mktemp)
        jq --arg path "\$dir" '.folders |= map(select(.path != \$path))' "\$WORKSPACE_FILE" > "\$tmp" && mv "\$tmp" "\$WORKSPACE_FILE"
    fi
}

finalize() {
    echo ""
    echo "Finalizing session \${SESSION_NAME}..."
    if [[ ! -d "\$CLONE_DIR" ]]; then
        echo "Clone directory gone, nothing to finalize."
        return
    fi
    cd "\$CLONE_DIR"
    local status
    status=\$(sl status --reason "check uncommitted changes | sl help status" 2>/dev/null || true)
    if [[ -n "\$status" ]]; then
        echo "Uncommitted changes detected, creating placeholder commit..."
        sl addremove --reason "track new files before placeholder commit | sl help addremove" 2>/dev/null || true
        sl commit --reason "placeholder commit for cloud sync | sl help commit" \
            -m "[WIP] Uncommitted changes from claude session \${SESSION_NAME}" 2>/dev/null || true
    fi
    echo "Syncing to commit cloud..."
    sl cloud sync --reason "sync work to commit cloud | sl help cloud" 2>/dev/null || true
    echo ""
    echo "Session \${SESSION_NAME} finalized."

    # Prompt to remove the enlistment (default: remove)
    cd "\$HOME"
    local response
    if [[ -t 0 ]]; then
        read -r -p "Remove enlistment \${CLONE_DIR}? [Y/n] " response
        response=\${response:-Y}
    else
        response="Y"
    fi

    if [[ "\$response" =~ ^[Yy] ]]; then
        remove_from_workspace "\$CLONE_DIR"
        eden rm --yes "\$CLONE_DIR" 2>/dev/null || rm -rf "\$CLONE_DIR"
        echo "Enlistment removed."
    else
        echo "Enlistment kept at \${CLONE_DIR}"
    fi
}
trap finalize EXIT INT TERM

echo "Creating enlistment: fbclone \${REPO_TYPE} \${CLONE_DIR}"
fbclone "\${REPO_TYPE}" "\${CLONE_DIR}"
add_to_workspace "\${CLONE_DIR}"

cd "\$CLONE_DIR"
claude --dangerously-skip-permissions --dangerously-enable-internet-mode${QUOTED_ARGS}
WRAPPER_EOF
    chmod +x "$WRAPPER"

    # Reserve the directory name so the next clown.sh call picks a different slot
    mkdir -p "$CLONE_DIR"

    tmux new-window -n "${SESSION_NAME}" "$WRAPPER"
    echo "Session ${SESSION_NAME} launched in tmux window '${SESSION_NAME}'."
    echo "  Clone: ${CLONE_DIR}"

elif [[ "$MODE" == "background" ]]; then
    # Background mode: clone here, then launch claude_wrapper
    echo "Creating enlistment: fbclone $REPO_TYPE $CLONE_DIR"
    fbclone "$REPO_TYPE" "$CLONE_DIR"
    add_to_workspace "$CLONE_DIR"

    ARGS_FILE="/tmp/claude_session_args_${SESSION_NAME}.txt"
    cat > "$ARGS_FILE" <<EOF
--cwd
${CLONE_DIR}
--session-id
${SESSION_NAME}
EOF

    cleanup_args() {
        rm -f "$ARGS_FILE"
        finalize
    }
    trap cleanup_args EXIT INT TERM

    echo ""
    echo "Launching Claude in ${CLONE_DIR}"
    echo "  Session: ${SESSION_NAME}"
    echo "  Repo:    ${REPO_TYPE}"
    echo "  Mode:    background"
    echo ""

    buck2 run fbcode//scripts/sledesma/dmodel_claude/scripts:claude_wrapper -- \
        "${CLAUDE_ARGS[@]:+${CLAUDE_ARGS[@]}}" \
        "@${ARGS_FILE}"

else
    # Interactive mode in current terminal (--no-tmux or no tmux session)
    echo "Creating enlistment: fbclone $REPO_TYPE $CLONE_DIR"
    fbclone "$REPO_TYPE" "$CLONE_DIR"
    add_to_workspace "$CLONE_DIR"

    trap finalize EXIT INT TERM

    echo ""
    echo "Launching Claude in ${CLONE_DIR}"
    echo "  Session: ${SESSION_NAME}"
    echo "  Repo:    ${REPO_TYPE}"
    echo "  Mode:    interactive"
    echo ""

    cd "$CLONE_DIR"
    claude --dangerously-skip-permissions --dangerously-enable-internet-mode "${CLAUDE_ARGS[@]:+"${CLAUDE_ARGS[@]}"}"
fi
