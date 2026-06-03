#!/usr/bin/env python3
"""
Claude Code session watchdog.

Monitors a Claude Code session's JSONL conversation log and hook state files,
detects when Claude is waiting for input, classifies the wait type, and
autonomously responds via tmux send-keys.
"""

import argparse
import ctypes
import ctypes.util
import json
import logging
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# InotifyTailer — tail a file using Linux inotify (fallback: mtime polling)
# ---------------------------------------------------------------------------

# inotify constants
IN_MODIFY = 0x00000002

def _load_libc():
    """Try to load libc for inotify syscalls."""
    try:
        name = ctypes.util.find_library("c")
        if name:
            libc = ctypes.CDLL(name, use_errno=True)
            libc.inotify_init.restype = ctypes.c_int
            libc.inotify_add_watch.restype = ctypes.c_int
            libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
            libc.read.restype = ctypes.c_ssize_t
            libc.read.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_size_t]
            return libc
    except Exception:
        pass
    return None

_libc = _load_libc()


class InotifyTailer:
    """Tails appended lines from a file using inotify or mtime polling."""

    def __init__(self, path: str, poll_interval: float = 0.5):
        self.path = path
        self.poll_interval = poll_interval
        self._offset = 0
        self._inotify_fd = -1
        self._watch_fd = -1
        self._use_inotify = False

        # Seek to end of existing content
        if os.path.exists(path):
            self._offset = os.path.getsize(path)

        # Try to set up inotify
        if _libc is not None:
            fd = _libc.inotify_init()
            if fd >= 0:
                wd = _libc.inotify_add_watch(fd, path.encode(), IN_MODIFY)
                if wd >= 0:
                    self._inotify_fd = fd
                    self._watch_fd = wd
                    self._use_inotify = True
                    # Set non-blocking
                    import fcntl
                    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
                    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

        self._last_mtime = os.path.getmtime(path) if os.path.exists(path) else 0

    def read_new_lines(self) -> list[str]:
        """Return any new complete lines appended since last read."""
        if not os.path.exists(self.path):
            return []

        changed = False
        if self._use_inotify:
            buf = ctypes.create_string_buffer(4096)
            n = _libc.read(self._inotify_fd, buf, 4096)
            changed = n > 0
        else:
            mtime = os.path.getmtime(self.path)
            if mtime > self._last_mtime:
                self._last_mtime = mtime
                changed = True

        if not changed:
            return []

        try:
            with open(self.path, "r") as f:
                f.seek(self._offset)
                data = f.read()
                self._offset = f.tell()
        except (OSError, IOError):
            return []

        if not data:
            return []

        lines = data.split("\n")
        # If data doesn't end with newline, last element is incomplete — put it back
        if not data.endswith("\n"):
            self._offset -= len(lines[-1].encode())
            lines = lines[:-1]
        else:
            lines = lines[:-1]  # Remove trailing empty string from split

        return [l for l in lines if l.strip()]

    def close(self):
        if self._use_inotify and self._inotify_fd >= 0:
            os.close(self._inotify_fd)
            self._inotify_fd = -1


# ---------------------------------------------------------------------------
# StateWatcher — polls hook state JSON for changes
# ---------------------------------------------------------------------------

class StateWatcher:
    """Watches a hook state JSON file for changes via mtime polling."""

    def __init__(self, state_dir: str, session_id: str):
        self.state_file = os.path.join(state_dir, f"{session_id}.json")
        self._last_mtime = 0.0
        self._last_state = {}

    def check(self) -> dict | None:
        """Return parsed state dict if the file changed, else None."""
        if not os.path.exists(self.state_file):
            return None
        try:
            mtime = os.path.getmtime(self.state_file)
        except OSError:
            return None
        if mtime <= self._last_mtime:
            return None
        self._last_mtime = mtime
        try:
            with open(self.state_file, "r") as f:
                state = json.load(f)
            self._last_state = state
            return state
        except (json.JSONDecodeError, OSError):
            return None

    @property
    def last_state(self) -> dict:
        return self._last_state

    @property
    def exists(self) -> bool:
        return os.path.exists(self.state_file)


# ---------------------------------------------------------------------------
# MessageWindow — rolling buffer of recent JSONL messages
# ---------------------------------------------------------------------------

