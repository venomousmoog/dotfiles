#!/usr/bin/env python3
"""
Generates a tmux window title for a Claude Code session using haiku.

Invoked in the background by the Stop hook (when Claude finishes a turn and
the API is idle). Receives session_id, cwd, and tmux pane via arguments.

Only generates a title when:
  - The window title is generic or was previously set by this script
  - The session JSONL has grown significantly since the last generation
  - At least 60s have passed since the last check
"""

import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

LOG_DIR = Path.home() / ".claude-tmux-statusline"
LOG_FILE = LOG_DIR / "debug.log"
DEBUG_FLAG = LOG_DIR / "debug.enabled"

log = logging.getLogger("sync_window_titles")

def setup_logging():
    if DEBUG_FLAG.exists() or os.environ.get("CLAUDE_TMUX_DEBUG") == "1":
        logging.basicConfig(
            filename=str(LOG_FILE),
            level=logging.DEBUG,
            format="%(asctime)s: [title-sync] %(message)s",
            datefmt="%a %b %d %I:%M:%S %p %Z %Y",
        )
    else:
        logging.basicConfig(level=logging.CRITICAL)  # effectively silent

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
STATE_FILE = CLAUDE_DIR / "window-title-state.json"

GENERIC_TITLES = {"bash", "zsh", "nu", "fish", "sh", "~", "claude", "node"}

MIN_CHECK_INTERVAL = 60
MIN_SIZE_CHANGE_BYTES = 2048
MIN_SIZE_CHANGE_PCT = 0.10
MAX_USER_PROMPTS = 15

TMUX_BIN = None


def get_tmux_bin():
    global TMUX_BIN
    if TMUX_BIN:
        return TMUX_BIN
    tmux_env = os.environ.get("TMUX", "")
    if tmux_env:
        parts = tmux_env.split(",")
        if len(parts) >= 2:
            try:
                TMUX_BIN = os.readlink(f"/proc/{parts[1]}/exe")
                return TMUX_BIN
            except OSError:
                pass
    TMUX_BIN = "tmux"
    return TMUX_BIN


def tmux_cmd(*args):
    result = subprocess.run(
        [get_tmux_bin()] + list(args),
        capture_output=True, text=True, timeout=5,
    )
    return result.stdout.strip()


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state))
    tmp.rename(STATE_FILE)


def get_window_for_pane(pane_id):
    """Get window_id, window_name, and @title_source for a pane."""
    raw = tmux_cmd(
        "display-message", "-t", pane_id, "-p",
        "#{window_id}\t#{window_name}\t#{@title_source}",
    )
    parts = raw.split("\t")
    if len(parts) < 2:
        return None, None, None
    return parts[0], parts[1], parts[2] if len(parts) > 2 else ""


def find_session_jsonl(session_id, cwd):
    # Try direct path from cwd first
    if cwd:
        project_path = cwd.replace("/", "-")
        jsonl_file = PROJECTS_DIR / project_path / f"{session_id}.jsonl"
        if jsonl_file.exists():
            return jsonl_file
    # Fallback: search all project directories
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue
        jsonl_file = project_dir / f"{session_id}.jsonl"
        if jsonl_file.exists():
            return jsonl_file
    return None


def extract_user_prompts(jsonl_path):
    prompts = []
    with open(jsonl_path) as f:
        for line in f:
            try:
                entry = json.loads(line)
                if entry.get("type") != "user":
                    continue
                msg = entry.get("message", {})
                content = msg.get("content", "")
                if isinstance(content, list):
                    text_parts = [
                        p.get("text", "")
                        for p in content
                        if isinstance(p, dict) and p.get("type") == "text"
                    ]
                    content = " ".join(text_parts)
                if isinstance(content, str) and content.strip():
                    prompts.append(content.strip()[:300])
            except json.JSONDecodeError:
                continue
    if not prompts:
        return []
    # Always include the first prompt (establishes session intent)
    if len(prompts) <= MAX_USER_PROMPTS:
        return prompts
    return [prompts[0]] + prompts[-(MAX_USER_PROMPTS - 1):]


FILLER_PREFIXES = [
    "please ", "can you ", "could you ", "i'd like to ", "i would like to ",
    "i want to ", "i need to ", "let's ", "lets ", "we should ", "we need to ",
    "help me ", "go ahead and ", "take a look at ", "check ",
]


