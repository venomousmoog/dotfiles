---
name: review-queue
description: Summarize new diffs from the Aria AI review channel — pulls diff notifications from GChat, launches parallel AI reviews, and presents concise summaries with verdicts. Optionally posts review feedback to Phabricator with your confirmation. Triggers on "review queue", "what diffs need review", "check review channel", "new diffs".
allowed-tools: Read, Bash(sl:*), Bash(jf:*), Bash(date:*), Bash(cat:*), Bash(mktemp:*), Bash(meta:*), Bash(rm:*), Agent, mcp__plugin_meta_mux__get_phabricator_diff_details, AskUserQuestion
---

# Review Queue

Pull new diffs from the Aria AI review channel, summarize each one
concurrently, and present actionable verdicts. Optionally share AI
review feedback on Phabricator with your confirmation.

## Configuration

REVIEW_SOURCE_SPACE: AAQAZ_RE2jM

## Step 1: Pull New Diffs from GChat

Read recent messages from the Aria AI diff review space
(AAQAZ_RE2jM) to find diff notifications.

Determine the lookback window — the later of:
- The last time this skill was run (from the state file)
- 24 hours ago

Track the last-check timestamp in a state file. Take the later of the
state-file timestamp and 24-hours-ago — a stale state file (skill not
run for days) must not pull in a multi-day backlog of diffs:
```bash
STATE_FILE="$HOME/.review-queue-last-check"
TWENTY_FOUR_HOURS_AGO=$(date -d '24 hours ago' +%s)
STATE_TS=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
if [ "$STATE_TS" -gt "$TWENTY_FOUR_HOURS_AGO" ]; then
    LAST_CHECK="$STATE_TS"
else
    LAST_CHECK="$TWENTY_FOUR_HOURS_AGO"
fi
```

Read messages from the space since that timestamp and extract diff
numbers (D{number} pattern) from the messages.

For each diff found, use
`mcp__plugin_meta_mux__get_phabricator_diff_details` to check its
current status. Keep only diffs that are still in "Needs Review".

Exclude the current user's own diffs — no need to review your own
work.

If no new diffs need review, tell the user and stop. Do NOT advance
the timestamp yet — that happens only after the user has actually
seen the reviews (end of Step 3). Advancing the cursor here would
silently skip diffs if the workflow crashes mid-flight.

## Step 2: Launch Concurrent Reviews

For each diff, launch a subagent using the Agent tool. Launch ALL
subagents in a SINGLE message so they run concurrently.

Each subagent prompt:

```
Review Phabricator diff <DIFF_ID>: "<DIFF_TITLE>" by <AUTHOR>.

Use the mcp__plugin_meta_mux__get_phabricator_diff_details tool to
fetch the diff details with:
- phabricator_diff_number: "<DIFF_ID>"
- include_raw_diff: true
- include_diff_summary: true
- include_test_plan: true
- include_diff_author: true

Provide a concise review with:
1. Summary (2-3 sentences): What does this diff do?
2. Key Changes: The most important files/functions modified
3. Potential Issues: Any bugs, edge cases, missing error handling,
   or design concerns
4. Test Coverage: Is the test plan adequate?
5. Verdict: One of: LOOKS_GOOD, MINOR_ISSUES, NEEDS_ATTENTION,
   CRITICAL_ISSUES

Keep it concise — focus on what the reviewer needs to know to make
a decision.
```

## Step 3: Present Results

After all subagents complete, present a summary of each diff.

Format each review:

```
## <VERDICT_EMOJI> <DIFF_ID>: <TITLE>
**Author:** <AUTHOR> | **Verdict:** <VERDICT>

**Summary:** <2-3 sentence summary>

**Key Changes:**
- <change 1>
- <change 2>

**Potential Issues:**
- <issue or "None spotted">

**Test Coverage:** <assessment>

https://www.internalfb.com/diff/<DIFF_ID>
```

Verdict scale:
- LOOKS_GOOD — no issues found, safe to accept
- MINOR_ISSUES — small concerns, but acceptable
- NEEDS_ATTENTION — notable issues that should be addressed
- CRITICAL_ISSUES — bugs or design problems that block landing

Once the summaries have been presented to the user, advance the
last-check cursor — at this point the reviews have been delivered
and re-running the skill should not re-show the same diffs:

```bash
date +%s > "$STATE_FILE"
```

If any earlier step crashed, the cursor stays where it was and the
next invocation will pick the same diffs back up.

## Step 4: Offer to Post Feedback

After presenting all summaries, ask the user:

```
header: "Post feedback"
question: "Would you like to post any of these reviews as comments
on the diffs?"
options:
  - label: "Post all reviews"
    description: "Add AI review summaries as comments on each diff"
  - label: "Pick specific diffs"
    description: "Choose which diffs to post feedback on"
  - label: "No, just reading"
    description: "Don't post anything to Phabricator"
```

If the user wants to post:
1. For each selected diff, show the exact comment that will be
   posted and ask for confirmation before posting.
2. Write the review body to a temp file using `mktemp` (do NOT
   interpolate AI-generated content into a shell-quoted string —
   reviews can contain backticks, `$()`, double quotes, and other
   shell metacharacters that break the command or, worse, execute).
   Then post via `meta phabricator.diff comment --number=<diff>
   --message-file=<temp-path>`.
3. Prefix each comment body with "AI Review Summary:" so it is
   clearly labeled as AI-generated feedback.
4. Delete the temp file after posting.

## Review Quality Guidelines

When reviewing, focus on:

**High priority (flag these):**
- Bugs, logic errors, race conditions
- Security vulnerabilities
- Missing error handling for failure paths
- Data corruption risks

**Medium priority (note these):**
- Missing test coverage for new behavior
- Performance concerns
- API design issues

**Skip (do not flag):**
- Style/formatting (lint handles this)
- Import ordering
- Comment quality
- Naming preferences
