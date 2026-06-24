#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Launches Claude Code in a fresh worktree (default) or clone of fbsource/configerator.
# On exit, ensures all changes are committed and synced to commit cloud.
# Use --clean to remove inactive slots from ~/src/clown.
#
# Worktree mode (default) requires a distinguished base enlistment at
# ~/fbsource or ~/configerator. Bootstrap one with:
#   fbclone fbsource    --no-suffix ~/fbsource
#   fbclone configerator --no-suffix ~/configerator
#
# Usage:
#   clown.sh [options] <repo> [-- claude args...]
#   clown.sh -i fbsource                # worktree, interactive in new tmux window
#   clown.sh -i --clone fbsource        # full standalone clone via fbclone
#   clown.sh --ac fbsource               # AC-managed agent (opus)
#   clown.sh --clean                     # remove inactive slots from ~/src/clown
#   clown.sh --clean --dry-run           # preview what --clean would remove

set -euo pipefail

TEMP_BASE="$HOME/src/clown"
BASE_FBSOURCE="$HOME/fbsource"
BASE_CONFIGERATOR="$HOME/configerator"
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

# Seed a fresh slot with .vscode/markdown-styles.css copied from dotfiles.
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

# --- Base enlistment helpers ---
base_for() {
    case "$1" in
        f|fbsource) echo "$BASE_FBSOURCE" ;;
        c|configerator) echo "$BASE_CONFIGERATOR" ;;
    esac
}

require_base() {
    local base="$1" repo="$2"
    if [[ ! -d "$base" ]]; then
        echo "Error: base enlistment ${base} does not exist."
        echo "Bootstrap with: fbclone ${repo} --no-suffix ${base}"
        exit 1
    fi
    if ! eden info "$base" &>/dev/null; then
        echo "Error: ${base} is not an Eden checkout."
        echo "Bootstrap with: fbclone ${repo} --no-suffix ${base}"
        exit 1
    fi
}

# --- Save dirty working copy to commit cloud before reusing/removing a slot ---
save_uncommitted_work() {
    local dir="$1"
    local context="${2:-reuse}"
    [[ -d "$dir" ]] || return 0
    local status
    status=$(sl status --cwd "$dir" --reason "check uncommitted changes before ${context} | sl help status" 2>/dev/null || true)
    [[ -n "$status" ]] || return 0
    echo "Saving uncommitted changes from previous session..."
    sl addremove --cwd "$dir" --reason "track new files before saving | sl help addremove" 2>/dev/null || true
    sl commit --cwd "$dir" --reason "save previous session work | sl help commit" \
        -m "[WIP] Uncommitted changes saved before slot ${context}" 2>/dev/null || true
    sl cloud sync --cwd "$dir" --reason "sync saved work to commit cloud | sl help cloud" 2>/dev/null || true
}

# --- Slot type detection ---
# Returns 0 if dir is a linked worktree (part of a group), 1 if standalone clone.
# sl worktree list -Tjson returns "[\n]" (whitespace) for an empty group, so we
# parse with jq to get a real length.
is_worktree_slot() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    local count
    count=$(sl worktree list -Tjson --cwd "$dir" 2>/dev/null \
        | jq -r 'length' 2>/dev/null || echo 0)
    [[ "${count:-0}" -gt 0 ]]
}

# `sl worktree remove` kills the buckd for us; `eden rm` does not, so clone
# removal must do it explicitly or daemons leak across sessions.
kill_buck_daemon() {
    local dir="$1"
    command -v buck2 &>/dev/null || return 0
    [[ -d "$dir" ]] || return 0
    echo "Killing any buck2 daemon for ${dir}..."
    (cd "$dir" && buck2 kill 2>&1) || true
}