def generate_title(prompts):
    """Generate a window title from user prompts using heuristics.
    Takes the first substantial prompt, strips filler, and truncates."""
    # Find the first prompt that's long enough to be meaningful
    text = ""
    for p in prompts:
        if len(p) > 10:
            text = p
            break
    if not text:
        text = prompts[0] if prompts else ""

    if not text:
        return None

    # Lowercase and strip filler prefixes (repeatedly)
    text = text.lower().strip()
    changed = True
    while changed:
        changed = False
        for prefix in FILLER_PREFIXES + ["the ", "a ", "an ", "my ", "our "]:
            if text.startswith(prefix):
                text = text[len(prefix):]
                changed = True
                break

    # Cut at first sentence boundary if present
    for sep in (". ", "? ", "! ", " - ", " — "):
        idx = text.find(sep)
        if 10 < idx < 50:
            text = text[:idx]
            break

    # Truncate at word boundary around 40 chars
    if len(text) > 45:
        cut = text.rfind(" ", 0, 45)
        if cut > 15:
            text = text[:cut]
        else:
            text = text[:45]

    # Remove trailing punctuation
    text = text.rstrip(".,;:!?-–— ")

    return text if text else None


def has_changed_significantly(current_size, last_size):
    if last_size == 0:
        return True
    diff = current_size - last_size
    if diff < 0:
        return True
    pct = diff / last_size if last_size > 0 else 1.0
    return diff >= MIN_SIZE_CHANGE_BYTES or pct >= MIN_SIZE_CHANGE_PCT


def is_overwritable(window_name, title_source):
    if title_source == "sync":
        return True
    if window_name.lower() in GENERIC_TITLES:
        return True
    return False


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <session_id> <tmux_pane> [cwd]", file=sys.stderr)
        sys.exit(1)

    session_id = sys.argv[1]
    pane_id = sys.argv[2]
    cwd = sys.argv[3] if len(sys.argv) > 3 else ""

    setup_logging()
    log.debug("started: session=%s pane=%s cwd=%s", session_id, pane_id, cwd)

    if not os.environ.get("TMUX"):
        log.debug("skipped: not in tmux")
        return

    # Get window info for this pane
    window_id, window_name, title_source = get_window_for_pane(pane_id)
    log.debug("window: id=%s name=%s title_source=%s", window_id, window_name, title_source)
    if not window_id:
        log.debug("skipped: no window for pane")
        return

    if not is_overwritable(window_name, title_source):
        log.debug("skipped: title not overwritable")
        return

    # Find session JSONL
    jsonl_path = find_session_jsonl(session_id, cwd)
    if not jsonl_path:
        log.debug("skipped: no JSONL found")
        return

    jsonl_size = jsonl_path.stat().st_size
    log.debug("jsonl: %s (%d bytes)", jsonl_path, jsonl_size)

    # Rate limit
    state = load_state()
    window_state = state.get(window_id, {})
    last_check = window_state.get("last_check", 0)
    last_size = window_state.get("last_size", 0)

    now = time.time()
    if now - last_check < MIN_CHECK_INTERVAL:
        log.debug("skipped: checked %ds ago (min %ds)", int(now - last_check), MIN_CHECK_INTERVAL)
        return

    if not has_changed_significantly(jsonl_size, last_size):
        log.debug("skipped: size unchanged (%d -> %d)", last_size, jsonl_size)
        state[window_id] = {
            "last_check": now,
            "last_size": last_size,
            "session_id": session_id,
        }
        save_state(state)
        return

    log.debug("generating title: size %d -> %d", last_size, jsonl_size)

    # Generate title
    prompts = extract_user_prompts(jsonl_path)
    if not prompts:
        log.debug("skipped: no user prompts found")
        return

    log.debug("extracted %d prompts, calling haiku...", len(prompts))
    title = generate_title(prompts)
    log.debug("haiku returned: %s", title)

    if title:
        tmux_cmd("rename-window", "-t", window_id, title)
        tmux_cmd("set-option", "-wt", window_id, "@title_source", "sync")
        log.debug("set title: %s", title)

    state[window_id] = {
        "last_check": now,
        "last_size": jsonl_size,
        "session_id": session_id,
    }
    save_state(state)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
