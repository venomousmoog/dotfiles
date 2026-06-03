---
name: done
description: End-to-end workflow for finishing work and shipping diffs. Runs deslop, self-review, personal review checks, iterates through the commit stack bottom-to-top, submits each diff with inferred reviewers and clean descriptions/test plans, then monitors CI. Use when the user says "done", "ship it", "submit", "let's land this", "prepare for review", "clean up and submit", or indicates they've finished coding and want to get their changes reviewed. Also use when asked to check CI on submitted diffs or to go through a stack and prepare it for review.
---

# Done: Finish and Ship Your Stack

Automates the full workflow from "code complete" to "diffs submitted and CI passing."

**CRITICAL: This is an uninterruptible workflow. Execute ALL phases in sequence without pausing for user input between steps (except where explicitly noted). After each sub-skill invocation (deslop, review-diff, creating-or-updating-diffs, fixing-diffs) completes, immediately continue to the next step. Do NOT stop and wait for the user after any intermediate step.**

## Workflow

```
Discover stack
  → For each commit (bottom → top):
      deslop → lint → self-review → personal checks
        → fix & amend → write metadata → submit
  → Monitor CI
  → Fix failures (keeping metadata accurate)
```

## Phase 1: Discover

1. Run `sl ssl` to see the stack with diff statuses
2. Identify draft commits needing submission or update
3. Create a task per commit to track progress
4. Navigate to the bottom of the stack with `sl bottom`

If there are uncommitted changes, ask the user whether to amend into the current commit or create a new one.

## Phase 2: Process Each Commit (Bottom → Top)

After any step that modifies files, run `sl amend` to fold changes into the current commit.

### 2.1 Deslop

Invoke `/deslop` on changed files. Amend if changes were made.

### 2.2 Lint & Format

```bash
arc f
arc lint -a
```

Amend if fixes were applied.

### 2.3 Self-Review

Invoke `/source-control-at-meta:review-diff` on the current commit. Address significant issues and amend.

### 2.4 Personal Review Checks

Read `references/review-requirements.md` from this skill's directory for the user's personal criteria. Evaluate the commit against each requirement. Fix gaps and amend.

### 2.5 Write/Update Metadata

**The description and test plan describe what the code does NOW — not the history of changes.**

If steps 2.1–2.4 changed the code, don't add "fixed lint" or "addressed review feedback." Re-read the diff and write metadata that accurately describes the final state.

Invoke `/source-control-at-meta:creating-or-updating-diffs` to write or update:

- **Title**: Concise summary of what the diff does
- **Summary**: What changed, why, and context a reviewer needs. Don't hard-wrap paragraphs.
- **Test Plan**: How the change was verified — commands run, what was checked, what was observed

### 2.6 Infer Reviewers & Submit

Determine reviewers from the primary directory of changed files. Read `references/reviewer-map.md` for the mapping. If no mapping matches, ask the user.

**Always submit as draft** (`jf submit --draft`). Do NOT publish unless the user explicitly asks to publish. Draft lets CI run and reviewers see it without sending noisy notifications for a diff that might still need CI fixes.

Use `jf template` to set metadata (title, summary, test plan, reviewers), then `jf submit --draft` to create or update the diff.

After submission, mark the commit's task complete and run `sl next`.

## Phase 3: Monitor CI (MANDATORY)

You MUST monitor CI after submission — do not stop after submitting. This is part of the workflow, not an optional follow-up.

1. Wait 2–3 minutes for CI signals to start
2. Run `sl ssl` to check statuses for each submitted diff
3. If signals are still pending, wait and check again (up to 3 checks, ~2 min apart)
4. For failing signals, invoke `/source-control-at-meta:fixing-diffs`
5. After fixing, re-examine the description and test plan — if the fix changed what the code does (not just how), update the metadata. The question is always: "does this description still accurately describe the diff?"
6. Amend and resubmit (`jf submit --draft`)
7. Repeat until CI is green or only known-flaky failures remain
8. Once CI is green (or only flaky failures remain), report the final status and ask the user if they want to publish (`jf publish`)

## Principles

- **Metadata = current truth**: Description and test plan are a snapshot of what the diff does right now. After every fix, verify they're still accurate. Update if not — but don't turn them into a changelog.
- **One commit at a time**: Process bottom → top. Don't skip ahead.
- **Amend, don't create**: All fixes go into the current commit via `sl amend`.
- **Ask before big changes**: If review reveals issues needing significant refactoring, pause and ask.
- **Don't invent work**: If deslop and lint find nothing, move on.
