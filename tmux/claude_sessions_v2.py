#!/usr/bin/env python3
"""
Cross-session Claude agent status for tmux — tunnel-aware version.

Extends claude_sessions.py with support for tunnel sessions:
- Queries #{session_tunnel} and #{pane_tunnel_remote_id} to discover tunnel panes
- Uses tunnel-exec to read remote state files via the control mode channel
- Maps remote pane IDs back to local windows for @claude icon display

Drop-in replacement: activate via update_theme_v2.sh, revert via update_theme.sh.
"""

import json
import os
import re
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


def get_live_pane_mappings() -> tuple[
    dict[str, tuple[str, int]],
    dict[str, tuple[str, int, str, str]],
]:
    """Get pane mappings for ALL panes across ALL sessions.

    Returns:
        (local_mappings, tunnel_mappings)
        local_mappings: pane_id -> (session_name, window_index)
        tunnel_mappings: pane_id -> (session_name, window_index, tunnel_name, remote_pane_id)
    """
    try:
        result = subprocess.run(
            [
                TMUX_BIN,
                "list-panes",
                "-a",
                "-F",
                "#{pane_id}\t#{session_name}\t#{window_index}\t#{session_tunnel}\t#{pane_tunnel_remote_id}",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        local_mapping: dict[str, tuple[str, int]] = {}
        tunnel_mapping: dict[str, tuple[str, int, str, str]] = {}

        for line in result.stdout.strip().split("\n"):
            if not line or "\t" not in line:
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue

            pane_id = parts[0]
            sess = parts[1]
            win_idx_str = parts[2]
            tunnel_name = parts[3] if len(parts) > 3 else ""
            remote_id = parts[4] if len(parts) > 4 else ""

            if sess == "__tun_ctrl":
                continue

            try:
                win_idx = int(win_idx_str)
            except ValueError:
                continue

            local_mapping[pane_id] = (sess, win_idx)

            if tunnel_name and remote_id:
                tunnel_mapping[pane_id] = (sess, win_idx, tunnel_name, remote_id)

        return local_mapping, tunnel_mapping
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}, {}


def get_all_windows() -> list[dict]:
    """Get all windows across all sessions with metadata."""
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


def get_remote_state_files(tunnel_session: str) -> list[dict]:
    """Read remote Claude state files via tunnel-exec.

    Args:
        tunnel_session: A tunnel session name (e.g., "devbox/work") to exec through.

    Returns:
        List of parsed JSON state dicts from the remote machine.
    """
    try:
        result = subprocess.run(
            [
                TMUX_BIN,
                "tunnel-exec",
                "-t", tunnel_session,
                "run-shell",
                "cat ~/.claude-tmux-statusline/state/*/*.json 2>/dev/null",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return []

        states = []
        # Remote may have multiple JSON objects concatenated
        # Try to parse each line or each JSON object
        for line in result.stdout.strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                state = json.loads(line)
                if isinstance(state, dict) and "pane_id" in state:
                    states.append(state)
            except json.JSONDecodeError:
                continue
        return states
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            FileNotFoundError):
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
    """Set @claude window option on windows across ALL sessions."""
    if not window_icons:
        return

    temp_path: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False) as f:
            for (sess, win_idx), icon in sorted(window_icons.items(), key=lambda x: (x[0][0], x[0][1])):
                if not isinstance(win_idx, int) or win_idx < 0:
                    continue
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
    """Configure multi-line status bar for other sessions with active agents."""
    window_lookup: dict[tuple[str, int], dict] = {}
    for w in all_windows:
        window_lookup[(w["session_name"], w["window_index"])] = w

    sessions_with_agents = sorted(other_session_agents.keys())[:MAX_EXTRA_LINES]

    total_lines = 1 + len(sessions_with_agents)

    temp_path: Optional[str] = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False) as f:
            if total_lines <= 1:
                f.write("set -g status on\n")
            else:
                f.write(f"set -g status {total_lines}\n")

            for i in range(1, MAX_EXTRA_LINES + 1):
                if i >= total_lines:
                    f.write(f'set -g status-format[{i}] ""\n')

            for line_idx, sess_name in enumerate(sessions_with_agents, start=1):
                agents_by_window = other_session_agents[sess_name]
                sorted_windows = sorted(agents_by_window.keys())

                parts = []
                prefix = f"  {hostname} {sess_name}"
                padded = prefix.ljust(prefix_width)
                parts.append(
                    f"#[align=left]"
                    f"#[bg={BG_COLOR} fg={INACTIVE_COLOR}]"
                    f"#[range=user|{sess_name}]"
                    f"{padded}"
                    f"#[norange]│"
                )

                for win_idx in sorted_windows:
                    agents = agents_by_window[win_idx]
                    icon_str = format_icon_string(agents)
                    w_info = window_lookup.get((sess_name, win_idx))
                    w_name = w_info["window_name"] if w_info else str(win_idx)

                    parts.append(
                        f" #[range=user|{sess_name}:{win_idx} fg={INACTIVE_COLOR}]"
                        f"{win_idx}:{icon_str} {w_name}"
                        f" #[norange]"
                        f"#[fg={INACTIVE_COLOR}]│"
                    )

                line_content = "".join(parts)
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

    # Get live pane mappings across ALL sessions, including tunnel metadata
    pane_mappings, tunnel_pane_mappings = get_live_pane_mappings()
    live_pane_ids = set(pane_mappings.keys())

    # Get all windows across all sessions
    all_windows = get_all_windows()

    # Build set of all (session, window_index) pairs
    all_session_windows: set[tuple[str, int]] = set()
    for w in all_windows:
        all_session_windows.add((w["session_name"], w["window_index"]))

    # Collect agent states per (session, window)
    agents_by_session_window: defaultdict[
        tuple[str, int], list[tuple[str, str]]
    ] = defaultdict(list)

    # --- Step 1: Scan LOCAL state files (same as original) ---
    if STATE_BASE_DIR.exists():
        for pid_dir in STATE_BASE_DIR.iterdir():
            if not pid_dir.is_dir():
                continue
            for state_file in pid_dir.glob("*.json"):
                session_id = state_file.stem
                ack_file = pid_dir / f"{session_id}.ack"

                try:
                    state = json.loads(state_file.read_text())
                except (json.JSONDecodeError, OSError):
                    continue

                pane_id = state.get("pane_id")
                status = state.get("status")
                status_since = state.get("status_since", "")

                if not pane_id or not re.match(r"^%\d+$", pane_id):
                    continue

                if pane_id not in live_pane_ids:
                    continue

                sess_name, win_idx = pane_mappings[pane_id]

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

    # --- Step 2: Scan REMOTE state files via tunnel-exec ---
    # Build reverse map: (tunnel_name, remote_pane_id) -> (local_session, local_window)
    tunnel_remote_map: dict[tuple[str, str], tuple[str, int]] = {}
    # Track which tunnels we've seen and pick one session per tunnel for exec
    tunnel_exec_sessions: dict[str, str] = {}  # tunnel_name -> a session name

    for pane_id, (sess, win_idx, tun_name, remote_id) in tunnel_pane_mappings.items():
        tunnel_remote_map[(tun_name, remote_id)] = (sess, win_idx)
        if tun_name not in tunnel_exec_sessions:
            tunnel_exec_sessions[tun_name] = sess

    # For each unique tunnel, read remote state files
    for tunnel_name, exec_session in tunnel_exec_sessions.items():
        remote_states = get_remote_state_files(exec_session)
        for state in remote_states:
            remote_pane_id = state.get("pane_id", "")
            status = state.get("status")
            status_since = state.get("status_since", "")

            if not remote_pane_id:
                continue

            # Map remote pane ID to local session/window
            key = (tunnel_name, remote_pane_id)
            if key not in tunnel_remote_map:
                continue

            local_sess, local_win = tunnel_remote_map[key]

            # For tunnel sessions, we don't do auto-acknowledge (remote state)
            icon, duration = get_agent_display(status, False, status_since)
            agents_by_session_window[(local_sess, local_win)].append((icon, duration))

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
    other_session_agents: dict[str, dict[int, list[tuple[str, str]]]] = {}
    for (sess, win_idx), agents in agents_by_session_window.items():
        if sess == current_session:
            continue
        if sess not in other_session_agents:
            other_session_agents[sess] = {}
        other_session_agents[sess][win_idx] = agents

    # --- Compute dynamic prefix width from all session names ---
    all_session_names = {current_session} | set(other_session_agents.keys())
    prefix_width = max(
        len(f"  {hostname} {sess_name}")
        for sess_name in all_session_names
    )
    prefix_width += 1

    # --- Set status-left (primary line prefix) dynamically ---
    primary_prefix = f"{STATUS_LEFT_ICON} {hostname} {current_session}"
    padded_primary = primary_prefix.ljust(prefix_width)
    status_left_length = prefix_width + 3
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
