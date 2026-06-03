---
name: progress-monitoring
description: Use when working on any multi-step debugging, building, testing, or problem-solving task. Monitors elapsed time and detects when progress has stalled after 20+ minutes or 3+ failed approaches. Also monitors background task durations for unexpected delays.
---

# Progress Monitoring

Self-monitor for stalled progress during debugging, building, testing, or problem-solving. Detect when you're spinning without forward movement and surface it to the user instead of silently burning time.

## The Iron Law

```
NO SILENT SPINNING — IF 20 MINUTES PASS WITH 3+ FAILED APPROACHES, STOP AND SUMMARIZE
```

## Part 1: Stuck Detection

### Process

1. When starting a debugging/build/problem-solving effort, run `date +%s` and note the timestamp as `$START_TIME`
2. After each failed attempt or approach change, run `date +%s` and compare to `$START_TIME`
3. Track the number of distinct approaches tried and what each one yielded
4. Trigger a progress check when ANY of these conditions are met:
   - 20+ minutes elapsed AND 3+ approaches have failed
   - Same error message recurring after a "fix"
   - Cycling back to an approach already tried
   - 20+ minutes elapsed AND no measurable forward progress

### When Triggered

Print to console:

```
## Progress Check

**Goal:** [what we're trying to accomplish]

**Time spent:** [N] minutes

**Approaches tried:**
1. [approach] — [why it failed]
2. [approach] — [why it failed]
3. [approach] — [why it failed]

**Current theory:** [best guess at root cause]

**Next approach:** [what we'll try next]
```

Then use `AskUserQuestion` to ask the user whether to:
- Continue with the proposed next approach
- Try something different (user provides direction)
- Abandon this path entirely

After pausing, continue working. Do NOT repeat the pause more often than every 20 minutes.

## Part 2: Background Task Timeout Monitoring

When launching background tasks (via `run_in_background`):

1. Note the start time
2. **Standard tasks** (tests, scripts, tool invocations):
   - If no output after **5 minutes**, check on the task and print a note that it's taking longer than expected
   - If still running after **10 minutes**, print a warning and check whether the task is progressing or hung
3. **Build tasks** (buck2, cmake, cargo, etc.):
   - Builds can legitimately be slow — extend the thresholds
   - Warn at **10 minutes**, alert at **20 minutes**
4. For synchronous tool invocations that time out, note the timeout in console output so the user is aware

### How to Check

Use `TaskOutput` with `block: false` to non-blocking check the task's current output. Look for:
- New output lines since last check (task is progressing)
- No new output (task may be hung)
- Error output (task has failed silently)

## Red Flags

Watch for these patterns in your own behavior:

- Trying a variation of an approach that already failed
- Same error message appearing after a "fix"
- Adding workarounds on top of workarounds
- Background task running with no output for 5+ minutes
- Feeling "stuck" but not surfacing it
- Reverting a change and trying the same thing again
- Searching for the same thing multiple times hoping for different results

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Almost there, one more try" | If 3 have failed, stop and reconsider |
| "Don't want to interrupt flow" | 20 wasted minutes is worse than a pause |
| "User will notice eventually" | User may be AFK or in another tab |
| "Background task is probably fine" | Hung tasks waste time silently |
| "Build is just slow" | Check for actual progress, not just running |
| "This variation is different" | If the core approach failed, a tweak won't save it |
| "I just need to find the right flag" | If you've tried 3+ flags, the problem is elsewhere |

## What This Skill Does NOT Do

- This is not a task tracker or project management tool
- This does not replace the user's judgment about when to stop
- This does not apply to research/exploration tasks where breadth is the point
- This only triggers during active problem-solving where a specific goal exists

## The Mission

The worst outcome is Claude silently burning 45 minutes on a dead-end approach while the user assumes progress is being made. Surface stalls early, give the user enough context to redirect, and never rationalize continued spinning. A 30-second pause to check in saves 20 minutes of wasted effort.
