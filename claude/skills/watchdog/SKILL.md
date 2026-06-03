---
name: watchdog
description: "Launch a background watchdog to monitor the current Claude Code session. Detects when Claude stops and autonomously continues, answers questions from plans, or handles human-task blockers. Use: /watchdog <profile>, /watchdog stop, /watchdog list, /watchdog create-style <name>."
argument-hint: "<profile> | stop | list | create-style <name> | instruct <profile>"
---

# Watchdog Skill

A background Python process that monitors your Claude Code session and autonomously responds when Claude is waiting for input. It classifies the wait type (continue, question, human task, complex) and takes appropriate action based on your profile settings.

## Subcommand Dispatch

Parse the first argument to determine which subcommand to run:

- `stop` → Stop Watchdog
- `list` → List Profiles
- `create-style <name>` → Create Profile
- `instruct <profile>` → Add instructions or workarounds to a profile
- `<anything else>` → Start Watchdog with that profile name

### `/watchdog <profile-name>` — Start a watchdog

1. **Resolve profile** from `~/.claude/skills/watchdog/profiles/<name>.json`. If not found, list available profiles and stop.

2. **Check for existing watchdog** at `~/.claude-watchdog/<session-id>.pid`:
   - If file exists, check if process is alive (`kill -0 <pid>`)
   - If alive: report "Watchdog already running (PID <pid>)" and stop
   - If dead: clean up stale PID file and continue

3. **Gather environment**:
   ```bash
   # Session ID
   echo $CLAUDE_CODE_CURRENT_SESSION_ID

   # Pane ID
   tmux display-message -p '#{pane_id}'

   # Tmux server PID
   tmux display-message -p '#{pid}'
   ```

4. **Encode CWD** to derive the project directory path:
   - Take the current working directory
   - Replace `/` with `-`, strip leading `-`
   - Project dir: `~/.claude/projects/<encoded-cwd>/`

5. **Create runtime directory**:
   ```bash
   mkdir -p ~/.claude-watchdog
   ```

6. **Launch the watchdog** as a background process:
   ```bash
   nohup python3 ~/.claude/skills/watchdog/scripts/watchdog.py \
     --session-id "$SESSION_ID" \
     --project-dir "$PROJECT_DIR" \
     --pane-id "$PANE_ID" \
     --tmux-pid "$TMUX_PID" \
     --profile "$PROFILE_PATH" \
     > ~/.claude-watchdog/${SESSION_ID}.log 2>&1 &
   ```

7. **Write PID** to `~/.claude-watchdog/<session-id>.pid`

8. **Confirm** to the user: "Watchdog started with profile '<name>' (PID <pid>). Logs: ~/.claude-watchdog/<session-id>.log"

### `/watchdog stop` — Stop the watchdog

1. Read PID from `~/.claude-watchdog/<session-id>.pid` (use `$CLAUDE_CODE_CURRENT_SESSION_ID`)
2. If no PID file: report "No watchdog running for this session"
3. Send `SIGTERM`: `kill <pid>`
4. Remove PID file
5. Confirm: "Watchdog stopped (PID <pid>)"

### `/watchdog list` — List available profiles

1. List JSON files in `~/.claude/skills/watchdog/profiles/`
2. For each file, read and display the `name` and `description` fields
3. If no profiles exist, suggest using `/watchdog create-style <name>`

### `/watchdog create-style <name>` — Create a new profile

Conduct an interactive interview to build a profile. Ask these questions one at a time in your response and wait for the user to reply (do NOT use AskUserQuestion — just ask conversationally):

1. **Session type** — What kind of work will this profile be used for?
   - Options: planning, coding, debugging, research, other (free text)

2. **Auto-continue** — When Claude finishes a step and stops, should the watchdog send "continue"?
   - Options: always / smart (use classifier) / never
   - Map to: `auto_continue: true` (always), `auto_continue: true + use_llm: true` (smart), `auto_continue: false` (never)

3. **Human task handling** — When Claude is blocked on something that needs human action (run a command, visit a URL), should the watchdog try known workarounds?
   - Options: yes (try workarounds) / no (always flag for user)

4. **Question answering** — When Claude asks a question, should the watchdog try to answer from a plan file?
   - If yes: ask for plan file path, or "auto" to search `~/.claude/plans/` for the most recent plan
   - Map to: `answer_questions_from_plan: true/false`, `plan_file: <path or null>`

5. **LLM classification** — Use an LLM call for smarter classification of wait states, or use heuristics only?
   - Options: llm / heuristics
   - Note: LLM mode costs ~$0.01-0.05 per classification call

6. **Custom context** — Any additional instructions for the classifier? (free text, or skip)
   - Example: "This is a fully autonomous coding session, always continue unless there's an error"

7. **Max auto-continues** — Maximum number of times the watchdog will auto-continue before stopping (default: 50)

After collecting answers, assemble into JSON and write to `~/.claude/skills/watchdog/profiles/<name>.json`:

```json
{
  "name": "<name>",
  "description": "<session-type> profile",
  "auto_continue": true,
  "handle_human_tasks": true,
  "answer_questions_from_plan": false,
  "plan_file": null,
  "max_auto_continues": 50,
  "use_llm": false,
  "classifier_context": "",
  "debounce_seconds": 3.0,
  "created_at": "<ISO timestamp>"
}
```

Confirm: "Profile '<name>' created at ~/.claude/skills/watchdog/profiles/<name>.json"

### `/watchdog instruct <profile-name>` — Add instructions or workarounds to a profile

Verify the profile exists at `~/.claude/skills/watchdog/profiles/<name>.json`. If not, list available profiles and stop.

Ask the user: "What would you like to add to the **<name>** profile?"
- **1) A workaround** — a pattern/response pair for when Claude asks you to do something specific
- **2) An instruction** — a general rule for how the watchdog should behave with this profile

**If workaround:**
1. Ask: "What pattern should this match? (describe the situation or give a regex)"
2. Ask: "What should the watchdog respond with? (or 'NEVER_AUTO' to always flag for user)"
3. Read the profile workarounds file at `~/.claude/skills/watchdog/profiles/<name>.workarounds.md`. If it doesn't exist, create it with a header.
4. Append a new entry:
   ```
   ### <descriptive name>
   **Pattern:** `<regex>`
   **Workaround:** <response text or NEVER_AUTO>
   ```
5. Confirm what was added and show the file path.

**If instruction:**
1. Ask: "What instruction should the watchdog follow for this profile?"
   Example: "Never auto-continue after test failures" or "Always continue even if Claude asks a question"
2. Read the profile instructions file at `~/.claude/skills/watchdog/profiles/<name>.instructions.md`. If it doesn't exist, create it with a header.
3. Append the instruction as a bullet point.
4. Confirm what was added.

**Per-profile files:**
- `profiles/<name>.workarounds.md` — profile-specific workarounds (checked before global workarounds)
- `profiles/<name>.instructions.md` — profile-specific instructions (appended to `classifier_context` at runtime)

The watchdog loads both global and per-profile workarounds at startup. Profile workarounds are checked first (higher priority). Profile instructions are read and prepended to the classifier context for both heuristic and LLM classification.
