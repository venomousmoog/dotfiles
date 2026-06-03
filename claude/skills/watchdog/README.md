# Watchdog

A background process that monitors your Claude Code session and autonomously responds when Claude is waiting for input. Useful for long-running or overnight sessions where you don't want Claude to stall waiting for "continue" or for you to run a command in another terminal.

## Quick Start

```
/watchdog create-style coding    # create a profile interactively
/watchdog coding                 # start the watchdog with that profile
/watchdog stop                   # stop it when done
```

## Commands

| Command | Description |
|---------|-------------|
| `/watchdog <profile>` | Start the watchdog using the named profile |
| `/watchdog stop` | Stop the running watchdog for this session |
| `/watchdog list` | Show available profiles |
| `/watchdog create-style <name>` | Create a new profile via interactive interview |
| `/watchdog instruct <profile>` | Add a workaround or instruction to a profile |

## How It Works

The watchdog runs as a background Python process that monitors two data sources:

1. **Session JSONL** (`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`) — the conversation log. The watchdog tails new lines to maintain a rolling window of recent messages.

2. **Hook state file** (`~/.claude-tmux-statusline/state/<tmux-pid>/<session-id>.json`) — written by existing tmux statusline hooks. When the status transitions to `"waiting"`, the watchdog activates.

When Claude stops and the hook state becomes `"waiting"`:
1. A 3-second debounce timer starts (configurable via `debounce_seconds`)
2. If still waiting after the debounce, the watchdog classifies the wait type
3. Based on the classification and profile settings, it either sends a response via `tmux send-keys` or does nothing

## Wait Classifications

| Type | Meaning | Default Action |
|------|---------|---------------|
| `continue` | Claude finished a step, can proceed | Send "continue" (if `auto_continue` enabled) |
| `human_task` | Claude needs you to do something external | Look up workaround, send if found |
| `question` | Claude is asking a design/architecture question | Answer from plan file if configured |
| `complex` | Ambiguous or risky situation | Do nothing |

Classification uses either heuristic pattern matching (free) or an LLM call via `claude -p` (~$0.01-0.05 per call), controlled by the `use_llm` profile setting.

## Profiles

Profiles are JSON files in `~/.claude/skills/watchdog/profiles/`. Create them with `/watchdog create-style <name>` or write them manually:

```json
{
  "name": "coding",
  "description": "Autonomous coding sessions",
  "auto_continue": true,
  "handle_human_tasks": true,
  "answer_questions_from_plan": false,
  "plan_file": null,
  "max_auto_continues": 50,
  "use_llm": false,
  "classifier_context": "",
  "debounce_seconds": 3.0,
  "created_at": "2026-03-30T12:00:00Z"
}
```

### Profile Fields

| Field | Type | Description |
|-------|------|-------------|
| `auto_continue` | bool | Send "continue" when Claude finishes a step |
| `handle_human_tasks` | bool | Try workarounds from `references/human-task-workarounds.md` |
| `answer_questions_from_plan` | bool | Answer questions using a plan file |
| `plan_file` | string/null | Path to plan file, or null to auto-detect from `~/.claude/plans/` |
| `max_auto_continues` | int | Cap on auto-continues per session (default 50) |
| `use_llm` | bool | Use LLM classification instead of heuristics |
| `classifier_context` | string | Extra context for the classifier prompt |
| `debounce_seconds` | float | Wait this long after "waiting" before acting (default 3.0) |

## Safety Guardrails

- **Debounce**: 3s delay after detecting "waiting" before acting; resets if Claude starts working
- **Infinite loop cap**: After 3 identical consecutive classifications, stops acting
- **Auto-continue cap**: `max_auto_continues` per session (default 50)
- **Input sanitization**: Shell metacharacters stripped, responses limited to 500 chars
- **Never bypasses security**: Permission prompts and EdenFS infosec prompts are always classified as `complex` (do nothing)
- **Self-termination**: Exits when session ends, state file disappears, or PID file is removed

## Human Task Workarounds

Workarounds are pattern/action pairs that tell the watchdog how to respond when Claude asks you to do something external.

### Global workarounds

The file `references/human-task-workarounds.md` contains workarounds that apply to all profiles. You can edit this file directly or add entries to the "Custom Entries" section.

### Per-profile workarounds

Each profile can have its own workarounds file at `profiles/<name>.workarounds.md`. Per-profile workarounds are checked **before** global workarounds, so they take priority.

Use `/watchdog instruct <profile>` to add workarounds interactively, or create the file manually:
```
# Workarounds for <profile-name>

### Entry Name
**Pattern:** `regex pattern here`
**Workaround:** Response text to send (or NEVER_AUTO to flag for user)
```

## Per-Profile Instructions

Each profile can have an instructions file at `profiles/<name>.instructions.md` containing general rules for the watchdog. These are prepended to the `classifier_context` at runtime, influencing both heuristic and LLM classification.

Use `/watchdog instruct <profile>` to add instructions interactively, or create the file manually:
```markdown
# Instructions for <profile-name>

- Never auto-continue after test failures
- Always continue when Claude finishes writing a file
- Treat "should I proceed?" as a rhetorical question and continue
```

## Debugging

### Dry-run mode

Reads and classifies but doesn't send any keys:
```bash
python3 ~/.claude/skills/watchdog/scripts/watchdog.py \
  --session-id ID --project-dir DIR --pane-id PANE --tmux-pid PID \
  --profile PROFILE --dry-run
```

### Replay mode

Replay a completed session's JSONL to see what actions would have been taken:
```bash
python3 ~/.claude/skills/watchdog/scripts/watchdog.py \
  --session-id ID --project-dir DIR --pane-id PANE --tmux-pid PID \
  --profile PROFILE --dry-run --replay path/to/session.jsonl
```

### Log inspection

All decisions are logged to `~/.claude-watchdog/<session-id>.log` with timestamps, classifications, and actions taken.

## File Layout

```
~/.claude/skills/watchdog/
├── SKILL.md                          # Skill definition (subcommand dispatch)
├── README.md                         # This file
├── profiles/                         # Profile storage
│   ├── <name>.json                   # Profile config
│   ├── <name>.workarounds.md         # Per-profile workarounds (optional)
│   └── <name>.instructions.md        # Per-profile instructions (optional)
├── scripts/
│   └── watchdog.py                   # Background watchdog process
└── references/
    └── human-task-workarounds.md     # Workaround lookup table

~/.claude-watchdog/                   # Runtime state (created at runtime)
├── <session-id>.pid                  # PID file
├── <session-id>.json                 # Runtime state
└── <session-id>.log                  # Watchdog output log
```
