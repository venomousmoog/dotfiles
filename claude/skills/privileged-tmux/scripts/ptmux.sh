#!/bin/bash
# ptmux.sh -- drive a private bash pane on the *shared* tmux server.
#
# Why this exists: the agent's normal Bash tool is stateless (every call is a
# fresh process), has no TTY, and runs under the harness sandbox/permission
# gating. The shared tmux server (created by shared-tmux.sh on socket
# /tmp/tmux-shared/shared) is a real, persistent, TTY-backed shell that runs in
# the full login environment -- so it's where you run privileged/sudo commands,
# interactive REPLs and prompts, long-running jobs, or anything that must keep
# shell state across calls.
#
# Many agents attach to the SAME server. To avoid clobbering each other's panes,
# every agent gets its OWN session, named from its Claude session id by default
# (override with $PTMUX_SESSION). You never touch another agent's session.
#
# Usage:
#   ptmux.sh ensure                 Create the server (if needed) + your private
#                                   bash session; wait until ready; print its name.
#   ptmux.sh run "<cmd>" [timeout]  Run cmd, wait, print stdout+stderr, exit with
#                                   the command's own exit code. timeout secs
#                                   (default 600); on timeout returns 124 and the
#                                   command keeps running (interrupt with `key C-c`).
#   ptmux.sh start "<cmd>"          Fire-and-forget: run cmd in the pane and return
#                                   immediately (long-running / things you'll watch).
#                                   Output stays in the pane; read it with `capture`.
#   ptmux.sh send "<text>"          Type literal text + Enter (answer a prompt, feed
#                                   a REPL, type a sudo password).
#   ptmux.sh key <keys...>          Send raw tmux keys, no Enter (e.g. `key C-c`,
#                                   `key Up Enter`).
#   ptmux.sh capture [lines]        Print the pane. With [lines], include that many
#                                   lines of scrollback.
#   ptmux.sh name                   Print the resolved session name and exit.
#   ptmux.sh list                   List agent sessions on the shared server.
#   ptmux.sh kill                   Kill your session and clean up its workdir.
#
# Env overrides:
#   PTMUX_SESSION   session name (default: agent-<first8 of CLAUDE_CODE_SESSION_ID>)
#   PTMUX_SOCKET    server socket   (default: /tmp/tmux-shared/shared)
#   PTMUX_COLS/ROWS new-pane size   (default: 200x50)

set -uo pipefail

SOCK="${PTMUX_SOCKET:-/tmp/tmux-shared/shared}"
SHARED_DIR="$(dirname "$SOCK")"
AGENTS_DIR="$SHARED_DIR/agents"

tmux_s() { tmux -S "$SOCK" "$@"; }

resolve_name() {
  if [ -n "${PTMUX_SESSION:-}" ]; then printf '%s\n' "$PTMUX_SESSION"; return; fi
  local sid="${CLAUDE_CODE_SESSION_ID:-${CC_SESSION_ID:-${CLAUDE_CODE_CURRENT_SESSION_ID:-}}}"
  if [ -n "$sid" ]; then printf 'agent-%s\n' "${sid:0:8}"; return; fi
  printf 'agent-%s\n' "$$"
}

NAME="$(resolve_name)"
WD="$AGENTS_DIR/$NAME"

die() { printf 'ptmux: %s\n' "$*" >&2; exit 2; }

# Wait until the pane's bash has actually started and is reading input. ~/.bashrc
# may block on the dotfiles bootstrap (waiting for env sync) on a cold machine,
# so allow a generous timeout.
readiness_wait() {
  local timeout="${1:-120}" m="__PTMUX_READY_${NAME}__" lf="$WD/.ready"
  mkdir -p "$WD"; : > "$lf"
  tmux_s send-keys -t "$NAME" "printf '%s\\n' $m > '$lf'" Enter
  local n=0 max=$((timeout * 10))
  while ! grep -q "$m" "$lf" 2>/dev/null; do
    sleep 0.1; n=$((n + 1))
    [ "$n" -ge "$max" ] && return 1
  done
  return 0
}

ensure() {
  mkdir -p "$SHARED_DIR" "$WD" 2>/dev/null
  if ! tmux_s has-session -t "$NAME" 2>/dev/null; then
    # Force bash -- the shared server's default-command is the login shell (pwsh
    # here), so we must pass bash explicitly or we'd get the wrong shell.
    tmux_s new-session -d -s "$NAME" -n main \
      -x "${PTMUX_COLS:-200}" -y "${PTMUX_ROWS:-50}" bash || die "could not start session $NAME"
    # World-rw socket so other users' agents can share this server (best effort).
    chmod 777 "$SOCK" 2>/dev/null || true
    sleep 0.3
    readiness_wait 120 || die "pane bash never became ready (cold ~/.bashrc?)"
  fi
}