# --- Slot removal: dispatches on type ---
remove_slot() {
    local dir="$1"
    local base
    base=$(base_for "${PREFIX:-$(basename "$dir" | head -c1)}")
    if is_worktree_slot "$dir"; then
        echo "Removing linked worktree ${dir}..."
        if [[ -n "$base" ]]; then
            sl worktree remove "$dir" -y --cwd "$base" 2>&1 || rm -rf "$dir"
        else
            rm -rf "$dir"
        fi
    else
        echo "Removing standalone clone ${dir}..."
        kill_buck_daemon "$dir"
        eden rm --yes "$dir" 2>/dev/null || rm -rf "$dir"
    fi
}

# --- Slot activity detection ---
# Populates _AC_PATHS cache on first call. Checks claude processes, session
# wrappers, and AC agents. Returns 0 (active) or 1 (inactive).
_AC_PATHS_CACHED=""
_AC_PATHS_LOADED=false
_load_ac_paths() {
    if [[ "$_AC_PATHS_LOADED" == true ]]; then return; fi
    _AC_PATHS_LOADED=true
    if command -v acd &>/dev/null; then
        # Each line is "<fbclonePath>\t<agent name>" so callers can name the agent.
        _AC_PATHS_CACHED=$(acd agent list --json 2>/dev/null \
            | jq -r '.hosts[].agents[] | select(.alive) | select(.fbclonePath != null) | "\(.fbclonePath)\t\(.name // "unknown")"' 2>/dev/null \
            || true)
    fi
}

# On a return of 0 (active), sets _ACTIVE_REASON to a human-readable
# explanation of what is holding the slot (process + pid, wrapper, or AC agent).
_ACTIVE_REASON=""
is_slot_active() {
    local dir="$1"
    local name
    name=$(basename "$dir")
    local real_dir
    real_dir=$(realpath "$dir")
    _ACTIVE_REASON=""

    # Check if any claude process has this directory as its cwd
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        local proc_cwd
        proc_cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)
        if [[ "$proc_cwd" == "$real_dir" || "$proc_cwd" == "${real_dir}/"* ]]; then
            local cmd
            cmd=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '\n' || true)
            _ACTIVE_REASON="claude process ${cmd:-claude} (pid ${pid}) running here"
            return 0
        fi
    done < <(pgrep -f "claude" 2>/dev/null || true)

    # Check if the session wrapper script is still running
    local wrapper_pid
    wrapper_pid=$(pgrep -f "claude_session_wrapper_${name}[.]sh" 2>/dev/null | head -n1 || true)
    if [[ -n "$wrapper_pid" ]]; then
        _ACTIVE_REASON="session wrapper still running (pid ${wrapper_pid})"
        return 0
    fi

    # Check if an AC agent is using this slot
    _load_ac_paths
    if [[ -n "$_AC_PATHS_CACHED" ]]; then
        while IFS=$'\t' read -r ac_path ac_name; do
            [[ -n "$ac_path" ]] || continue
            if [[ "$ac_path" == "$real_dir" ]]; then
                _ACTIVE_REASON="live AC agent '${ac_name:-unknown}' attached to this slot"
                return 0
            fi
        done <<< "$_AC_PATHS_CACHED"
    fi

    return 1
}

