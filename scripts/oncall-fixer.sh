#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Spawns parallel Claude Code agents to fix broken/flaky tests and build failures.
# Each agent gets its own fbsource clone via clown.sh and runs autonomously.
#
# Usage:
#   oncall-fixer.sh [options] [targets...]
#   oncall-fixer.sh --discover --team aria_ai
#   oncall-fixer.sh --team aria_ai --config targets.txt
#   oncall-fixer.sh --dry-run --team aria_ai broken:fbcode//path/to:test
#
# Target format: TYPE=BUCK_TARGET[=TEST_NAME]
#   TYPE is one of: broken, flaky, build
#   BUCK_TARGET is the full buck target path (contains colons, so we use = as separator)
#   TEST_NAME (optional) is the specific failing test method
#
# Examples:
#   broken=fbcode//surreal/aria_ai/tests:test_auth=test_service_router_error
#   flaky=fbcode//surreal/aria_ai/models:handler_test
#   build=fbcode//surreal/aria_ai/common:decoder
#
# Config file format (one target per line, # for comments):
#   broken=fbcode//surreal/aria_ai/tests:test_auth=test_service_router_error
#   flaky=fbcode//surreal/aria_ai/models:handler_test
#   build=fbcode//surreal/aria_ai/common:decoder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="${SCRIPT_DIR}/prompts"

# --- Defaults ---
DRY_RUN=false
DISCOVER=false
TEAM="aria_ai"
ONCALL_USER="${USER}"
TARGETS=()
CONFIG_FILE=""
DELAY=30

# --- Usage ---
usage() {
    cat <<EOF
Usage: $0 [options] [targets...]

Spawns Claude Code agents to fix broken/flaky tests and build failures.
Each agent gets its own fbsource clone and runs autonomously.

Options:
  --discover      Run an analysis agent to discover broken/flaky tests and
                  build failures, then launch fixers for each. No --config needed.
  --discover-only Run the analysis agent and write a targets file, then stop.
                  Use this to review discovered targets before launching fixers.
  --dry-run       Preview what would be launched (writes prompts, doesn't launch)
  --team TEAM     Team name for diff tagging (default: aria_ai)
  --user USER     Username for GChat notifications (default: \$USER)
  --config FILE   Read targets from a file (one per line, # for comments)
  --delay SECS    Seconds between launches (default: 30)
  -h, --help      Show this help

Target format: TYPE=BUCK_TARGET[=TEST_NAME]
  broken=fbcode//path:target          Actively failing test
  broken=fbcode//path:target=method   Specific failing test method
  flaky=fbcode//path:target           Flaky test
  build=fbcode//path:target           Build failure

The = separator is used instead of : because buck targets contain colons.
EOF
    exit 1
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --discover)
            DISCOVER=true
            shift
            ;;
        --discover-only)
            DISCOVER=true
            DRY_RUN=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --team)
            TEAM="$2"
            shift 2
            ;;
        --user)
            ONCALL_USER="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --delay)
            DELAY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

