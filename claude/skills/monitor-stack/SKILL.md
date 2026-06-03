---
name: monitor-stack
description: Use when diffs are submitted and need ongoing monitoring for CI signals and reviewer comments. Watches for comments from the user and others, fixes what the user asks, critically evaluates external suggestions, replies to every comment with what was done, and resolves them.
---

# Monitor Stack

Monitors submitted diffs for CI signals and reviewer comments until the stack is stable.

## Workflow

```
Discover submitted diffs (sl ssl)
  → Loop:
      Poll CI signals + new comments
        → CI failure → /source-control-at-meta:fixing-diffs
        → User's comment → implement the fix
        → Other's comment → analyze, push back if risky
        → Reply with deslopped summary → resolve comment
        → Amend & resubmit if changes made
  → Until: CI green + no unresolved actionable comments
  → Report final status
```

## Phase 1: Discover

1. Run `whoami` to determine the current user's identity
2. Run `sl ssl` to get the stack with diff numbers and CI statuses
3. Identify all submitted diffs (draft or published)
4. Create a task per diff to track progress

## Phase 2: Monitor Loop

Poll every 2-3 minutes. For each diff in the stack:

### 2.1 Check CI Signals

For each diff, use `mcp__plugin_meta_mux__get_phabricator_diff_details` with:
- `include_ci_overall_status=true`
- `include_ci_signal_counts=true`

**CRITICAL: Always also check for critical failures explicitly** by fetching `include_failing_ci_signals=true` with `signal_status_filter=critical` on every cycle — not just when test signals fail. Merge validation failures, autodeps errors, and target determinator failures are non-test critical signals that block landing but don't show up in test signal counts.

Common critical non-test failures to watch for:
- **Merge Validation**: the diff has a merge conflict with master → rebase with `sl pull --rebase` and resubmit
- **autodeps-error**: BUCK file parse error (bad load path, undefined variable) → fix the BUCK file
- **citadel-orchestrator**: target determinator failure, often caused by BUCK parse errors → same root cause as autodeps

For test failures, invoke `/source-control-at-meta:fixing-diffs`.

### 2.2 Fetch Comments

Use `mcp__plugin_meta_mux__get_phabricator_diff_details` to get comments on each diff. Track which comments have already been processed to avoid re-handling.

### 2.3 Triage Comments

For each new unresolved comment, identify the author and act accordingly:

**User's own comments** (matches `whoami`):
- Treat as fix instructions — implement the requested change
- Amend the commit

**Comments from others** (AI reviewers, human reviewers):
- Analyze the suggestion in context of the diff's intent
- If the suggestion could cause problems (regressions, conflicts with the fix's purpose, architectural issues):
  - Reply explaining concretely why the suggestion is problematic
  - Do NOT implement
- If the suggestion is valid and safe:
  - Implement the change
  - Amend the commit

### 2.4 Reply & Resolve

After every action (fix, push-back, or implementation):

1. Draft a reply summarizing what was done or why you pushed back
2. Deslop the reply — concise, direct, no filler or hedging
3. Post the reply to the comment
4. Resolve the comment

### 2.5 Update & Resubmit

If any changes were made to a diff:

1. `sl amend` to fold changes into the commit
2. Re-read the diff and verify metadata (title, summary, test plan) still accurately describes what the code does — update if the change altered behavior, not just style
3. `arc f` and `arc lint -a`
4. `jf submit --draft` to resubmit

## Phase 3: Completion

Continue the loop until:
- CI is green: zero critical signals (including merge validation), all test signals pass. Warnings are acceptable.
- No unresolved actionable comments remain

Report final status to the user. Ask if they want to publish (`jf publish`).

## Principles

- **User comments are instructions**: Always implement what the user asks in their own comments.
- **External comments deserve scrutiny**: Don't blindly implement suggestions that could break the fix. The user's intent comes first. Push back with a concrete reason when a suggestion is risky.
- **Every action gets a reply**: Never silently fix or ignore a comment. Reply with what you did and why.
- **Deslop your replies**: No "Great suggestion!", no "I've gone ahead and...", no hedging. State what changed or why it didn't.
- **Metadata stays current**: After any code change, verify the diff description still matches reality.