class MessageWindow:
    """Rolling buffer of parsed JSONL conversation entries."""

    KEEP_TYPES = {"user", "assistant", "system"}

    def __init__(self, max_size: int = 30):
        self.max_size = max_size
        self._messages: list[dict] = []

    def add(self, raw_line: str):
        try:
            entry = json.loads(raw_line)
        except json.JSONDecodeError:
            return
        msg_type = entry.get("type")
        if msg_type not in self.KEEP_TYPES:
            return
        self._messages.append(entry)
        if len(self._messages) > self.max_size:
            self._messages = self._messages[-self.max_size:]

    def recent_text(self, n: int = 10) -> str:
        """Format last N messages as text for the classifier."""
        msgs = self._messages[-n:]
        parts = []
        for m in msgs:
            role = m.get("type", "unknown")
            text = _extract_text(m)
            if text:
                parts.append(f"[{role}] {text[:500]}")
        return "\n".join(parts)

    def last_assistant_text(self) -> str:
        """Extract text from the most recent assistant message."""
        for m in reversed(self._messages):
            if m.get("type") == "assistant":
                return _extract_text(m)
        return ""


def _extract_text(entry: dict) -> str:
    """Extract readable text from a JSONL message entry."""
    # message.content can be a string or list of content blocks
    msg = entry.get("message", {})
    content = msg.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return " ".join(parts)
    return str(content) if content else ""


# ---------------------------------------------------------------------------
# Classifier — heuristic and LLM-based wait classification
# ---------------------------------------------------------------------------

QUESTION_KEYWORDS = re.compile(
    r"\b(should|would|prefer|architecture|design|approach|strategy|which|decision|choose)\b",
    re.IGNORECASE,
)

HUMAN_TASK_KEYWORDS = re.compile(
    r"\b(permission|approve|run manually|another terminal|outside|visit|open|browser|"
    r"manually run|you.ll need to|please run|could you run)\b",
    re.IGNORECASE,
)

CLASSIFIER_SCHEMA = json.dumps({
    "type": "object",
    "properties": {
        "type": {"type": "string", "enum": ["continue", "human_task", "question", "complex"]},
        "suggested_response": {"type": "string"},
    },
    "required": ["type", "suggested_response"],
})


def classify_heuristic(assistant_text: str, hook_state: dict) -> dict:
    """Classify the wait type using pattern matching."""
    notification_type = hook_state.get("current_tool")

    # Permission/elicitation prompts — always flag
    if notification_type in ("permission_prompt", "elicitation_dialog"):
        return {"type": "complex", "suggested_response": ""}

    text = assistant_text.strip()
    if not text:
        return {"type": "continue", "suggested_response": "continue"}

    # Check for question patterns
    if text.rstrip().endswith("?") and QUESTION_KEYWORDS.search(text):
        return {"type": "question", "suggested_response": ""}

    # Check for human task patterns
    if HUMAN_TASK_KEYWORDS.search(text):
        return {"type": "human_task", "suggested_response": ""}

    # Default: likely just finished a step
    return {"type": "continue", "suggested_response": "continue"}


