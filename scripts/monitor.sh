#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Monitors Phabricator diffs by detecting the repo, generating a monitoring
# prompt, and delegating to clown.sh for clone allocation and session management.
#
# Usage: ./monitor.sh D12345678 [D12345679 ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 D<num> [D<num> ...]"
    exit 1
fi

DIFFS=("$@")
PRIMARY_DIFF="${DIFFS[0]}"
DIFF_NUM="${PRIMARY_DIFF#D}"
PROMPT_FILE="/tmp/diff_monitor_prompt_${DIFF_NUM}.txt"

cleanup_prompt() {
    rm -f "$PROMPT_FILE"
}
trap cleanup_prompt EXIT

# --- Detect repository ---
echo "Detecting repository for ${PRIMARY_DIFF}..."
DIFF_META=$(meta phabricator.diff metadata -n "$PRIMARY_DIFF" -o json)
REPO=$(echo "$DIFF_META" | jq -r '.repository')

case "$REPO" in
    FBS)
        REPO_TYPE="fbsource"
        ;;
    CONFIGERATOR)
        REPO_TYPE="configerator"
        ;;
    WWW)
        echo "Error: www diffs are not yet supported by monitor.sh."
        echo "www requires an existing OnDemand enlistment, not a fresh clone."
        exit 1
        ;;
    *)
        echo "Error: Unsupported repository: $REPO"
        exit 1
        ;;
esac

# --- Write monitoring prompt ---
cat > "$PROMPT_FILE" <<'PROMPTEOF'
You are a diff monitoring agent. Your job is to continuously monitor Phabricator
diffs, fix issues, and report status until all diffs are landed or abandoned.

## Diffs to Monitor
PROMPTEOF
for d in "${DIFFS[@]}"; do
    echo "- ${d}" >> "$PROMPT_FILE"
done
cat >> "$PROMPT_FILE" <<'PROMPTEOF'

## Setup

1. Run `sl ssl` to see the stack. Identify which commits correspond to which diffs.
2. If you're not on the right commit, run:
   sl pull --reason "pull diff commits | sl help pull" -r <DIFF_NUM>
   sl goto --reason "checkout diff commit | sl help goto" <hash>
3. For each diff, get current status:
   meta phabricator.diff metadata -n DXXX -o json
4. Read the CLAUDE.md files in the repo for conventions.

## Monitoring Loop

Repeat the following every ~5 minutes (use `sleep 300` between iterations).
Stop when ALL monitored diffs are Landed (status=Closed/Committed) or Abandoned.

### Step 1: Check CI Signals
For each diff:
  meta phabricator.ci.signals list -n DXXX --status=failed --limit=500

### Step 2: Check Review Comments
For each diff:
  meta phabricator.diff comments -n DXXX

Look for unresolved inline comments, reviewer requests, and suggested changes.

### Step 3: Fix Issues

**What to fix:**
- Lint errors and formatting issues (`arc f`, `arc lint -a`)
- Import errors (missing/unused imports)
- Type errors (wrong annotations, missing return types)
- Simple test failures where the fix is obvious from the error message
- Reviewer comments requesting changes — attempt to address ALL actionable
  feedback, including descriptive requests like "add error handling here",
  "consider this edge case", "rename this for clarity", etc.
- Apply any explicit code suggestions from reviewers
- Basically anything you are confident you can fix correctly

**What NOT to fix (alert via gchat instead):**
- Comments that are questions or open-ended discussions (not action items)
- Structural changes spanning many files (e.g., "refactor this pattern
  across the codebase")
- Changes where you are not confident the fix is correct
- Infrastructure/CI flakes unrelated to the code itself

**When you encounter something you cannot fix**, send a gchat message to
the diff author alerting them. Include the diff number, the issue, and
why you couldn't address it. Use the gchat skill to send the message.

### Step 4: After Making Fixes
If you made changes to any diff in the stack:
1. Navigate to the correct commit: `sl goto --reason "..." <hash>`
2. Run `arc f` to format changed files
3. Run `arc lint` to verify no new lint issues
4. `sl amend --reason "amend fixes | sl help amend"` (no -m flag, preserve message)
5. `jf submit --draft` to update the diff on Phabricator
6. If working on a stack, repeat for each diff you modified

### Step 5: Print Status Summary
After each iteration, print:

===== DIFF MONITOR STATUS — [timestamp] =====

DXXXXXXXX: [Title]
  Review:   Needs Review / Accepted / Needs Revision / Landed / Abandoned
  CI:       X passed, Y failed, Z running
  Failed:   [signal names]
  Reviewers: [name (status), ...]
  Action:   [what you fixed, or "No action needed"]

[repeat for each diff]

Next check in 5 minutes.
==============================================

### Step 6: Update Changelog
Append to `/tmp/diff_monitor_log.md` (create if needed). Each entry:
- Timestamp
- Diff affected
- Issue found (CI signal name, reviewer comment text, etc.)
- Fix applied (what you changed)
- Whether jf submit was run
Do NOT commit this file.

## Stack Ready Notification

If you are monitoring a stack of MORE THAN ONE diff, and in any iteration you
detect that ALL diffs have:
- Clean CI (no failed signals)
- All reviewers have accepted (status = Accepted)

Then send a gchat message to the diff author saying the stack is ready to land,
listing each diff and its title. Only send this notification once — track
whether you've already sent it to avoid duplicates.

This does NOT apply when monitoring a single diff.

## When to Stop

Stop monitoring when ALL diffs are Landed or Abandoned. Print a final summary
of everything you did during the session, including total fixes applied, diffs
that landed, and any unresolved issues you alerted via gchat.

## Safety Rules

- Never force-push or use destructive sl operations
- Never bypass EdenFS infosec filter warnings — answer "no" and stop
- Always preserve the `Differential Revision:` line in commit messages
- Use `sl amend` without -m to keep existing commit message
- Only use `jf submit --draft` — never `--update-fields`
- Always include `--reason "..."` on every sl command (except sl help)
PROMPTEOF

# --- Delegate to clown.sh ---
echo ""
exec "${SCRIPT_DIR}/clown.sh" -b "$REPO_TYPE" -- \
    --initial-prompt "$(cat "$PROMPT_FILE")"