# --- Discovery mode: run analysis agent to find targets ---
if $DISCOVER; then
    DISCOVER_TEMPLATE="${PROMPT_DIR}/oncall-discover.txt"
    if [[ ! -f "$DISCOVER_TEMPLATE" ]]; then
        echo "Error: missing discovery prompt: ${DISCOVER_TEMPLATE}"
        exit 1
    fi

    DISCOVER_PROMPT="/tmp/oncall_discover_prompt_${TEAM}.txt"
    DISCOVER_TARGETS="/tmp/oncall_discover_${TEAM}_targets.txt"
    DISCOVER_INVENTORY="/tmp/oncall_discover_${TEAM}_inventory.txt"
    DISCOVER_SUMMARY="/tmp/oncall_discover_${TEAM}_summary.txt"

    # Render the discovery prompt
    cp "$DISCOVER_TEMPLATE" "$DISCOVER_PROMPT"
    ESCAPED_TEAM=$(printf '%s' "$TEAM" | sed 's/[&\\/]/\\&/g')
    ESCAPED_USER=$(printf '%s' "$ONCALL_USER" | sed 's/[&\\/]/\\&/g')
    sed -i "s|{{TEAM}}|${ESCAPED_TEAM}|g" "$DISCOVER_PROMPT"
    sed -i "s|{{USER}}|${ESCAPED_USER}|g" "$DISCOVER_PROMPT"

    echo "========================================"
    echo "  Oncall Discovery"
    echo "  Team:    ${TEAM}"
    echo "  User:    ${ONCALL_USER}"
    echo "  Date:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""
    echo "Launching discovery agent to analyze oncall health..."
    echo "  Prompt:    ${DISCOVER_PROMPT} ($(wc -c < "$DISCOVER_PROMPT") bytes)"
    echo "  Inventory: ${DISCOVER_INVENTORY}"
    echo "  Tasks:     ${DISCOVER_TARGETS}"
    echo "  Summary:   ${DISCOVER_SUMMARY}"
    echo ""

    # Run discovery agent in foreground (blocking) via clown.sh --no-tmux
    # The agent queries scuba, graphql, metamate and writes the targets file.
    "${SCRIPT_DIR}/clown.sh" -i --no-tmux fbsource -- \
        -p "$(cat "$DISCOVER_PROMPT")"

    # Check if discovery produced a targets file
    if [[ ! -f "$DISCOVER_TARGETS" ]]; then
        echo ""
        echo "Error: discovery agent did not produce a targets file at:"
        echo "  ${DISCOVER_TARGETS}"
        echo ""
        echo "Check the discovery summary (if written):"
        echo "  cat ${DISCOVER_SUMMARY}"
        exit 1
    fi

    echo ""
    echo "Discovery complete. Targets file: ${DISCOVER_TARGETS}"
    echo ""

    # Show the summary if it exists
    if [[ -f "$DISCOVER_SUMMARY" ]]; then
        echo "--- Discovery Summary ---"
        cat "$DISCOVER_SUMMARY"
        echo "--- End Summary ---"
        echo ""
    fi

    # Load the discovered targets as the config file
    CONFIG_FILE="$DISCOVER_TARGETS"
fi

# --- Load targets from config file ---
# Parse the config file, capturing comment blocks above each target as cluster
# context. Comments between target lines are associated with the NEXT target.
CLUSTER_CONTEXTS=()

