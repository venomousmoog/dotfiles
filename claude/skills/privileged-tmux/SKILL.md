---
name: privileged-tmux
description: >-
  Run a command in a real, persistent, TTY-backed bash shell on the shared tmux
  server instead of the stateless sandboxed Bash tool. Use this whenever you need
  to run privileged / sudo / root system-administration commands; run in the real
  unsandboxed login environment (full PATH, real network, no per-command approval
  gating); use an interactive command, prompt, or REPL that needs a TTY (sudo
  password, ssh, psql, python -i, fdb/adb shells); keep shell state (cd, exported
  vars, background jobs) across multiple commands; or launch a long-running
  process you'll check on later. Each agent gets its OWN private bash session on
  the shared server (auto-named from your Claude session id) so you never clobber
  other agents' panes. Reach for this skill when a command fails or is blocked in
  the normal Bash tool because of sandboxing/permissions, needs a terminal, needs
  sudo, or must persist state between calls -- even if the user never mentioned
  tmux.
---

# privileged-tmux

The normal **Bash tool is stateless** (each call is a fresh process), has **no
TTY**, and runs under the harness sandbox/permission gating. That's fine for most
work. But some commands need a *real* shell:

- **privileged / sudo / system-admin** commands (services, package installs, `/etc`),
- the **real, unsandboxed login environment** (full `PATH`, real network, no
  per-command approval),
- **interactive** programs that need a terminal or prompt for input (sudo
  password, `ssh`, `psql`, `python -i`, `adb shell`),
- **state that must persist** across commands (`cd`, `export`, background jobs),
- **long-running** processes you start now and check on later.

For those, drive a bash pane on the **shared tmux server** that `shared-tmux.sh`
creates on socket `/tmp/tmux-shared/shared`. It's a persistent, TTY-backed shell
in the full login environment.

## The one rule: your own session

The shared server is shared by **many agents at once**. If you send keystrokes to
a pane another agent is using, you corrupt their command and yours. So:

> **Create and use your OWN session, and only ever touch that session.**

You don't manage this by hand — `ptmux.sh` does it for you. It derives a session
name from your Claude session id (`agent-<first8>`), creates that session running
**bash explicitly** (the server's default shell is pwsh, not bash), and only ever
drives that one session. Two different agents get two different names
automatically, so you can't collide.

## Helper: `ptmux.sh`

All interaction goes through one script:

```
~/.claude/skills/privileged-tmux/scripts/ptmux.sh <subcommand> [args]
```

Common pattern — just run a command and get its output + exit code:

```bash
~/.claude/skills/privileged-tmux/scripts/ptmux.sh run "sudo systemctl restart sshd && systemctl is-active sshd"
```

`run` blocks until the command finishes, prints combined stdout+stderr, and exits
with the command's **own exit code** — so you can branch on success just like a
normal Bash tool call. State persists, so a later call sees the same `cwd` and
env:

```bash
ptmux.sh run "cd /etc && pwd"     # -> /etc
ptmux.sh run "pwd"                # -> /etc   (same pane, state kept)
```

### Subcommands

| Command | What it does |
|---|---|
| `ensure` | Create the server (if down) + your bash session; wait until ready; print the name. Optional — `run`/`start`/`send` auto-ensure. |
| `run "<cmd>" [timeout]` | Run, **wait**, print output, exit with cmd's exit code. `timeout` seconds (default 600). On timeout: returns 124, prints partial output, command keeps running. |
| `start "<cmd>"` | **Fire-and-forget** for long-running/interactive things. Returns immediately; output stays in the pane (read with `capture`). |
| `send "<text>"` | Type literal text + Enter — answer a prompt, feed a REPL, type a password. |
| `key <keys...>` | Send raw tmux keys, no Enter — e.g. `key C-c` to interrupt, `key Up Enter` to rerun. |
| `capture [lines]` | Print the pane's current contents; `lines` adds that much scrollback. |
| `name` | Print your resolved session name. |
| `list` | List all `agent-*` sessions on the shared server. |
| `kill` | Kill your session and clean its workdir (do this when fully done). |

Tip: export `PTMUX=~/.claude/skills/privileged-tmux/scripts/ptmux.sh` once at the
top of a Bash call and use `$PTMUX run "..."` to keep lines short.

## Recipes

**A command the Bash tool blocks/sandboxes** — run it in the real shell:

```bash
ptmux.sh run "sudo dnf install -y htop"
```

**Interactive: a command that prompts** — start it, watch, answer:

```bash
ptmux.sh start "ssh somehost"
ptmux.sh capture                 # see the password/fingerprint prompt
ptmux.sh send "yes"              # accept fingerprint
ptmux.sh send "$MY_PASSWORD"     # answer the prompt
ptmux.sh capture                 # confirm you're in
```

(`send` types literally, so it's safe for passwords and arbitrary text. Don't echo
secrets into your own output.)

**A REPL:**

```bash
ptmux.sh start "python3 -i"
ptmux.sh send "import os; print(os.getuid())"
ptmux.sh capture
ptmux.sh send "exit()"
```

**Long-running job — start now, poll later:**

```bash
ptmux.sh start "buck2 build //foo:bar 2>&1 | tee /tmp/build.log"
# ... do other work ...
ptmux.sh capture 200             # check progress
ptmux.sh key C-c                 # interrupt if needed
```

**Need a second pane** (e.g. one server + one client) — override the name:

```bash
PTMUX_SESSION=agent-myserver ptmux.sh start "python3 -m http.server 8000"
PTMUX_SESSION=agent-myclient ptmux.sh run   "curl -s localhost:8000 | head"
```

**Clean up** when the task is done so you don't leave panes around:

```bash
ptmux.sh kill
```

## Letting a human watch

Everything you run is visible in the shared session. A human can open a live view
of all agent panes with the viewer in the dotfiles repo:

```bash
~/src/dotfiles/scripts/shared-tmux-view.sh              # read-only switcher (C-b n/p between agents)
~/src/dotfiles/scripts/shared-tmux-view.sh --dashboard  # tiled live mirror of every agent at once
```

If a user asks to "watch the agents" or "see what the agents are doing," point
them at that script.

## Gotchas

- **Don't rely on the server's default shell.** It's pwsh here; `ptmux.sh` always
  launches bash for you. If you ever call tmux directly, pass `bash` explicitly.
- **`run` captures via a logfile, not screen-scraping**, so big output and colors
  are fine and there's no prompt noise. `capture` *does* scrape the screen — use
  it for interactive/long-running watching, not for clean output.
- **Don't read other agents' sessions.** Use `list` to see them, but only ever
  drive your own (the default name).
- **`exit`/`logout` closes your pane.** Commands run in your live shell (so `cd`
  and `export` persist), which means a command that calls `exit` ends the session.
  `run` detects this and returns 125 instead of hanging; just call any command
  again to recreate the session. Use a subshell — `(... ; exit 0)` — if you really
  need `exit`.
- **Files are shared.** `/tmp` is visible both to the sandboxed Bash tool and to
  the pane, so you can write a script with the Bash tool and run it in the pane.
- **First call may pause** a few seconds on a cold machine while the pane's
  `~/.bashrc` finishes the dotfiles bootstrap; that's expected.

## Files

- Agent helper: `scripts/ptmux.sh` (this skill).
- Server bootstrap: `~/src/dotfiles/scripts/shared-tmux.sh` (creates the socket).
- Human viewer: `~/src/dotfiles/scripts/shared-tmux-view.sh`.
