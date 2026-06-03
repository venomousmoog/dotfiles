#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Launches Claude Code in a fresh clone. On exit, ensures all changes are
# committed and synced to commit cloud. Use --clean to remove inactive clones.
#
# Usage:
#   clown.sh [options] <repo> [-- claude args...]
#   clown.sh -i fbsource             # interactive in new tmux window
#   clown.sh -i --no-tmux configerator  # interactive, no tmux
#   clown.sh -b fbsource -p "do X"   # background via dashboard
#   clown.sh --ac fbsource            # AC-managed agent (opus)
#   clown.sh --clean                  # remove inactive clones from ~/src/clown
#   clown.sh --clean --dry-run         # preview what --clean would remove

set -euo pipefail

TEMP_BASE="$HOME/src/clown"
WORKSPACE_FILE="$HOME/src/monster.code-workspace"
MARKDOWN_STYLES_SRC="$HOME/src/dotfiles/docs/markdown-styles.css"

# --- Workspace file helpers ---
prune_dead_workspace_paths() {
    [[ -f "$WORKSPACE_FILE" ]] || return 0
    command -v jq &>/dev/null || return 0
    local folders dead=() path tmp
    folders=$(jq -r '.folders[].path' "$WORKSPACE_FILE" 2>/dev/null || true)
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ -e "$path" ]] || dead+=("$path")
    done <<< "$folders"
    [[ ${#dead[@]} -eq 0 ]] && return 0
    tmp=$(mktemp)
    jq --argjson dead "$(printf '%s\n' "${dead[@]}" | jq -R . | jq -s .)" \
        '.folders |= map(select(.path as $p | $dead | index($p) | not))' \
        "$WORKSPACE_FILE" > "$tmp" && mv "$tmp" "$WORKSPACE_FILE"
    echo "Pruned ${#dead[@]} dead path(s) from workspace."
}

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
    prune_dead_workspace_paths
}

remove_from_workspace() {
    local dir="$1"
    if [[ -f "$WORKSPACE_FILE" ]] && command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg path "$dir" '.folders |= map(select(.path != $path))' "$WORKSPACE_FILE" > "$tmp" && mv "$tmp" "$WORKSPACE_FILE"
    fi
    prune_dead_workspace_paths
}

# Seed a fresh clone with .vscode/markdown-styles.css copied from dotfiles.
seed_vscode_markdown_styles() {
    local dir="$1"
    [[ -f "$MARKDOWN_STYLES_SRC" ]] || return 0
    mkdir -p "${dir}/.vscode"
    cp "$MARKDOWN_STYLES_SRC" "${dir}/.vscode/markdown-styles.css"
}

# --- Agent name generator for AC mode ---
generate_agent_name() {
    local adjectives=(
        cosmic blazing sneaky fuzzy turbo
        mighty phantom groovy wicked stellar
        atomic nimble fierce quirky radical
        jolly mystic dapper witty crafty
    )
    local nouns=(
        kraken phoenix yeti dragon panda
        falcon narwhal badger wizard goblin
        sphinx manticore griffin chimera hydra
        raven jackal panther condor viper
    )
    local adj=${adjectives[$((RANDOM % ${#adjectives[@]}))]}
    local noun=${nouns[$((RANDOM % ${#nouns[@]}))]}
    echo "${adj}-${noun}"
}

# --- Clone activity detection ---
# Populates _AC_PATHS cache on first call. Checks claude processes, session
# wrappers, and AC agents. Returns 0 (active) or 1 (inactive).
_AC_PATHS_CACHED=""
_AC_PATHS_LOADED=false
_load_ac_paths() {
    if [[ "$_AC_PATHS_LOADED" == true ]]; then return; fi
    _AC_PATHS_LOADED=true
    if command -v acd &>/dev/null; then
        _AC_PATHS_CACHED=$(acd agent list --json 2>/dev/null \
            | jq -r '.hosts[].agents[] | select(.alive) | .fbclonePath // empty' 2>/dev/null \
            || true)
    fi
}

is_clone_active() {
    local dir="$1"
    local name
    name=$(basename "$dir")
    local real_dir
    real_dir=$(realpath "$dir")

    # Check if any claude process has this directory as its cwd
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        local proc_cwd
        proc_cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)
        if [[ "$proc_cwd" == "$real_dir" || "$proc_cwd" == "${real_dir}/"* ]]; then
            return 0
        fi
    done < <(pgrep -f "claude" 2>/dev/null || true)

    # Check if the session wrapper script is still running
    if pgrep -f "claude_session_wrapper_${name}[.]sh" &>/dev/null; then
        return 0
    fi

    # Check if an AC agent is using this clone
    _load_ac_paths
    if [[ -n "$_AC_PATHS_CACHED" ]]; then
        while IFS= read -r ac_path; do
            [[ -n "$ac_path" ]] || continue
            if [[ "$ac_path" == "$real_dir" ]]; then
                return 0
            fi
        done <<< "$_AC_PATHS_CACHED"
    fi

    return 1
}

# --- Clean mode: remove inactive clones ---
clean_clones() {
    local dry_run="${1:-false}"
    mkdir -p "$TEMP_BASE"
    local removed=0
    local kept=0
    local total=0

    if [[ "$dry_run" == true ]]; then
        echo "Scanning ${TEMP_BASE} for inactive clones (dry run)..."
    else
        echo "Scanning ${TEMP_BASE} for inactive clones..."
    fi
    echo ""

    for dir in "${TEMP_BASE}"/*/; do
        [[ -d "$dir" ]] || continue
        total=$((total + 1))
        local name
        name=$(basename "$dir")

        if is_clone_active "$dir"; then
            echo "  ACTIVE    ${name}"
            kept=$((kept + 1))
        else
            if [[ "$dry_run" == true ]]; then
                echo "  INACTIVE  ${name}  — would remove"
            else
                echo "  INACTIVE  ${name}  — removing..."
                remove_from_workspace "${dir%/}"
                eden rm --yes "$dir" 2>/dev/null || rm -rf "$dir"
            fi
            removed=$((removed + 1))
        fi
    done

    echo ""
    if [[ "$dry_run" == true ]]; then
        echo "Dry run: ${removed} would be removed, ${kept} active (${total} total)."
    else
        echo "Done. ${removed} removed, ${kept} kept (${total} total)."
    fi
    exit 0
}

# --- Find or create a clone directory ---
# Looks for an inactive clone with the given prefix to reuse. If none found,
# picks the next available slot number. Sets CLONE_DIR, SESSION_NAME, and
# REUSE_CLONE (true/false).
find_clone_slot() {
    local prefix="$1"
    REUSE_CLONE=false

    # Load eden mount states once for the scan
    local eden_json=""
    eden_json=$(eden list --json 2>/dev/null || true)

    # Scan for an existing inactive clone we can reuse
    for dir in "${TEMP_BASE}/${prefix}"*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        # Only match our prefix+number pattern (e.g. f1, f2, c1)
        [[ "$name" =~ ^${prefix}[0-9]+$ ]] || continue
        if ! is_clone_active "$dir"; then
            # Verify the eden mount is healthy before reusing
            if [[ -n "$eden_json" ]]; then
                local real_path
                real_path=$(realpath "${dir%/}")
                local eden_state
                eden_state=$(echo "$eden_json" | jq -r --arg p "$real_path" '.[$p].state // empty' 2>/dev/null || true)
                if [[ "$eden_state" != "RUNNING" ]]; then
                    echo "Skipping ${name}: eden mount not healthy (state=${eden_state:-missing})"
                    continue
                fi
            fi
            CLONE_DIR="${dir%/}"
            SESSION_NAME="$name"
            REUSE_CLONE=true
            return
        fi
    done

    # No reusable clone found — pick next available slot
    local n=1
    while [[ -d "${TEMP_BASE}/${prefix}${n}" ]]; do
        n=$((n + 1))
    done
    CLONE_DIR="${TEMP_BASE}/${prefix}${n}"
    SESSION_NAME="${prefix}${n}"
}

# --- Prepare a clone directory (reuse or create fresh) ---
prepare_clone() {
    if [[ "$REUSE_CLONE" == true ]]; then
        echo "Reusing inactive clone: ${CLONE_DIR}"
        cd "$CLONE_DIR"

        local status
        status=$(sl status --reason "check uncommitted changes before reuse | sl help status" 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            echo "Saving uncommitted changes from previous session..."
            sl addremove --reason "track new files before saving | sl help addremove" 2>/dev/null || true
            sl commit --reason "save previous session work | sl help commit" \
                -m "[WIP] Uncommitted changes saved before clone reuse" 2>/dev/null || true
            sl cloud sync --reason "sync saved work to commit cloud | sl help cloud" 2>/dev/null || true
        fi

        sl pull --reason "pull latest before checkout | sl help pull" 2>/dev/null || true
        sl checkout remote/fbcode/stable --reason "reset to stable for new session | sl help checkout" 2>/dev/null || true
        cd - >/dev/null
    else
        echo "Creating enlistment: fbclone $REPO_TYPE $CLONE_DIR"
        fbclone "$REPO_TYPE" "$CLONE_DIR"
    fi
    seed_vscode_markdown_styles "$CLONE_DIR"
    add_to_workspace "$CLONE_DIR"
}

# --- Parse options ---
MODE="interactive"
USE_TMUX=true
USE_AC=false
REPO_TYPE=""
CLAUDE_ARGS=()

CLEAN_DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            shift
            if [[ "${1:-}" == "--dry-run" ]]; then
                CLEAN_DRY_RUN=true
                shift
            fi
            clean_clones "$CLEAN_DRY_RUN"
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
        --ac)
            USE_AC=true
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
            echo "  --ac                Use Agent Conductor to manage the agent (opus model)"
            echo "  --no-tmux           Don't create a new tmux window (interactive only)"
            echo "  --clean             Remove inactive clones from ~/src/clown"
            echo "  --clean --dry-run   Show what --clean would do without removing"
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

find_clone_slot "$PREFIX"

# --- Finalize function (used by non-tmux modes and embedded in tmux wrapper) ---
# Commits uncommitted changes and syncs to commit cloud.
# Enlistment removal is handled separately via `clown.sh --clean`.
finalize() {
    echo ""
    echo "Finalizing session ${SESSION_NAME}..."

    if [[ ! -d "$CLONE_DIR" ]]; then
        echo "Clone directory gone, nothing to finalize."
        return
    fi

    cd "$CLONE_DIR"

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
    echo "Session ${SESSION_NAME} finalized. Run 'clown.sh --clean' to remove inactive clones."
}

# --- Launch ---
if [[ "$USE_AC" == true ]]; then
    # AC mode: prepare clone, then hand off to Agent Conductor
    prepare_clone

    AGENT_NAME=$(generate_agent_name)

    echo ""
    echo "Launching AC agent '${AGENT_NAME}' in ${CLONE_DIR}"
    echo "  Repo:  ${REPO_TYPE}"
    echo "  Model: claude-opus-4-8[1m]"
    echo ""

    acd agent create \
        --mode claude \
        --model opus \
        --dir "$CLONE_DIR" \
        --name "$AGENT_NAME" \
        --fbclone-path "$CLONE_DIR" \
        --skip-permissions=true \
        --env "META_CLAUDE_USE_GCP_DIRECT=1" \
        --env "META_CLAUDE_CODE_NATIVE_BIN=1" \
        --env "NODE_OPTIONS=--max-old-space-size=32768" \
        --env "META_CLAUDE_CODE_RELEASE=latest" \
        --env "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" \
        -- --dangerously-skip-permissions --dangerously-enable-internet-mode \
           --model "claude-opus-4-8[1m]" --effort max \
           "${CLAUDE_ARGS[@]:+"${CLAUDE_ARGS[@]}"}"

    echo ""
    echo "Agent '${AGENT_NAME}' created."
    echo "  acd agent show ${AGENT_NAME}"
    echo "  acd agent output -f ${AGENT_NAME}"
    echo "  acd agent prompt ${AGENT_NAME} \"your message\""

elif [[ "$USE_TMUX" == true && -n "${TMUX:-}" && "$MODE" == "interactive" ]]; then
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
REUSE_CLONE="${REUSE_CLONE}"
WORKSPACE_FILE="${WORKSPACE_FILE}"
MARKDOWN_STYLES_SRC="${MARKDOWN_STYLES_SRC}"

prune_dead_workspace_paths() {
    [[ -f "\$WORKSPACE_FILE" ]] || return 0
    command -v jq &>/dev/null || return 0
    local folders dead=() path tmp
    folders=\$(jq -r '.folders[].path' "\$WORKSPACE_FILE" 2>/dev/null || true)
    while IFS= read -r path; do
        [[ -n "\$path" ]] || continue
        [[ -e "\$path" ]] || dead+=("\$path")
    done <<< "\$folders"
    [[ \${#dead[@]} -eq 0 ]] && return 0
    tmp=\$(mktemp)
    jq --argjson dead "\$(printf '%s\n' "\${dead[@]}" | jq -R . | jq -s .)" \\
        '.folders |= map(select(.path as \$p | \$dead | index(\$p) | not))' \\
        "\$WORKSPACE_FILE" > "\$tmp" && mv "\$tmp" "\$WORKSPACE_FILE"
    echo "Pruned \${#dead[@]} dead path(s) from workspace."
}

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
    prune_dead_workspace_paths
}

remove_from_workspace() {
    local dir="\$1"
    if [[ -f "\$WORKSPACE_FILE" ]] && command -v jq &>/dev/null; then
        local tmp
        tmp=\$(mktemp)
        jq --arg path "\$dir" '.folders |= map(select(.path != \$path))' "\$WORKSPACE_FILE" > "\$tmp" && mv "\$tmp" "\$WORKSPACE_FILE"
    fi
    prune_dead_workspace_paths
}

seed_vscode_markdown_styles() {
    local dir="\$1"
    [[ -f "\$MARKDOWN_STYLES_SRC" ]] || return 0
    mkdir -p "\${dir}/.vscode"
    cp "\$MARKDOWN_STYLES_SRC" "\${dir}/.vscode/markdown-styles.css"
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
    echo "Session \${SESSION_NAME} finalized. Run 'clown.sh --clean' to remove inactive clones."
}
trap finalize EXIT INT TERM

if [[ "\$REUSE_CLONE" == true ]]; then
    echo "Reusing inactive clone: \${CLONE_DIR}"
    cd "\$CLONE_DIR"

    status=\$(sl status --reason "check uncommitted changes before reuse | sl help status" 2>/dev/null || true)
    if [[ -n "\$status" ]]; then
        echo "Saving uncommitted changes from previous session..."
        sl addremove --reason "track new files before saving | sl help addremove" 2>/dev/null || true
        sl commit --reason "save previous session work | sl help commit" \
            -m "[WIP] Uncommitted changes saved before clone reuse" 2>/dev/null || true
        sl cloud sync --reason "sync saved work to commit cloud | sl help cloud" 2>/dev/null || true
    fi

    sl pull --reason "pull latest before checkout | sl help pull" 2>/dev/null || true
    sl checkout remote/fbcode/stable --reason "reset to stable for new session | sl help checkout" 2>/dev/null || true
    cd - >/dev/null
else
    echo "Creating enlistment: fbclone \${REPO_TYPE} \${CLONE_DIR}"
    fbclone "\${REPO_TYPE}" "\${CLONE_DIR}"
fi
seed_vscode_markdown_styles "\${CLONE_DIR}"
add_to_workspace "\${CLONE_DIR}"

cd "\$CLONE_DIR"
claude --dangerously-skip-permissions --dangerously-enable-internet-mode${QUOTED_ARGS}
WRAPPER_EOF
    chmod +x "$WRAPPER"

    # Reserve the directory so concurrent clown.sh calls pick a different slot
    mkdir -p "$CLONE_DIR"

    tmux new-window -n "${SESSION_NAME}" "$WRAPPER"
    echo "Session ${SESSION_NAME} launched in tmux window '${SESSION_NAME}'."
    echo "  Clone: ${CLONE_DIR}"

elif [[ "$MODE" == "background" ]]; then
    # Background mode: prepare clone, then launch claude_wrapper
    prepare_clone

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
    prepare_clone

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