if [[ -n "$CONFIG_FILE" ]]; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: config file not found: $CONFIG_FILE"
        exit 1
    fi
    pending_comments=""
    while IFS= read -r raw_line; do
        stripped=$(echo "$raw_line" | xargs)
        if [[ -z "$stripped" ]]; then
            # blank line — keep accumulating
            continue
        elif [[ "$stripped" == \#* ]]; then
            # comment line — accumulate for the next target
            pending_comments+="${raw_line}"$'\n'
        else
            # target line — store it with its accumulated comments
            TARGETS+=("$stripped")
            CLUSTER_CONTEXTS+=("$pending_comments")
            pending_comments=""
        fi
    done < "$CONFIG_FILE"
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    if $DISCOVER; then
        echo "Discovery produced no actionable targets. Nothing to fix."
        exit 0
    fi
    echo "Error: no targets specified."
    echo ""
    usage
fi

# --- Validate prompt templates exist ---
for tmpl in broken-test-fixer.txt flaky-test-fixer.txt build-failure-fixer.txt; do
    if [[ ! -f "${PROMPT_DIR}/${tmpl}" ]]; then
        echo "Error: missing prompt template: ${PROMPT_DIR}/${tmpl}"
        exit 1
    fi
done

# --- Header ---
echo "========================================"
echo "  Oncall Test Fixer"
echo "  Team:    ${TEAM}"
echo "  User:    ${ONCALL_USER}"
echo "  Date:    $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Targets: ${#TARGETS[@]}"
echo "  Mode:    $(if $DRY_RUN; then echo 'DRY RUN'; else echo 'LIVE'; fi)"
echo "  Delay:   ${DELAY}s between launches"
echo "========================================"
echo ""

# --- Process targets ---
PROMPT_FILES=()

for idx in "${!TARGETS[@]}"; do
    target_spec="${TARGETS[$idx]}"
    # Parse TYPE=BUCK_TARGET[=TEST_NAME] using = as separator
    # Split on first = to get TYPE
    TYPE="${target_spec%%=*}"
    REST="${target_spec#*=}"

    # REST is now BUCK_TARGET[=TEST_NAME]
    # Check if there's a test name (another = after the buck target)
    # Buck targets look like: fbcode//path/to:target_name
    # Test name would be after the last =
    if [[ "$REST" == *"="* ]]; then
        # There's a test name
        BUCK_TARGET="${REST%=*}"
        TEST_NAME="${REST##*=}"
    else
        BUCK_TARGET="$REST"
        TEST_NAME=""
    fi

    # Select prompt template
    case "$TYPE" in
        broken)
            TEMPLATE_FILE="${PROMPT_DIR}/broken-test-fixer.txt"
            LABEL="BROKEN"
            ;;
        flaky)
            TEMPLATE_FILE="${PROMPT_DIR}/flaky-test-fixer.txt"
            LABEL="FLAKY"
            ;;
        build)
            TEMPLATE_FILE="${PROMPT_DIR}/build-failure-fixer.txt"
            LABEL="BUILD"
            ;;
        *)
            echo "Error: unknown type '${TYPE}' in: ${target_spec}"
            echo "Valid types: broken, flaky, build"
            exit 1
            ;;
    esac

    # Generate safe filename from buck target
    SAFE_NAME=$(echo "$BUCK_TARGET" | tr '/:' '__')
    PROMPT_FILE="/tmp/oncall_fixer_prompt_${SAFE_NAME}.txt"

    # Render template using sed on the file directly.
    # We avoid loading into a bash variable because templates contain $var and
    # $(cmd) syntax (for the agent's shell examples) that bash would expand.
    cp "$TEMPLATE_FILE" "$PROMPT_FILE"

    # Escape sed replacement special chars (& and \) in substitution values
    ESCAPED_TARGET=$(printf '%s' "$BUCK_TARGET" | sed 's/[&\\/]/\\&/g')
    ESCAPED_TEAM=$(printf '%s' "$TEAM" | sed 's/[&\\/]/\\&/g')
    ESCAPED_USER=$(printf '%s' "$ONCALL_USER" | sed 's/[&\\/]/\\&/g')

    sed -i "s|{{TARGET}}|${ESCAPED_TARGET}|g" "$PROMPT_FILE"
    sed -i "s|{{TEAM}}|${ESCAPED_TEAM}|g" "$PROMPT_FILE"
    sed -i "s|{{USER}}|${ESCAPED_USER}|g" "$PROMPT_FILE"

    # Inject cluster context if available (from config file comments above target)
    CONTEXT="${CLUSTER_CONTEXTS[$idx]:-}"
    if [[ -n "$CONTEXT" ]]; then
        # Write cluster context to a temp file (avoids bash expansion of $vars)
        CONTEXT_FILE="/tmp/oncall_fixer_context_${SAFE_NAME}.txt"
        printf '%s' "$CONTEXT" > "$CONTEXT_FILE"
        # Replace the {{CLUSTER_CONTEXT}} placeholder, or append after first line
        if grep -q '{{CLUSTER_CONTEXT}}' "$PROMPT_FILE"; then
            # Multi-line sed replacement: read context file into hold space
            sed -i -e "/{{CLUSTER_CONTEXT}}/{r ${CONTEXT_FILE}" -e 'd}' "$PROMPT_FILE"
        else
            # No placeholder — append cluster context after the opening paragraph
            sed -i "3i\\
