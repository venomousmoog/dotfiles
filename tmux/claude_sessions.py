#!/usr/bin/env python3
"""
Cross-session Claude agent status for tmux.

Replaces constellation.py's per-tab call. Runs every 2 seconds via #(...) in
status-right. Works entirely via side effects (sets tmux options directly),
outputs nothing.

Responsibilities:
- Scan ALL state files across all PID directories
- Set @claude window option on ALL windows across ALL sessions
- Auto-acknowledge waiting agents on the active window of the attached session
- Manage multi-line status bars showing other sessions' Claude agents
- Clean up stale state files (rate-limited to 1/hour)
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

STATE_BASE_DIR: Path = Path.home() / ".claude-tmux-statusline" / "state"

# Cleanup constants
CLEANUP_INTERVAL: int = 3600
MAX_STATE_AGE: int = 86400

# Icons
WORKING_ICON: str = "🟢"
WAITING_ICON: str = "🟡"
ACKNOWLEDGED_ICON: str = "⚪"

# Max extra status lines (to avoid taking over the whole screen)
MAX_EXTRA_LINES: int = 4

# Theme colors
ACTIVE_COLOR: str = "#b4befe"
INACTIVE_COLOR: str = "#6c7086"
BG_COLOR: str = "#1A1D23"

# Icon used in the primary status-left prefix
STATUS_LEFT_ICON: str = "\ue602"


def get_tmux_bin() -> str:
    """Find the tmux binary that started this server via /proc/<pid>/exe.

    Falls back to 'tmux' in PATH if /proc isn't available.
    """
    tmux_env = os.environ.get("TMUX", "")
    if tmux_env:
        parts = tmux_env.split(",")
        if len(parts) >= 2:
            try:
                exe = os.readlink(f"/proc/{parts[1]}/exe")
                if os.path.isfile(exe):
                    return exe
            except OSError:
                pass
    return "tmux"


TMUX_BIN: str = get_tmux_bin()


def cleanup_stale_state_files() -> None:
    """Clean up state files older than 24 hours. Rate-limited to once per hour."""
    cleanup_marker = STATE_BASE_DIR.parent / ".last_cleanup"
    now = time.time()

    try:
        if cleanup_marker.exists():
            if now - cleanup_marker.stat().st_mtime < CLEANUP_INTERVAL:
                return
    except OSError:
        pass

    if not STATE_BASE_DIR.exists():
        return

    for pid_dir in STATE_BASE_DIR.iterdir():
        if not pid_dir.is_dir():
            continue
        try:
            dir_pid = int(pid_dir.name)
        except ValueError:
            continue
        try:
            os.kill(dir_pid, 0)
        except ProcessLookupError:
            shutil.rmtree(pid_dir, ignore_errors=True)
            continue
        except (PermissionError, OSError):
            pass
        for state_file in pid_dir.glob("*.json"):
            try:
                if now - state_file.stat().st_mtime > MAX_STATE_AGE:
                    ack_file = state_file.with_suffix(".ack")
                    state_file.unlink(missing_ok=True)
                    ack_file.unlink(missing_ok=True)
            except OSError:
                pass
        try:
            if not any(pid_dir.iterdir()):
                pid_dir.rmdir()
        except OSError:
            pass

    try:
        cleanup_marker.parent.mkdir(parents=True, exist_ok=True)
        cleanup_marker.touch()
    except OSError:
        pass


def get_tmux_info() -> tuple[Optional[str], Optional[int], Optional[int], str]:
    """Get current tmux session name, server pid, active window index, and hostname."""
    try:
        result = subprocess.run(
            [
                TMUX_BIN,
                "display-message",
                "-p",
                "#{session_name}\t#{pid}\t#{window_index}\t#{?#{@host},#{@host},#{host_short}}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        parts = result.stdout.strip().split("\t")
        session, pid, active_window = parts[0], parts[1], parts[2]
        hostname = parts[3] if len(parts) > 3 else ""
        return session, int(pid), int(active_window), hostname
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        return None, None, None, ""


def get_live_pane_mappings() -> dict[str, tuple[str, int]]:
    """Get pane_id -> (session_name, window_index) for ALL panes across ALL sessions."""
    try:
        result = subprocess.run(
            [
                TMUX_BIN,
                "list-panes",
                "-a",
                "-F",
                "#{pane_id}\t#{session_name}\t#{window_index}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        mapping: dict[str, tuple[str, int]] = {}
        for line in result.stdout.strip().split("\n"):
            if not line or "\t" not in line:
                continue
            parts = line.split("\t", 2)
            if len(parts) == 3:
                pane_id, sess, win_idx = parts
                if sess == "__tun_ctrl":
                    continue
                try:
                    mapping[pane_id] = (sess, int(win_idx))
                except ValueError:
                    pass
        return mapping
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}


def get_all_windows() -> list[dict]:
    """Get all windows across all sessions with metadata.

    Returns list of dicts with keys:
    session_name, window_index, window_name, window_active, session_attached
    """
    try:
        result = subprocess.run(
            [
                TMUX_BIN,
                "list-windows",
                "-a",
                "-F",
                "#{session_name}\t#{window_index}\t#{window_name}\t#{window_active}\t#{session_attached}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        windows = []
        for line in result.stdout.strip().split("\n"):
            if not line or "\t" not in line:
                continue
            parts = line.split("\t", 4)
            if len(parts) == 5:
                if parts[0] == "__tun_ctrl":
                    continue
                try:
                    windows.append(
                        {
                            "session_name": parts[0],
                            "window_index": int(parts[1]),
                            "window_name": parts[2],
                            "window_active": parts[3] == "1",
                            "session_attached": parts[4] == "1",
                        }
                    )
                except ValueError:
                    pass
        return windows
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []


def format_duration(status_since: str) -> str:
    """Format wait duration as 'Xm' or 'Xh'."""
    try:
        since = datetime.fromisoformat(status_since.replace("Z", "+00:00"))
        delta = datetime.now(timezone.utc) - since
        minutes = int(delta.total_seconds() // 60)
        if minutes < 60:
            return f"{minutes}m"
        return f"{minutes // 60}h"
    except ValueError:
        return ""


def get_agent_display(
    status: Optional[str],
    acknowledged: bool,
    status_since: str,
) -> tuple[str, str]:
    """Return (icon, duration) for an agent state."""
    if status == "working":
        return WORKING_ICON, ""
    elif status == "waiting" and not acknowledged:
        return WAITING_ICON, format_duration(status_since)
    else:
        return ACKNOWLEDGED_ICON, ""


def format_icon_string(agents: list[tuple[str, str]]) -> str:
    """Format agent icons for a single window. Returns e.g. '🟢' or '🟡 3m'."""
    if len(agents) == 1:
        icon, duration = agents[0]
        if duration:
            return f"{icon} {duration}"
        return icon
    # Multiple agents - show all icons
    return "".join(a[0] for a in agents)


def set_window_options(
    window_icons: dict[tuple[str, int], str],
) -> None:
    """Set @claude window option on windows across ALL sessions.

    Args:
        window_icons: Dict mapping (session_name, window_index) to icon string.
    """
    if not window_icons:
        return

    temp_path: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False) as f:
            for (sess, win_idx), icon in sorted(window_icons.items(), key=lambda x: (x[0][0], x[0][1])):
                if not isinstance(win_idx, int) or win_idx < 0:
                    continue
                # Sanitize session name for tmux target
                safe_sess = re.sub(r"[^a-zA-Z0-9_./-]", "", sess)
                if not safe_sess:
                    continue
                escaped_icon = (
                    icon.replace("\\", "\\\\")
                    .replace('"', '\\"')
                    .replace("$", "\\$")
                    .replace("`", "\\`")
                    .replace("\n", "")
                )
                f.write(
                    f'set-window-option -t {safe_sess}:{win_idx} @claude "{escaped_icon}"\n'
                )
            temp_path = f.name

        subprocess.run(
            [TMUX_BIN, "source-file", temp_path],
            capture_output=True,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except OSError:
                pass


def set_status_lines(
    current_session: str,
    hostname: str,
    other_session_agents: dict[str, dict[int, list[tuple[str, str]]]],
    all_windows: list[dict],
    prefix_width: int,
) -> None:
    """Configure multi-line status bar for other sessions.

    status-format[0] is left alone (default tmux window list for current session).
    Each additional line shows one other session's windows.
    """
    # Sort other sessions alphabetically, limit to MAX_EXTRA_LINES
    other_sessions = sorted(other_session_agents.keys())[:MAX_EXTRA_LINES]

    total_lines = 1 + len(other_sessions)

    temp_path: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False) as f:
            # Set number of status lines
            # tmux uses "on" for 1-line status; numeric values for 2+
            if total_lines <= 1:
                f.write("set -g status on\n")
            else:
                f.write(f"set -g status {total_lines}\n")

            # Clear any previously-set extra status lines beyond what we need now
            # (tmux keeps old status-format[i] around)
            for i in range(1, MAX_EXTRA_LINES + 1):
                if i >= total_lines:
                    # Clear this line's format to avoid stale content
                    f.write(f'set -g status-format[{i}] ""\n')

            # Build each extra status line
            for line_idx, sess_name in enumerate(other_sessions, start=1):
                agents_by_window = other_session_agents[sess_name]
                # Get all windows for this session, sorted by index
                session_windows = sorted(
                    [w for w in all_windows if w["session_name"] == sess_name],
                    key=lambda w: w["window_index"],
                )

                parts = []
                # Session label: inactive style, padded to fixed width, clickable
                # Pad with Python since #{p...} doesn't work inside status-format[N]
                prefix = f"  {hostname} {sess_name}"
                padded = prefix.ljust(prefix_width)
                parts.append(
                    f"#[align=left]"
                    f"#[bg={BG_COLOR} fg={INACTIVE_COLOR}]"
                    f"#[range=user|{sess_name}]"
                    f"{padded}"
                    f"#[norange]│"
                )

                for w_info in session_windows:
                    win_idx = w_info["window_index"]
                    w_name = w_info["window_name"]
                    agents = agents_by_window.get(win_idx, [])

                    if agents:
                        icon_str = format_icon_string(agents)
                        label = f"{win_idx}:{icon_str} {w_name}"
                    else:
                        label = f"{win_idx}:{w_name}"

                    # Clickable range targeting session:window
                    parts.append(
                        f" #[range=user|{sess_name}:{win_idx} fg={INACTIVE_COLOR}]"
                        f"{label}"
                        f" #[norange]"
                        f"#[fg={INACTIVE_COLOR}]│"
                    )

                line_content = "".join(parts)
                # Escape double quotes for tmux conf
                escaped = line_content.replace('"', '\\"')
                f.write(f'set -g status-format[{line_idx}] "{escaped}"\n')

            temp_path = f.name

        subprocess.run(
            [TMUX_BIN, "source-file", temp_path],
            capture_output=True,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except OSError:
                pass


def main() -> None:
    current_session, current_pid, active_window, hostname = get_tmux_info()
    if current_session is None or current_pid is None:
        return

    cleanup_stale_state_files()

    # Get live pane mappings across ALL sessions
    pane_mappings = get_live_pane_mappings()
    live_pane_ids = set(pane_mappings.keys())

    # Get all windows across all sessions
    all_windows = get_all_windows()

    # Build set of all (session, window_index) pairs
    all_session_windows: set[tuple[str, int]] = set()
    for w in all_windows:
        all_session_windows.add((w["session_name"], w["window_index"]))

    # Collect agent states per (session, window)
    # Key: (session_name, window_index) -> list of (icon, duration)
    agents_by_session_window: defaultdict[
        tuple[str, int], list[tuple[str, str]]
    ] = defaultdict(list)

    # Scan only current tmux server's PID directory
    current_pid_dir = STATE_BASE_DIR / str(current_pid)
    if current_pid_dir.is_dir():
        for state_file in current_pid_dir.glob("*.json"):
            session_id = state_file.stem
            ack_file = current_pid_dir / f"{session_id}.ack"

            try:
                state = json.loads(state_file.read_text())
            except (json.JSONDecodeError, OSError):
                continue

            pane_id = state.get("pane_id")
            status = state.get("status")
            status_since = state.get("status_since", "")

            # Validate pane_id format
            if not pane_id or not re.match(r"^%\d+$", pane_id):
                continue

            # Clean up if pane no longer exists
            if pane_id not in live_pane_ids:
                try:
                    state_file.unlink(missing_ok=True)
                    ack_file.unlink(missing_ok=True)
                except OSError:
                    pass
                continue

            # Look up which session/window this pane belongs to NOW
            sess_name, win_idx = pane_mappings[pane_id]

            # Auto-acknowledge: if this agent is waiting and is on the
            # active window of the currently-viewed (attached) session
            if (
                sess_name == current_session
                and win_idx == active_window
                and status == "waiting"
            ):
                try:
                    fd = os.open(
                        str(ack_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY
                    )
                    os.close(fd)
                    acknowledged = True
                except FileExistsError:
                    acknowledged = True
                except OSError:
                    acknowledged = ack_file.exists()
            else:
                acknowledged = ack_file.exists()

            icon, duration = get_agent_display(status, acknowledged, status_since)
            agents_by_session_window[(sess_name, win_idx)].append((icon, duration))

    # --- Set @claude window option on ALL windows across ALL sessions ---
    window_icons: dict[tuple[str, int], str] = {}
    for sess_win in all_session_windows:
        if sess_win in agents_by_session_window:
            agents = agents_by_session_window[sess_win]
            window_icons[sess_win] = f"{format_icon_string(agents)} "
        else:
            window_icons[sess_win] = ""

    set_window_options(window_icons)

    # --- Manage multi-line status for other sessions ---
    # Group agents by session, excluding the current session.
    # Include all other sessions, even those without any Claude agents.
    other_session_agents: dict[str, dict[int, list[tuple[str, str]]]] = {}
    for (sess, win_idx), agents in agents_by_session_window.items():
        if sess == current_session:
            continue
        if sess not in other_session_agents:
            other_session_agents[sess] = {}
        other_session_agents[sess][win_idx] = agents
    # Ensure all other sessions appear, even without agents
    for w in all_windows:
        sess = w["session_name"]
        if sess != current_session and sess not in other_session_agents:
            other_session_agents[sess] = {}

    # --- Compute dynamic prefix width from all session names ---
    # Prefix format: "  <host> <session>" (2 leading spaces + host + space + session)
    # or for primary: "<icon> <host> <session>" (icon is 1 display char + 1 space)
    # Both cases use 2 leading characters, so width is the same.
    all_session_names = {current_session} | set(other_session_agents.keys())
    prefix_width = max(
        len(f"  {hostname} {sess_name}")
        for sess_name in all_session_names
    )
    # Add 1 char trailing padding so │ isn't jammed against the name
    prefix_width += 1

    # --- Set status-left (primary line prefix) dynamically ---
    primary_prefix = f"{STATUS_LEFT_ICON} {hostname} {current_session}"
    padded_primary = primary_prefix.ljust(prefix_width)
    status_left_length = prefix_width + 3  # +3 for │ + space + margin
    temp_path_sl: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False) as f:
            escaped_prefix = (
                padded_primary.replace("\\", "\\\\")
                .replace('"', '\\"')
                .replace("$", "\\$")
                .replace("`", "\\`")
            )
            f.write(
                f'set -g status-left "#[fg={ACTIVE_COLOR},bold]{escaped_prefix}'
                f'#[fg={INACTIVE_COLOR},nobold]│ "\n'
            )
            f.write(f"set -g status-left-length {status_left_length}\n")
            temp_path_sl = f.name
        subprocess.run(
            [TMUX_BIN, "source-file", temp_path_sl],
            capture_output=True,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        if temp_path_sl:
            try:
                os.unlink(temp_path_sl)
            except OSError:
                pass

    set_status_lines(current_session, hostname, other_session_agents, all_windows, prefix_width)


if __name__ == "__main__":
    main()
