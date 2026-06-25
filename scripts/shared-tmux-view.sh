#!/bin/bash
# shared-tmux-view.sh -- watch the bash panes that agents created on the shared
# tmux server (see shared-tmux.sh, and the privileged-tmux skill / ptmux.sh).
#
# Agents each run in their own `agent-*` session on the shared server. This script
# gathers those into a single view so you can watch them all.
#
# Two modes:
#   (default)    switcher  -- attach READ-ONLY to a transient 'view' session whose
#                            windows are live links to each agent's window. One
#                            agent on screen at a time, zero lag. Flip with
#                            C-b n / C-b p, or C-b w for a list (mouse works too).
#   --dashboard  dashboard -- one window, tiled, every agent pane mirrored at once
#                            (read-only screen capture refreshed ~0.5s). Best when
#                            you want everything visible simultaneously.
#
# Both modes are non-destructive: the switcher attaches read-only and pins window
# size to the largest client so it won't resize an agent's pane; the dashboard
# only mirrors captured text and never sends input to agents.
#
# Options:
#   --dashboard          tiled all-at-once mirror instead of the switcher
#   --interval <secs>    dashboard refresh interval (default 0.5)
#   --filter <glob>      which session names count as agents (default 'agent-*')
#   --all                include every session (except this viewer's own)
#   --rw                 switcher: attach read-WRITE (lets you type into agents)
#   --socket <path>      shared server socket (default /tmp/tmux-shared/shared)
#   -h | --help

set -uo pipefail

SOCK="/tmp/tmux-shared/shared"
MODE="switcher"
INTERVAL="0.5"
FILTER="agent-*"
ALL=0
RW=0
VIEW="view"
DASH="viewdash"

while [ $# -gt 0 ]; do
  case "$1" in
    --dashboard) MODE="dashboard" ;;
    --interval)  INTERVAL="${2:?}"; shift ;;
    --filter)    FILTER="${2:?}"; shift ;;
    --all)       ALL=1 ;;
    --rw)        RW=1 ;;
    --socket)    SOCK="${2:?}"; shift ;;
    -h|--help)   sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

tmux_s() { tmux -S "$SOCK" "$@"; }

if ! tmux_s list-sessions >/dev/null 2>&1; then
  echo "No shared tmux server at $SOCK." >&2
  echo "Start it with: ~/src/dotfiles/scripts/shared-tmux.sh" >&2
  exit 1
fi

# Print the session names that count as agent sessions (one per line).
agent_sessions() {
  local s
  while read -r s; do
    [ "$s" = "$VIEW" ] && continue
    [ "$s" = "$DASH" ] && continue
    if [ "$ALL" = 1 ]; then
      [ "$s" = "auto" ] && continue
      printf '%s\n' "$s"
    else
      # shellcheck disable=SC2254  # $FILTER is an intentional glob
      case "$s" in $FILTER) printf '%s\n' "$s" ;; esac
    fi
  done < <(tmux_s list-sessions -F '#{session_name}' 2>/dev/null | sort)
}

mapfile -t SESSIONS < <(agent_sessions)
if [ "${#SESSIONS[@]}" -eq 0 ]; then
  echo "No agent sessions found on $SOCK (filter: '$FILTER'; use --all to include everything)." >&2
  echo "Existing sessions:" >&2
  tmux_s list-sessions -F '  #{session_name}' >&2
  exit 0
fi