## Cluster Context\\
\\
This target is part of a cluster of related failures. Your fix should address\\
the root cause that affects ALL targets in the cluster. After fixing, validate\\
against every target listed below, not just the representative target.\\
" "$PROMPT_FILE"
            sed -i "7r ${CONTEXT_FILE}" "$PROMPT_FILE"
        fi
        rm -f "$CONTEXT_FILE"
    else
        # No cluster context — remove the placeholder if present
        sed -i '/{{CLUSTER_CONTEXT}}/d' "$PROMPT_FILE"
    fi

    if [[ -n "$TEST_NAME" ]]; then
        ESCAPED_TEST=$(printf '%s' "$TEST_NAME" | sed 's/[&\\/]/\\&/g')
        sed -i 's/{{#TEST_NAME}}//g' "$PROMPT_FILE"
        sed -i 's|{{/TEST_NAME}}||g' "$PROMPT_FILE"
        sed -i "s|{{TEST_NAME}}|${ESCAPED_TEST}|g" "$PROMPT_FILE"
    else
        # Remove conditional blocks. Handle two cases:
        # 1. Single-line: {{#TEST_NAME}}...{{/TEST_NAME}} on same line
        sed -i '/{{#TEST_NAME}}.*{{\/TEST_NAME}}/d' "$PROMPT_FILE"
        # 2. Multi-line: {{#TEST_NAME}} on one line, {{/TEST_NAME}} on another
        sed -i '/{{#TEST_NAME}}/,/{{\/TEST_NAME}}/d' "$PROMPT_FILE"
    fi

    PROMPT_FILES+=("$PROMPT_FILE")

    # Display target info
    echo "  [${LABEL}] ${BUCK_TARGET}"
    if [[ -n "$TEST_NAME" ]]; then
        echo "         Method: ${TEST_NAME}"
    fi
    echo "         Prompt: ${PROMPT_FILE} ($(wc -c < "$PROMPT_FILE") bytes)"
    echo ""
done

# --- Dry run: just show plan ---
if $DRY_RUN; then
    echo "DRY RUN complete. ${#PROMPT_FILES[@]} prompts written to /tmp/."
    echo ""
    echo "To inspect a prompt:"
    echo "  cat ${PROMPT_FILES[0]}"
    echo ""
    echo "To run for real:"
    echo "  $0 --team ${TEAM} ${TARGETS[*]}"
    exit 0
fi

# --- Confirm launch ---
echo ""
echo "About to launch ${#PROMPT_FILES[@]} agents, each in its own fbsource clone."
echo "Each clone takes ~2 minutes to create."
echo ""
read -r -p "Proceed? [Y/n] " response
response=${response:-Y}
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Aborted."
    exit 0
fi

# --- Launch agents ---
echo ""
echo "Launching agents..."
echo ""

PIDS=()
for i in "${!PROMPT_FILES[@]}"; do
    PROMPT_FILE="${PROMPT_FILES[$i]}"
    TARGET_SPEC="${TARGETS[$i]}"

    echo "[$((i+1))/${#PROMPT_FILES[@]}] Launching: ${TARGET_SPEC}"

    # Use background mode (-b), matching monitor.sh pattern
    "${SCRIPT_DIR}/clown.sh" -b fbsource -- \
        --initial-prompt "$(cat "$PROMPT_FILE")" &
    PIDS+=($!)

    # Stagger launches to avoid overwhelming fbclone/EdenFS
    if [[ $i -lt $((${#PROMPT_FILES[@]} - 1)) ]]; then
        echo "  Waiting ${DELAY}s before next launch..."
        sleep "$DELAY"
    fi
done

echo ""
echo "========================================"
echo "  All ${#PROMPT_FILES[@]} agents launched."
echo "  PIDs: ${PIDS[*]}"
echo ""
echo "  Monitor with:"
echo "    ps aux | grep claude"
echo "    tmux list-windows"
echo ""
echo "  Cleanup when done:"
echo "    ${SCRIPT_DIR}/clown.sh --clean"
echo "========================================"