# Write the script the pane will source. cap=1 captures output+exit to $logf with
# a completion marker; cap=0 just runs the command (output stays in the pane).
# The command is written verbatim (printf '%s'), so no quoting/escaping surprises,
# and it runs in a brace group (not a subshell) so cd/export persist across calls.
write_cmd_file() {
  local cmdf="$1" logf="$2" marker="$3" cmd="$4" cap="$5"
  if [ "$cap" = 1 ]; then
    {
      printf '{\n'
      printf '%s\n' "$cmd"
      printf '} > %q 2>&1\n' "$logf"
      printf 'printf "PTMUX_EXIT:%%s\\n" "$?" >> %q\n' "$logf"
      printf 'printf "%%s\\n" %q >> %q\n' "$marker" "$logf"
    } > "$cmdf"
  else
    printf '%s\n' "$cmd" > "$cmdf"
  fi
}

stamp() { printf '%s-%s' "$(date +%s%N)" "${RANDOM}${RANDOM}"; }

cmd_run() {
  [ $# -ge 1 ] || die "run needs a command"
  local cmd="$1" timeout="${2:-600}"
  ensure
  local st; st="$(stamp)"
  local cmdf="$WD/cmd-$st.sh" logf="$WD/out-$st.log" marker="__PTMUX_DONE_${st}__"
  : > "$logf"
  write_cmd_file "$cmdf" "$logf" "$marker" "$cmd" 1
  tmux_s send-keys -t "$NAME" "source '$cmdf'" Enter
  local n=0 max=$((timeout * 10)) timed_out=0
  while ! grep -q "$marker" "$logf" 2>/dev/null; do
    # If the pane closed before the marker landed, the command exited the shell
    # itself (e.g. called `exit`/`logout`, or crashed it). Bail fast rather than
    # waiting out the full timeout. Check once a second to keep polling cheap.
    if [ $((n % 10)) -eq 0 ] && ! tmux_s has-session -t "$NAME" 2>/dev/null; then
      sed -e "/^${marker}\$/d" -e '/^PTMUX_EXIT:/d' "$logf" 2>/dev/null
      printf 'ptmux: pane %s closed before the command finished -- it likely called exit/logout or crashed the shell. Re-run to recreate the session.\n' "$NAME" >&2
      rm -f "$cmdf"
      return 125
    fi
    sleep 0.1; n=$((n + 1))
    if [ "$n" -ge "$max" ]; then timed_out=1; break; fi
  done
  if [ "$timed_out" = 1 ]; then
    sed -e "/^${marker}\$/d" -e '/^PTMUX_EXIT:/d' "$logf" 2>/dev/null
    printf 'ptmux: command still running after %ss (interrupt with: ptmux.sh key C-c)\n' "$timeout" >&2
    rm -f "$cmdf"
    return 124
  fi
  local rc; rc="$(grep '^PTMUX_EXIT:' "$logf" | tail -1 | cut -d: -f2)"
  sed -e "/^${marker}\$/d" -e '/^PTMUX_EXIT:/d' "$logf"
  rm -f "$cmdf" "$logf"
  return "${rc:-0}"
}

cmd_start() {
  [ $# -ge 1 ] || die "start needs a command"
  ensure
  local st; st="$(stamp)"
  local cmdf="$WD/start-$st.sh"
  write_cmd_file "$cmdf" "" "" "$1" 0
  tmux_s send-keys -t "$NAME" "source '$cmdf'" Enter
  printf 'started in %s (watch: ptmux.sh capture)\n' "$NAME"
}

cmd_send() {
  [ $# -ge 1 ] || die "send needs text"
  ensure
  tmux_s send-keys -t "$NAME" -l "$1"
  tmux_s send-keys -t "$NAME" Enter
}

cmd_key() {
  [ $# -ge 1 ] || die "key needs at least one key"
  ensure
  tmux_s send-keys -t "$NAME" "$@"
}

cmd_capture() {
  tmux_s has-session -t "$NAME" 2>/dev/null || die "no session $NAME (run ensure first)"
  if [ $# -ge 1 ] && [ -n "$1" ]; then
    tmux_s capture-pane -p -t "$NAME" -S "-$1"
  else
    tmux_s capture-pane -p -t "$NAME"
  fi
}

cmd_list() {
  tmux_s list-sessions \
    -F '#{session_name}  (#{session_windows} win, attached=#{session_attached})' 2>/dev/null \
    | grep -E '^agent-' || printf '(no agent sessions on %s)\n' "$SOCK"
}

cmd_kill() {
  tmux_s kill-session -t "$NAME" 2>/dev/null || true
  rm -rf "$WD" 2>/dev/null || true
  printf 'killed %s\n' "$NAME"
}

sub="${1:-}"; shift || true
case "$sub" in
  ensure)  ensure; printf '%s\n' "$NAME" ;;
  run)     cmd_run "$@" ;;
  start)   cmd_start "$@" ;;
  send)    cmd_send "$@" ;;
  key)     cmd_key "$@" ;;
  capture) cmd_capture "$@" ;;
  name)    printf '%s\n' "$NAME" ;;
  list)    cmd_list ;;
  kill)    cmd_kill ;;
  ""|-h|--help)
    sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $sub (try --help)" ;;
esac