run_switcher() {
  tmux_s kill-session -t "$VIEW" 2>/dev/null || true
  tmux_s new-session -d -s "$VIEW" -n _seed bash
  # Don't let a small viewer client shrink the agents' panes.
  tmux_s set-option -t "$VIEW" window-size largest >/dev/null 2>&1 || true
  tmux_s set-option -t "$VIEW" mouse on >/dev/null 2>&1 || true

  local s w linked=0
  for s in "${SESSIONS[@]}"; do
    while read -r w; do
      if tmux_s link-window -s "${s}:${w}" -t "${VIEW}:" 2>/dev/null; then
        linked=$((linked + 1))
      fi
    done < <(tmux_s list-windows -t "$s" -F '#{window_index}' 2>/dev/null)
  done

  if [ "$linked" -eq 0 ]; then
    echo "Could not link any agent windows." >&2
    tmux_s kill-session -t "$VIEW" 2>/dev/null || true
    exit 1
  fi
  tmux_s kill-window -t "${VIEW}:_seed" 2>/dev/null || true

  echo "Switcher: ${#SESSIONS[@]} agent session(s), $linked window(s)."
  echo "  C-b n / C-b p  switch agents     C-b w  pick from a list     C-b d  detach"
  [ "$RW" = 0 ] && echo "  (read-only -- pass --rw to type into agents)"

  if [ "$RW" = 1 ]; then
    tmux_s attach-session -t "$VIEW"
  else
    tmux_s attach-session -r -t "$VIEW"
  fi
  tmux_s kill-session -t "$VIEW" 2>/dev/null || true
}

# The live-mirror loop each dashboard tile runs. Shipped as a temp script (rather
# than an inlined command) so the trailing-blank trim + tail logic stays readable.
# It shows the agent's most recent output sized to the live tile height: capture
# the agent pane, drop trailing blank rows (an idle agent leaves the bottom of its
# pane empty), then print the last $h lines. $TMUX_PANE is set per pane so the tile
# can read its own current height. The tile is labelled via its pane border title.
write_mirror_script() {
  cat > "$1" <<'MIRROR'
#!/bin/bash
SOCK="$1"; TARGET="$2"; INTERVAL="${3:-0.5}"
while tmux -S "$SOCK" has-session -t "$TARGET" 2>/dev/null; do
  h=$(tmux -S "$SOCK" display -p -t "$TMUX_PANE" '#{pane_height}' 2>/dev/null); h=${h:-20}
  mapfile -t L < <(tmux -S "$SOCK" capture-pane -p -t "$TARGET")
  last=${#L[@]}
  while [ "$last" -gt 0 ] && [ -z "${L[$((last-1))]//[[:space:]]/}" ]; do last=$((last-1)); done
  start=$((last - h)); [ "$start" -lt 0 ] && start=0
  clear
  for ((i=start; i<last; i++)); do printf '%s\n' "${L[$i]}"; done
  sleep "$INTERVAL"
done
clear; printf '[%s ended]\n' "$TARGET"; sleep 5
MIRROR
}

run_dashboard() {
  tmux_s kill-session -t "$DASH" 2>/dev/null || true
  local mirror; mirror="$(mktemp "${TMPDIR:-/tmp}/shared-tmux-mirror.XXXXXX.sh")"
  write_mirror_script "$mirror"

  local first=1 s pane
  for s in "${SESSIONS[@]}"; do
    if [ "$first" = 1 ]; then
      tmux_s new-session -d -s "$DASH" -n grid bash "$mirror" "$SOCK" "$s" "$INTERVAL"
      pane="$(tmux_s display -p -t "$DASH:grid" '#{pane_id}')"
      first=0
    else
      pane="$(tmux_s split-window -t "$DASH:grid" -P -F '#{pane_id}' bash "$mirror" "$SOCK" "$s" "$INTERVAL")"
      tmux_s select-layout -t "$DASH:grid" tiled >/dev/null
    fi
    tmux_s select-pane -t "$pane" -T "$s" >/dev/null 2>&1 || true
  done
  tmux_s select-layout -t "$DASH:grid" tiled >/dev/null
  tmux_s set-option -w -t "$DASH:grid" pane-border-status top >/dev/null 2>&1 || true
  tmux_s set-option -w -t "$DASH:grid" pane-border-format ' #{pane_title} ' >/dev/null 2>&1 || true
  tmux_s set-option -t "$DASH" mouse on >/dev/null 2>&1 || true

  echo "Dashboard: mirroring ${#SESSIONS[@]} agent session(s), refresh ${INTERVAL}s."
  echo "  Scroll with the mouse / C-b [.   C-b d  detach."
  tmux_s attach-session -t "$DASH"
  tmux_s kill-session -t "$DASH" 2>/dev/null || true
  rm -f "$mirror" 2>/dev/null || true
}

case "$MODE" in
  switcher)  run_switcher ;;
  dashboard) run_dashboard ;;
esac