# --- Clean mode: remove inactive slots ---
clean_slots() {
    local dry_run="${1:-false}"
    mkdir -p "$TEMP_BASE"
    local removed=0
    local kept=0
    local total=0

    if [[ "$dry_run" == true ]]; then
        echo "Scanning ${TEMP_BASE} for inactive slots (dry run)..."
    else
        echo "Scanning ${TEMP_BASE} for inactive slots..."
    fi
    echo ""

    for dir in "${TEMP_BASE}"/*/; do
        [[ -d "$dir" ]] || continue
        total=$((total + 1))
        local name kind
        name=$(basename "$dir")
        if is_worktree_slot "$dir"; then
            kind="worktree"
        else
            kind="clone   "
        fi

        if is_slot_active "$dir"; then
            echo "  ACTIVE    ${kind}  ${name}  — ${_ACTIVE_REASON:-in use}"
            kept=$((kept + 1))
        else
            if [[ "$dry_run" == true ]]; then
                echo "  INACTIVE  ${kind}  ${name}  — would remove"
            else
                echo "  INACTIVE  ${kind}  ${name}  — removing..."
                remove_from_workspace "${dir%/}"
                PREFIX="${name:0:1}" remove_slot "${dir%/}"
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

# --- Find or pick a slot directory ---
# Looks for an inactive slot with the given prefix to reuse. If none, picks the
# next available slot number. Sets SLOT_DIR, SESSION_NAME, REUSE_SLOT.
find_slot() {
    local prefix="$1"
    REUSE_SLOT=false

    # Load eden mount states once for the scan (only relevant for clone mode)
    local eden_json=""
    eden_json=$(eden list --json 2>/dev/null || true)

    # Scan for an inactive slot to reuse
    for dir in "${TEMP_BASE}/${prefix}"*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        [[ "$name" =~ ^${prefix}[0-9]+$ ]] || continue
        if ! is_slot_active "$dir"; then
            # In clone mode, verify the eden mount is healthy before reusing.
            # In worktree mode, we'll wipe and re-create anyway.
            if [[ "$USE_CLONE" == true && -n "$eden_json" ]]; then
                local real_path
                real_path=$(realpath "${dir%/}")
                local eden_state
                eden_state=$(echo "$eden_json" | jq -r --arg p "$real_path" '.[$p].state // empty' 2>/dev/null || true)
                if [[ "$eden_state" != "RUNNING" ]]; then
                    echo "Skipping ${name}: eden mount not healthy (state=${eden_state:-missing})"
                    continue
                fi
            fi
            SLOT_DIR="${dir%/}"
            SESSION_NAME="$name"
            REUSE_SLOT=true
            return
        fi
    done

    # No reusable slot found — pick next available number
    local n=1
    while [[ -d "${TEMP_BASE}/${prefix}${n}" ]]; do
        n=$((n + 1))
    done
    SLOT_DIR="${TEMP_BASE}/${prefix}${n}"
    SESSION_NAME="${prefix}${n}"
}

# --- Prepare a slot directory ---
# Worktree mode: remove if exists, then `sl worktree add` from base.
# Clone   mode: reuse if possible (reset to stable), else `fbclone`.
prepare_slot() {
    if [[ "$USE_CLONE" == true ]]; then
        prepare_clone_slot
    else
        prepare_worktree_slot
    fi
    seed_vscode_markdown_styles "$SLOT_DIR"
    add_to_workspace "$SLOT_DIR"
}

prepare_worktree_slot() {
    local base
    base=$(base_for "$PREFIX")
    require_base "$base" "$REPO_TYPE"
    if [[ -d "$SLOT_DIR" ]]; then
        save_uncommitted_work "$SLOT_DIR" "recreate"
        echo "Removing existing slot ${SLOT_DIR} for fresh worktree..."
        remove_slot "$SLOT_DIR"
    fi
    echo "Creating worktree: sl worktree add ${SLOT_DIR}"
    sl worktree add "$SLOT_DIR" --cwd "$base"
}

prepare_clone_slot() {
    # If reusing a slot that's actually a worktree, blow it away and start fresh.
    if [[ "$REUSE_SLOT" == true ]] && is_worktree_slot "$SLOT_DIR"; then
        echo "Slot ${SLOT_DIR} is a worktree but clone mode requested; removing..."
        remove_slot "$SLOT_DIR"
        REUSE_SLOT=false
    fi

    if [[ "$REUSE_SLOT" == true ]]; then
        echo "Reusing inactive clone: ${SLOT_DIR}"
        save_uncommitted_work "$SLOT_DIR" "reuse"
        sl pull --cwd "$SLOT_DIR" --reason "pull latest before checkout | sl help pull" 2>/dev/null || true
        sl checkout remote/fbcode/stable --cwd "$SLOT_DIR" \
            --reason "reset to stable for new session | sl help checkout" 2>/dev/null || true
    else
        echo "Creating enlistment: fbclone $REPO_TYPE $SLOT_DIR"
        fbclone "$REPO_TYPE" "$SLOT_DIR"
    fi
}

# --- Parse options ---
MODE="interactive"
USE_TMUX=true
USE_AC=false
USE_CLONE=false
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
            clean_slots "$CLEAN_DRY_RUN"
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
        --clone)
            USE_CLONE=true
            shift
            ;;
        --worktree)
            USE_CLONE=false
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
            echo "  --worktree          Linked worktree from base enlistment (default)"
            echo "  --clone             Full standalone clone via fbclone"
            echo "  --clean             Remove inactive slots from ~/src/clown"
            echo "  --clean --dry-run   Show what --clean would do without removing"
            echo ""
            echo "Worktree mode requires base enlistments at ~/fbsource / ~/configerator."
            echo "Bootstrap once with: fbclone fbsource --no-suffix ~/fbsource"
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

# Validate base enlistment up-front in worktree mode so we fail fast.
if [[ "$USE_CLONE" == false ]]; then
    require_base "$(base_for "$PREFIX")" "$REPO_TYPE"
fi

find_slot "$PREFIX"

# --- Finalize function (used by non-tmux modes and embedded in tmux wrapper) ---
# Commits uncommitted changes and syncs to commit cloud.
# Slot removal is handled separately via `clown.sh --clean`.
finalize() {
    echo ""
    echo "Finalizing session ${SESSION_NAME}..."

    if [[ ! -d "$SLOT_DIR" ]]; then
        echo "Slot directory gone, nothing to finalize."
        return
    fi

    cd "$SLOT_DIR"

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
    echo "Session ${SESSION_NAME} finalized. Run 'clown.sh --clean' to remove inactive slots."
}

# --- Launch ---
if [[ "$USE_AC" == true ]]; then
    # AC mode: prepare slot, then hand off to Agent Conductor
    prepare_slot

    AGENT_NAME=$(generate_agent_name)

    echo ""
    echo "Launching AC agent '${AGENT_NAME}' in ${SLOT_DIR}"
    echo "  Repo:  ${REPO_TYPE}"
    echo "  Mode:  $([[ "$USE_CLONE" == true ]] && echo "clone" || echo "worktree")"
    echo "  Model: claude-opus-4-8[1m]"
    echo ""

    acd agent create \
        --mode claude \
        --model opus \
        --dir "$SLOT_DIR" \
        --name "$AGENT_NAME" \
        --fbclone-path "$SLOT_DIR" \
        --skip-permissions=true \
        --env "META_CLAUDE_USE_GCP_DIRECT=1" \
        --env "META_CLAUDE_CODE_NATIVE_BIN=1" \
        --env "NODE_OPTIONS=--max-old-space-size=32768" \
        --env "META_CLAUDE_CODE_RELEASE=latest" \
        --env "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" \
        -- --dangerously-skip-permissions --dangerously-enable-internet-mode \
           --model "claude-opus-4-8[1m]" --effort xhigh \
           --settings '{"ultracode": true}' \
           "${CLAUDE_ARGS[@]:+"${CLAUDE_ARGS[@]}"}"

    echo ""
    echo "Agent '${AGENT_NAME}' created."
    echo "  acd agent show ${AGENT_NAME}"
    echo "  acd agent output -f ${AGENT_NAME}"
    echo "  acd agent prompt ${AGENT_NAME} \"your message\""

elif [[ "$USE_TMUX" == true && -n "${TMUX:-}" && "$MODE" == "interactive" ]]; then
    # Interactive tmux mode: open window immediately so caller's terminal is free.
    # The wrapper handles slot prep + claude + finalize entirely in the new window.
    WRAPPER="/tmp/claude_session_wrapper_${SESSION_NAME}.sh"

    # Serialize CLAUDE_ARGS with proper quoting for the wrapper script
    QUOTED_ARGS=""
    for arg in "${CLAUDE_ARGS[@]:+${CLAUDE_ARGS[@]}}"; do
        escaped=$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")
        QUOTED_ARGS="${QUOTED_ARGS} '${escaped}'"
    done

    BASE_DIR=$(base_for "$PREFIX")

    cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
set -euo pipefail

SLOT_DIR="${SLOT_DIR}"
SESSION_NAME="${SESSION_NAME}"
REPO_TYPE="${REPO_TYPE}"
PREFIX="${PREFIX}"
REUSE_SLOT="${REUSE_SLOT}"
USE_CLONE="${USE_CLONE}"
BASE_DIR="${BASE_DIR}"
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

seed_vscode_markdown_styles() {
    local dir="\$1"
    [[ -f "\$MARKDOWN_STYLES_SRC" ]] || return 0
    mkdir -p "\${dir}/.vscode"
    cp "\$MARKDOWN_STYLES_SRC" "\${dir}/.vscode/markdown-styles.css"
}

is_worktree_slot() {
    local dir="\$1"
    [[ -d "\$dir" ]] || return 1
    local count
    count=\$(sl worktree list -Tjson --cwd "\$dir" 2>/dev/null \
        | jq -r 'length' 2>/dev/null || echo 0)
    [[ "\${count:-0}" -gt 0 ]]
}

save_uncommitted_work() {
    local dir="\$1"
    local context="\${2:-reuse}"
    [[ -d "\$dir" ]] || return 0
    local status
    status=\$(sl status --cwd "\$dir" --reason "check uncommitted changes before \${context} | sl help status" 2>/dev/null || true)
    [[ -n "\$status" ]] || return 0
    echo "Saving uncommitted changes from previous session..."
    sl addremove --cwd "\$dir" --reason "track new files before saving | sl help addremove" 2>/dev/null || true
    sl commit --cwd "\$dir" --reason "save previous session work | sl help commit" \
        -m "[WIP] Uncommitted changes saved before slot \${context}" 2>/dev/null || true
    sl cloud sync --cwd "\$dir" --reason "sync saved work to commit cloud | sl help cloud" 2>/dev/null || true
}

kill_buck_daemon() {
    local dir="\$1"
    command -v buck2 &>/dev/null || return 0
    [[ -d "\$dir" ]] || return 0
    echo "Killing any buck2 daemon for \${dir}..."
    (cd "\$dir" && buck2 kill 2>&1) || true
}

remove_slot() {
    local dir="\$1"
    if is_worktree_slot "\$dir"; then
        echo "Removing linked worktree \${dir}..."
        sl worktree remove "\$dir" -y --cwd "\$BASE_DIR" 2>&1 || rm -rf "\$dir"
    else
        echo "Removing standalone clone \${dir}..."
        kill_buck_daemon "\$dir"
        eden rm --yes "\$dir" 2>/dev/null || rm -rf "\$dir"
    fi
}

finalize() {
    echo ""
    echo "Finalizing session \${SESSION_NAME}..."
    if [[ ! -d "\$SLOT_DIR" ]]; then
        echo "Slot directory gone, nothing to finalize."
        return
    fi
    cd "\$SLOT_DIR"
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
    echo "Session \${SESSION_NAME} finalized. Run 'clown.sh --clean' to remove inactive slots."
}
trap finalize EXIT INT TERM

if [[ "\$USE_CLONE" == true ]]; then
    if [[ "\$REUSE_SLOT" == true ]] && is_worktree_slot "\$SLOT_DIR"; then
        echo "Slot \$SLOT_DIR is a worktree but clone mode requested; removing..."
        remove_slot "\$SLOT_DIR"
        REUSE_SLOT=false
    fi
    if [[ "\$REUSE_SLOT" == true ]]; then
        echo "Reusing inactive clone: \${SLOT_DIR}"
        save_uncommitted_work "\$SLOT_DIR" "reuse"
        sl pull --cwd "\$SLOT_DIR" --reason "pull latest before checkout | sl help pull" 2>/dev/null || true
        sl checkout remote/fbcode/stable --cwd "\$SLOT_DIR" \
            --reason "reset to stable for new session | sl help checkout" 2>/dev/null || true
    else
        echo "Creating enlistment: fbclone \${REPO_TYPE} \${SLOT_DIR}"
        fbclone "\${REPO_TYPE}" "\${SLOT_DIR}"
    fi
else
    if [[ -d "\$SLOT_DIR" ]]; then
        save_uncommitted_work "\$SLOT_DIR" "recreate"
        echo "Removing existing slot \$SLOT_DIR for fresh worktree..."
        remove_slot "\$SLOT_DIR"
    fi
    echo "Creating worktree: sl worktree add \${SLOT_DIR}"
    sl worktree add "\$SLOT_DIR" --cwd "\$BASE_DIR"
fi
seed_vscode_markdown_styles "\${SLOT_DIR}"
add_to_workspace "\${SLOT_DIR}"

cd "\$SLOT_DIR"
claude --dangerously-skip-permissions --dangerously-enable-internet-mode${QUOTED_ARGS}
WRAPPER_EOF
    chmod +x "$WRAPPER"

    # Clone-mode fresh: reserve slot so concurrent calls pick a different number.
    # Other paths use an existing dir (reuse) or let `sl worktree add` create it.
    if [[ "$USE_CLONE" == true && "$REUSE_SLOT" == false ]]; then
        mkdir -p "$SLOT_DIR"
    fi

    tmux new-window -n "${SESSION_NAME}" "$WRAPPER"
    echo "Session ${SESSION_NAME} launched in tmux window '${SESSION_NAME}'."
    echo "  Slot: ${SLOT_DIR}"
    echo "  Mode: $([[ "$USE_CLONE" == true ]] && echo "clone" || echo "worktree")"

elif [[ "$MODE" == "background" ]]; then
    # Background mode: prepare slot, then launch claude_wrapper
    prepare_slot

    ARGS_FILE="/tmp/claude_session_args_${SESSION_NAME}.txt"
    cat > "$ARGS_FILE" <<EOF
--cwd
${SLOT_DIR}
--session-id
${SESSION_NAME}
EOF

    cleanup_args() {
        rm -f "$ARGS_FILE"
        finalize
    }
    trap cleanup_args EXIT INT TERM

    echo ""
    echo "Launching Claude in ${SLOT_DIR}"
    echo "  Session: ${SESSION_NAME}"
    echo "  Repo:    ${REPO_TYPE}"
    echo "  Mode:    background ($([[ "$USE_CLONE" == true ]] && echo "clone" || echo "worktree"))"
    echo ""

    buck2 run fbcode//scripts/sledesma/dmodel_claude/scripts:claude_wrapper -- \
        "${CLAUDE_ARGS[@]:+${CLAUDE_ARGS[@]}}" \
        "@${ARGS_FILE}"

else
    # Interactive mode in current terminal (--no-tmux or no tmux session)
    prepare_slot

    trap finalize EXIT INT TERM

    echo ""
    echo "Launching Claude in ${SLOT_DIR}"
    echo "  Session: ${SESSION_NAME}"
    echo "  Repo:    ${REPO_TYPE}"
    echo "  Mode:    interactive ($([[ "$USE_CLONE" == true ]] && echo "clone" || echo "worktree"))"
    echo ""

    cd "$SLOT_DIR"
    claude --dangerously-skip-permissions --dangerously-enable-internet-mode "${CLAUDE_ARGS[@]:+"${CLAUDE_ARGS[@]}"}"
fi