def classify_llm(recent_text: str, profile: dict) -> dict:
    """Classify using claude CLI with JSON schema output."""
    context = profile.get("classifier_context", "")
    prompt = (
        "You are classifying why a Claude Code session stopped and is waiting for user input.\n\n"
        f"Profile context: {context}\n\n"
        "Recent conversation:\n"
        f"{recent_text}\n\n"
        "Classify the wait into one of:\n"
        "- continue: Claude finished a step and can proceed with 'continue'\n"
        "- human_task: Claude needs the user to do something external\n"
        "- question: Claude is asking a question that needs a thoughtful answer\n"
        "- complex: Situation is ambiguous or risky, do nothing\n\n"
        "Respond with the classification and a suggested response (empty string if complex)."
    )
    try:
        result = subprocess.run(
            [
                "claude", "-p", prompt,
                "--no-session-persistence",
                "--output-format", "json",
                "--max-turns", "1",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return {"type": "complex", "suggested_response": ""}
        output = json.loads(result.stdout)
        # claude -p --output-format json returns {"result": "..."}
        inner = output.get("result", "")
        # Try to parse the inner text as JSON
        parsed = json.loads(inner)
        if parsed.get("type") in ("continue", "human_task", "question", "complex"):
            return parsed
    except Exception:
        pass
    return {"type": "complex", "suggested_response": ""}


# ---------------------------------------------------------------------------
# TitleManager — sets tmux window title from session intent
# ---------------------------------------------------------------------------

class TitleManager:
    def __init__(self, pane_id: str):
        self.pane_id = pane_id
        self._title_set = False
        self._last_user_text = ""

    def update(self, messages: MessageWindow):
        """Generate title from first user message; update only on major topic shift."""
        # Find most recent user message
        user_text = ""
        for m in reversed(messages._messages):
            if m.get("type") == "user":
                user_text = _extract_text(m)
                break

        if not user_text or user_text == self._last_user_text:
            return

        self._last_user_text = user_text

        if self._title_set:
            # Only update if substantially different topic
            # Simple heuristic: less than 30% word overlap
            old_words = set(self._last_user_text.lower().split())
            new_words = set(user_text.lower().split())
            if old_words and new_words:
                overlap = len(old_words & new_words) / max(len(old_words), len(new_words))
                if overlap > 0.3:
                    return

        # Generate a short title from the user text
        title = user_text[:60].replace("'", "").replace('"', "").replace("\n", " ").strip()
        # Truncate to ~10 words
        words = title.split()[:10]
        title = " ".join(words)
        if title:
            try:
                subprocess.run(
                    ["tmux", "rename-window", "-t", self.pane_id, title],
                    capture_output=True, timeout=5,
                )
                self._title_set = True
            except Exception:
                pass


# ---------------------------------------------------------------------------
# WorkaroundTable — parses human-task-workarounds.md
# ---------------------------------------------------------------------------

class WorkaroundTable:
    """Lookup table of (regex, action_text) from workaround reference files."""

    def __init__(self, *paths: str):
        self.entries: list[tuple[re.Pattern, str]] = []
        for path in paths:
            self._load(path)

    def _load(self, ref_path: str):
        if not os.path.exists(ref_path):
            return
        try:
            with open(ref_path, "r") as f:
                content = f.read()
        except OSError:
            return

        # Parse **Pattern:** and **Workaround:** pairs
        pattern = None
        for line in content.split("\n"):
            line = line.strip()
            if line.startswith("**Pattern:**"):
                pat_text = line.split("**Pattern:**", 1)[1].strip().strip("`")
                try:
                    pattern = re.compile(pat_text, re.IGNORECASE)
                except re.error:
                    pattern = None
            elif line.startswith("**Workaround:**") and pattern is not None:
                action = line.split("**Workaround:**", 1)[1].strip()
                if action == "NEVER_AUTO":
                    self.entries.append((pattern, ""))
                else:
                    self.entries.append((pattern, action))
                pattern = None

    def lookup(self, text: str) -> str | None:
        """Return action text if a workaround matches, None otherwise.
        Empty string means 'flag for user'."""
        for regex, action in self.entries:
            if regex.search(text):
                return action
        return None


# ---------------------------------------------------------------------------
# ActionSender — sends responses via tmux send-keys
# ---------------------------------------------------------------------------

class ActionSender:
    """Sends text to a tmux pane with safety measures."""

    MAX_LENGTH = 500

    def __init__(self, pane_id: str, max_auto_continues: int):
        self.pane_id = pane_id
        self.max_auto_continues = max_auto_continues
        self.auto_continue_count = 0

    def can_send(self) -> bool:
        return self.auto_continue_count < self.max_auto_continues

    def send(self, text: str, log: logging.Logger) -> bool:
        """Send text to the tmux pane. Returns True if sent."""
        if not self.can_send():
            log.warning("Auto-continue cap reached (%d), refusing to send", self.max_auto_continues)
            return False

        # Sanitize
        text = self._sanitize(text)
        if not text:
            log.warning("Empty text after sanitization, not sending")
            return False

        self.auto_continue_count += 1
        log.info("Sending [%d/%d]: %s", self.auto_continue_count, self.max_auto_continues, text)

        try:
            subprocess.run(
                ["tmux", "send-keys", "-t", self.pane_id, text, "Enter"],
                capture_output=True, timeout=5,
            )
            return True
        except Exception as e:
            log.error("Failed to send keys: %s", e)
            return False

    def _sanitize(self, text: str) -> str:
        """Strip shell metacharacters and limit length."""
        # Remove dangerous shell chars
        text = re.sub(r'[;&|`$(){}\\]', '', text)
        # Collapse whitespace
        text = " ".join(text.split())
        # Limit length
        if len(text) > self.MAX_LENGTH:
            text = text[:self.MAX_LENGTH]
        return text.strip()


# ---------------------------------------------------------------------------
# Main watchdog loop
# ---------------------------------------------------------------------------

def load_profile(path: str) -> dict:
    with open(path, "r") as f:
        return json.load(f)


def read_plan_file(profile: dict) -> str:
    """Read the plan file if configured, return its content."""
    plan_path = profile.get("plan_file")
    if not plan_path:
        # Auto-detect: find most recent .md in ~/.claude/plans/
        plans_dir = os.path.expanduser("~/.claude/plans")
        if os.path.isdir(plans_dir):
            md_files = sorted(
                Path(plans_dir).glob("*.md"),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            )
            if md_files:
                plan_path = str(md_files[0])
    if not plan_path or not os.path.exists(plan_path):
        return ""
    try:
        with open(plan_path, "r") as f:
            return f.read()
    except OSError:
        return ""


def handle_waiting(
    classification: dict,
    profile: dict,
    workarounds: WorkaroundTable,
    sender: ActionSender,
    messages: MessageWindow,
    log: logging.Logger,
) -> None:
    """Act on a classified wait state."""
    wait_type = classification["type"]
    suggested = classification.get("suggested_response", "")

    if wait_type == "continue":
        if profile.get("auto_continue"):
            sender.send(suggested or "continue", log)
        else:
            log.info("auto_continue disabled, skipping")

    elif wait_type == "human_task":
        if profile.get("handle_human_tasks"):
            assistant_text = messages.last_assistant_text()
            action = workarounds.lookup(assistant_text)
            if action is None:
                log.info("No workaround found for human task, skipping")
            elif action == "":
                log.info("Workaround says flag for user, skipping")
            else:
                sender.send(action, log)
        else:
            log.info("handle_human_tasks disabled, skipping")

    elif wait_type == "question":
        if profile.get("answer_questions_from_plan"):
            plan_content = read_plan_file(profile)
            if plan_content and suggested:
                sender.send(suggested, log)
            elif plan_content:
                # Use LLM to answer from plan if available
                if profile.get("use_llm"):
                    answer = _answer_from_plan_llm(messages.last_assistant_text(), plan_content)
                    if answer:
                        sender.send(answer, log)
                    else:
                        log.info("LLM couldn't answer question from plan")
                else:
                    log.info("Question detected but no LLM and no suggested response")
            else:
                log.info("Question detected but no plan file available")
        else:
            log.info("answer_questions_from_plan disabled, skipping")

    elif wait_type == "complex":
        log.info("Complex situation, doing nothing")


def _answer_from_plan_llm(question: str, plan_content: str) -> str:
    """Use claude CLI to answer a question from plan content."""
    prompt = (
        "A Claude Code session is asking this question:\n\n"
        f"{question}\n\n"
        "Here is the plan document for context:\n\n"
        f"{plan_content[:3000]}\n\n"
        "Answer the question concisely based on the plan. "
        "If the plan doesn't contain the answer, respond with just 'CANNOT_ANSWER'."
    )
    try:
        result = subprocess.run(
            [
                "claude", "-p", prompt,
                "--no-session-persistence",
                "--max-turns", "1",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            answer = result.stdout.strip()
            if "CANNOT_ANSWER" not in answer and len(answer) > 5:
                return answer
    except Exception:
        pass
    return ""


class Watchdog:
    def __init__(self, args):
        self.session_id = args.session_id
        self.project_dir = args.project_dir
        self.pane_id = args.pane_id
        self.tmux_pid = args.tmux_pid
        self.dry_run = args.dry_run
        self.replay_path = args.replay

        self.profile = load_profile(args.profile)
        self.profile_path = args.profile
        self.pid_file = os.path.expanduser(f"~/.claude-watchdog/{self.session_id}.pid")
        self.jsonl_path = os.path.join(self.project_dir, f"{self.session_id}.jsonl")

        self.log = logging.getLogger("watchdog")
        self.log.setLevel(logging.DEBUG)
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        self.log.addHandler(handler)

        self.tailer = InotifyTailer(self.replay_path or self.jsonl_path)
        self.state_watcher = StateWatcher(
            os.path.expanduser(f"~/.claude-tmux-statusline/state/{self.tmux_pid}"),
            self.session_id,
        )
        self.messages = MessageWindow(max_size=30)
        self.title_mgr = TitleManager(self.pane_id)

        # Load workarounds: per-profile first (higher priority), then global
        profile_name = self.profile.get("name", "")
        profiles_dir = os.path.expanduser("~/.claude/skills/watchdog/profiles")
        profile_workarounds = os.path.join(profiles_dir, f"{profile_name}.workarounds.md")
        global_workarounds = os.path.expanduser(
            "~/.claude/skills/watchdog/references/human-task-workarounds.md"
        )
        self.workarounds = WorkaroundTable(profile_workarounds, global_workarounds)

        # Load per-profile instructions and merge into classifier_context
        profile_instructions = os.path.join(profiles_dir, f"{profile_name}.instructions.md")
        self._load_profile_instructions(profile_instructions)
        self.sender = ActionSender(
            self.pane_id,
            self.profile.get("max_auto_continues", 50),
        )

        # Debounce state
        self.debounce_seconds = self.profile.get("debounce_seconds", 3.0)
        self._waiting_since: float | None = None

        # Infinite loop protection
        self._consecutive_same = 0
        self._last_classification = ""

        self._running = True

    def _load_profile_instructions(self, instructions_path: str):
        """Read per-profile instructions and prepend to classifier_context."""
        if not os.path.exists(instructions_path):
            return
        try:
            with open(instructions_path, "r") as f:
                instructions = f.read().strip()
        except OSError:
            return
        if instructions:
            existing = self.profile.get("classifier_context", "")
            self.profile["classifier_context"] = (
                f"{instructions}\n\n{existing}" if existing else instructions
            )

    def run(self):
        self.log.info(
            "Watchdog started: session=%s profile=%s dry_run=%s",
            self.session_id, self.profile.get("name", "?"), self.dry_run,
        )

        # Install signal handlers
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)

        while self._running:
            # 1. Process new JSONL lines
            for line in self.tailer.read_new_lines():
                self.messages.add(line)

            self.title_mgr.update(self.messages)

            # 2. Check hook state
            new_state = self.state_watcher.check()
            if new_state:
                status = new_state.get("status")
                if status == "waiting":
                    if self._waiting_since is None:
                        self._waiting_since = time.monotonic()
                        self.log.debug("Waiting state detected, starting debounce")
                elif status == "working":
                    self._waiting_since = None
                    self.log.debug("Working state detected, reset debounce")

            # Check debounce
            if self._waiting_since is not None:
                elapsed = time.monotonic() - self._waiting_since
                if elapsed >= self.debounce_seconds:
                    # Re-check state is still waiting
                    current = self.state_watcher.last_state
                    if current.get("status") == "waiting":
                        self._act(current)
                    self._waiting_since = None

            # 3. Self-termination checks
            if self._should_terminate():
                self.log.info("Self-termination triggered")
                break

            # Replay mode: exit when tailer has no more data and we've processed everything
            if self.replay_path and not os.path.exists(self.replay_path):
                break

            time.sleep(0.5)

        self._cleanup()

    def _act(self, hook_state: dict):
        """Classify and act on a waiting state."""
        assistant_text = self.messages.last_assistant_text()
        recent = self.messages.recent_text(10)

        # Classify
        if self.profile.get("use_llm"):
            classification = classify_llm(recent, self.profile)
        else:
            classification = classify_heuristic(assistant_text, hook_state)

        self.log.info("Classification: %s", classification)

        # Infinite loop protection
        cls_key = classification["type"]
        if cls_key == self._last_classification:
            self._consecutive_same += 1
        else:
            self._consecutive_same = 1
            self._last_classification = cls_key

        if self._consecutive_same > 3:
            self.log.warning(
                "3+ identical consecutive classifications (%s), backing off", cls_key
            )
            return

        if self.dry_run:
            self.log.info("DRY RUN — would act on: %s", classification)
            return

        handle_waiting(
            classification, self.profile, self.workarounds,
            self.sender, self.messages, self.log,
        )

    def _should_terminate(self) -> bool:
        # PID file removed (explicit stop)
        if not os.path.exists(self.pid_file):
            self.log.info("PID file removed")
            return True
        # State file deleted (session ended)
        if not self.state_watcher.exists:
            # Check if JSONL is also stale
            if os.path.exists(self.jsonl_path):
                try:
                    age = time.time() - os.path.getmtime(self.jsonl_path)
                    if age > 300:  # 5 minutes
                        self.log.info("JSONL stale (%.0fs) and state file gone", age)
                        return True
                except OSError:
                    return True
            else:
                self.log.info("State file and JSONL both gone")
                return True
        return False

    def _handle_signal(self, signum, frame):
        self.log.info("Received signal %d, shutting down", signum)
        self._running = False

    def _cleanup(self):
        self.tailer.close()
        # Remove PID file
        try:
            os.unlink(self.pid_file)
        except OSError:
            pass
        self.log.info("Watchdog stopped")


def main():
    parser = argparse.ArgumentParser(description="Claude Code session watchdog")
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--pane-id", required=True)
    parser.add_argument("--tmux-pid", required=True)
    parser.add_argument("--profile", required=True, help="Path to profile JSON")
    parser.add_argument("--dry-run", action="store_true", help="Log actions without sending keys")
    parser.add_argument("--replay", metavar="JSONL", help="Replay a JSONL file instead of live session")
    args = parser.parse_args()

    wd = Watchdog(args)
    wd.run()


if __name__ == "__main__":
    main()
