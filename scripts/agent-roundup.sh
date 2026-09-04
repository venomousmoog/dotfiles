#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Morning orientation roundup: ask every live acd agent in the AC mesh what it
# is working on, collect the replies, and publish them as one mdoc.
#
# Runs from any host in the mesh: a Worker routes --host RPCs to its peers just
# as the Conductor does. Hosts missing from `acd host list` (an uplink that is
# down) are reported as unreachable rather than silently dropped.
#
# Usage:
#   agent-roundup.sh [options]
#
# Options:
#   --timeout N        per-agent reply budget in seconds (default 180)
#   --start-timeout N  seconds to wait for a booting harness (default 90)
#   --skip-busy        leave agents that are mid-turn alone
#   --only NAME|PTY    prompt only this agent; repeatable
#   --modes a,b,c      agent modes to prompt (default claude,codex,metacode,mhemate)
#   --no-mdoc          write the markdown locally and stop
#   --share-id ID      update an existing orientation mdoc instead of creating one
#   --open             open the published mdoc in the browser via `acd urlopen`
#   --dry-run          print the roster and the prompt, ask nobody
#   -h, --help         show this help

# shellcheck disable=SC2016  # single-quoted backticks in printf are markdown, not subshells

set -euo pipefail

# Replies typically land in 30-60s. The timeout only bites on agents that never
# answer, and it sets the floor on total runtime, so keep it tight.
TIMEOUT=180
START_TIMEOUT=90
POLL_EVERY=5
SKIP_BUSY=0
ONLY=""
MODES="claude,codex,metacode,mhemate"
DO_MDOC=1
SHARE_ID=""
OPEN_DOC=0
DRY_RUN=0

# Print the header comment block, stopping at the first non-comment line so the
# help text cannot drift when code is added below it.
usage() {
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)       TIMEOUT="$2"; shift 2 ;;
        --start-timeout) START_TIMEOUT="$2"; shift 2 ;;
        --skip-busy)     SKIP_BUSY=1; shift ;;
        --only)          ONLY="$ONLY
$2"; shift 2 ;;
        --modes)         MODES="$2"; shift 2 ;;
        --no-mdoc)       DO_MDOC=0; shift ;;
        --share-id)      SHARE_ID="$2"; shift 2 ;;
        --open)          OPEN_DOC=1; shift ;;
        --dry-run)       DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "agent-roundup: unknown option '$1' (try --help)" >&2; exit 2 ;;
    esac
done

for _tool in acd jq; do
    command -v "$_tool" >/dev/null 2>&1 || {
        echo "agent-roundup: '$_tool' is not in PATH" >&2; exit 1; }
done
if [[ $DO_MDOC -eq 1 && $DRY_RUN -eq 0 ]] && ! command -v meta >/dev/null 2>&1; then
    echo "agent-roundup: 'meta' is not in PATH -- rerun with --no-mdoc" >&2
    exit 1
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
STAMP="$(date '+%Y-%m-%d %H:%M %Z')"
REMOTE_DIR="/tmp/agent-roundup/$RUN_ID"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent-roundup.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OUT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-roundup"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/orientation-$RUN_ID.md"

# --- The prompt every agent gets ------------------------------------------
# Sent as a SINGLE line: `acd agent prompt` writes the text to the PTY and then
# submits, so an embedded newline would submit a partial prompt.
#
# The agent hands its report back through a PTY env marker rather than a file.
# `acd cp` relays peer-to-peer transfers through the Conductor and, when neither
# endpoint is the Conductor, leaves the payload there while still reporting
# `cp ok` against the destination path -- so a Worker-run roundup would collect
# nothing. set-env/get-env needs no relay and round-trips base64 byte-exact.
prompt_text() {
    local file="$1" pty="$2"
    printf '%s' "STATUS ROUNDUP (automated, run $RUN_ID) -- read-only: do not start, change, submit or land any work. Step 1: with the Write tool, write EXACTLY two markdown lines to $file (create parent directories), nothing else: '- **Status:** <what you were most recently working on for Dave and where it now stands>' and '- **Follow-ups:** <what you need from Dave, or the single word none>'. Keep each line under 60 words and on ONE line. Step 2: hand it back by running exactly the bash command between these markers, and nothing else: <<CMD>> acd agent set-env $pty --env $ENV_KEY=\"\$(base64 < $file | tr -d '\n')\" <</CMD>> Step 3: print the two lines. Rules: if you cite a diff status you MUST re-query it this turn with 'meta phabricator.diff describe -n D<num>', otherwise write 'not checked'; do not edit any file other than $file; do not run builds or tests; then stop."
}

# --- Topology -------------------------------------------------------------
acd agent list --all --json > "$WORK/roster.json"
acd host list --json  > "$WORK/topo.json"  2>/dev/null || echo '{"hosts":[]}' > "$WORK/topo.json"
acd agent list --json > "$WORK/local.json" 2>/dev/null || echo '{"hosts":[]}' > "$WORK/local.json"

LOCAL_PTYS="$(jq -r '(.hosts // [])[] | (.agents // [])[] | (.ptyId // .id) // empty' "$WORK/local.json")"

# Namespaced per run, so a get-env read can never pick up a previous roundup's answer.
ENV_KEY="ROUNDUP_$(printf '%s' "$RUN_ID" | tr -c 'A-Za-z0-9' '_')"

# `acd cp` needs a canonical hostname on both endpoints; bare paths are rejected.
SELF_CANON="$(acd agent whoami --json 2>/dev/null | jq -r '.canonicalHostname // empty' || true)"
if [[ -z "$SELF_CANON" ]]; then
    SELF_CANON="$(jq -r --arg ptys "$LOCAL_PTYS" '
        ($ptys | split("\n") | map(select(length > 0))) as $mine
        | (.hosts // [])[]
        | select([(.agents // [])[] | (.ptyId // .id)]
                 | map(. as $p | ($mine | index($p)) != null) | any)
        | .canonicalHostname // empty' "$WORK/topo.json" | head -1)"
fi
[[ -n "$SELF_CANON" ]] || SELF_CANON="$( { hostname -f 2>/dev/null || hostname; } | tr -d '\n')"

CONDUCTOR_CANON="$(jq -r '(.hosts // [])[] | select(.role == "conductor")
                          | .canonicalHostname // empty' "$WORK/topo.json" | head -1)"

# --- Build the target list ------------------------------------------------
SELF_PTY="$(acd agent whoami --json 2>/dev/null | jq -r '.ptyId // empty' || true)"

# Fields are separated by US (0x1f), not tab. Tab is an IFS *whitespace*
# character, so `IFS=tab read` collapses runs of it -- one empty column (jq
# defaults several to "") would silently shift every field after it. US is not
# IFS whitespace, so empty fields survive. Values are scrubbed of the separator
# and of newlines because agent names, cwds and titles are not trusted input.
#
# The mesh-wide roster reports the Conductor's own host as the literal "local"
# -- a daemon-relative routing key, not a name. `acd host list --json` carries
# both forms per host, so each roster key is resolved through that table into a
# canonical hostname, which is what --host and `acd cp` endpoints want. A key
# with no canonical is a host this daemon has no route to.
US="$(printf '\037')"
jq -r --slurpfile topo "$WORK/topo.json" '
    def clean: (. // "") | tostring | gsub("[\n\r\t\u001f]"; " ");
    (($topo[0].hosts) // []) as $known
    | (.hosts // [])[] as $h
    | (($h.hostname) // "") as $key
    | ([ $known[]
         | select((.hostname // "") == $key or (.canonicalHostname // "") == $key)
         | .canonicalHostname ] | first // "") as $canon
    | ($h.agents // [])[]
    | [ ($key | clean), ($canon | clean), ((.ptyId // .id) | clean), (.name | clean),
        (.mode | clean), (.status | clean), (.cwd | clean) ]
    | join("\u001f")' "$WORK/roster.json" \
    | sort -t"$US" -k2,2 -k4,4 > "$WORK/agents.tsv"

: > "$WORK/targets.tsv"
IDX=0
while IFS="$US" read -r key canon pty name mode status cwd; do
    [[ -n "$pty" ]] || continue
    IDX=$((IDX + 1))
    slug="$IDX-$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
    # An empty canonical means this daemon has no route to that host.
    host="${canon:-$key}"

    action="prompt"
    # The self check has to come first: prompting ourselves would deadlock on --wait.
    if [[ -n "$SELF_PTY" && "$pty" == "$SELF_PTY" ]]; then
        action="skip:this agent (the one running the roundup)"
    elif [[ -n "$ONLY" ]] \
        && ! printf '%s\n' "$ONLY" | grep -Fxq -- "$name" \
        && ! printf '%s\n' "$ONLY" | grep -Fxq -- "$pty"; then
        action="skip:not selected by --only"
    elif [[ "$status" == "dead" || "$status" == "exited" ]]; then
        action="skip:not alive (status $status)"
    elif ! printf '%s' ",$MODES," | grep -q ",$mode,"; then
        action="skip:mode '$mode' is not prompt-able"
    elif [[ $SKIP_BUSY -eq 1 && "$status" == "working" ]]; then
        action="skip:mid-turn and --skip-busy was set"
    elif [[ -z "$canon" ]]; then
        action="unreachable:host '$key' is not in this daemon's topology"
    fi

    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$host" "$US" "$key" "$US" "$pty" "$US" "$name" "$US" "$mode" "$US" \
        "$status" "$US" "$cwd" "$US" "$slug" "$US" "$action" >> "$WORK/targets.tsv"
done < "$WORK/agents.tsv"

TOTAL=$(wc -l < "$WORK/targets.tsv" | tr -d ' ')
ASKING=$(grep -c -- "${US}prompt\$" "$WORK/targets.tsv" || true)

echo "agent-roundup $RUN_ID: $TOTAL agent(s) in the mesh, prompting $ASKING" >&2
echo "  this daemon: ${SELF_CANON:-unknown}${CONDUCTOR_CANON:+ (conductor: $CONDUCTOR_CANON)}" >&2

if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n%-22s %-34s %-9s %-9s %s\n' AGENT HOST MODE STATUS ACTION >&2
    while IFS="$US" read -r host key pty name mode status cwd slug action; do
        printf '%-22s %-34s %-9s %-9s %s\n' \
            "$name" "$host" "$mode" "$status" "$action" >&2
    done < "$WORK/targets.tsv"
    printf '\nPrompt that would be sent:\n\n%s\n' \
        "$(prompt_text "$REMOTE_DIR/<agent>.md" "<agent-pty>")" >&2
    exit 0
fi

# --- Ask everyone in parallel --------------------------------------------
# Older macOS base64 spells decode -D, GNU spells it -d. Probe once rather than
# retrying on failure -- a failed first attempt would have consumed stdin.
B64_DECODE=-d
printf 'eA==' | base64 -d >/dev/null 2>&1 || B64_DECODE=-D
b64_decode() { base64 "$B64_DECODE"; }

strip_ansi() {
    local esc bel
    esc="$(printf '\033')"; bel="$(printf '\007')"
    sed -e "s/${esc}\[[0-9;?]*[a-zA-Z]//g" -e "s/${esc}\][^${bel}]*${bel}//g"
}

# Terminal scrollback is the last-resort source; keep only the printed report.
extract_report() {
    local f="$1" start
    start="$(grep -n '\*\*Status:\*\*' "$f" | tail -1 | cut -d: -f1 || true)"
    if [[ -n "$start" ]]; then tail -n "+$start" "$f"; else tail -n 40 "$f"; fi
}

# The TUI wraps long lines and pads every continuation word out to the terminal
# width, so scraped bullets arrive shredded. Collapse the padding and rejoin
# continuations onto the markdown line they belong to.
unwrap_md() {
    sed -e 's/[[:space:]]\{3,\}/ /g' -e 's/[[:space:]]*$//' \
    | awk '/^[[:space:]]*([-*]|#{1,6})[[:space:]]/ { if (buf != "") print buf; buf = $0; next }
           /^[[:space:]]*$/                        { if (buf != "") print buf; buf = ""; print ""; next }
                                                   { if (buf == "") buf = $0; else buf = buf " " $0 }
           END                                     { if (buf != "") print buf }'
}

# Hostnames are FQDNs with no whitespace, so an unquoted $hf expansion is safe
# and lets the flag disappear entirely for the local daemon.
host_flag() {
    [[ "$1" == "$SELF_CANON" ]] || printf -- '--host %s' "$1"
}

# Terminal titles give every routable agent a headline even when it never
# replies, so the roster is still legible for busy and skipped agents.
# shellcheck disable=SC2086
enrich_agent() {
    local host="$1" pty="$2" slug="$3" hf
    hf="$(host_flag "$host")"
    acd agent show $hf "$pty" --json > "$WORK/$slug.info" 2>/dev/null \
        || echo '{}' > "$WORK/$slug.info"
}

# shellcheck disable=SC2086  # $hf is a deliberate word-split flag pair
probe_agent() {
    local host="$1" pty="$2" slug="$3"
    local hf remote="$REMOTE_DIR/$slug.md" body="$WORK/$slug.body"
    hf="$(host_flag "$host")"

    if acd agent prompt $hf "$pty" "$(prompt_text "$remote" "$pty")" --wait \
            --timeout "$TIMEOUT" --start-timeout "$START_TIMEOUT" \
            >/dev/null 2>"$WORK/$slug.err"; then
        echo ok > "$WORK/$slug.rc"
    else
        echo "wait-failed" > "$WORK/$slug.rc"
    fi

    : > "$body"

    # 1. The env marker: lossless and routable to any host we can prompt.
    #
    # Poll for it rather than reading once. `--wait` returns early whenever its
    # own poll loop hits an error -- a flapping daemon uplink makes it come back
    # in seconds with the agent still mid-answer -- so treating it as the gate
    # loses replies that are simply not written yet. The prompt is already
    # delivered at this point; the marker appearing is the real completion
    # signal, and $TIMEOUT is the real budget.
    # An agent that took the turn and ended it without handing anything back is
    # done, not slow, so waiting out the rest of $TIMEOUT for it just delays the
    # whole run. Give up once it has gone busy and come back to rest empty --
    # but only after seeing it busy, since "idle" is also the pre-start state.
    local waited=0 got="" hs="" saw_busy=0
    while :; do
        got="$(acd agent get-env $hf "$pty" --key "$ENV_KEY" 2>/dev/null | tr -d '\r\n' || true)"
        if [[ -n "$got" ]]; then
            printf '%s' "$got" | b64_decode > "$body" 2>/dev/null || : > "$body"
            [[ -s "$body" ]] && break
        fi
        [[ $waited -ge $TIMEOUT ]] && break
        hs="$(acd agent show $hf "$pty" --json 2>/dev/null | jq -r '.hookStatus // ""' 2>/dev/null || true)"
        case "$hs" in
            working|running) saw_busy=1 ;;
            idle|done|need_input) [[ $saw_busy -eq 1 ]] && break ;;
        esac
        sleep "$POLL_EVERY"
        waited=$((waited + POLL_EVERY))
    done

    if [[ -s "$body" ]]; then
        echo env > "$WORK/$slug.src"
        acd agent unset-env $hf "$pty" --key "$ENV_KEY" >/dev/null 2>&1 || true
        return 0
    fi
    acd agent unset-env $hf "$pty" --key "$ENV_KEY" >/dev/null 2>&1 || true

    # 2. Same host: read the report the agent wrote.
    if [[ "$host" == "$SELF_CANON" && -s "$remote" ]]; then
        cat "$remote" > "$body"
        echo file > "$WORK/$slug.src"
        return 0
    fi

    # 3. Remote file copy. `acd cp` reports success between peer workers even
    #    when it writes nothing, so the destination is checked, not trusted.
    if [[ "$host" != "$SELF_CANON" ]]; then
        acd cp "$host:$remote" "$SELF_CANON:$body" >/dev/null 2>&1 || true
        if [[ -s "$body" ]]; then echo cp > "$WORK/$slug.src"; return 0; fi
    fi

    # 4. Last resort: the copy the agent printed to its own terminal.
    acd agent output $hf "$pty" --rendered-tail 200 --json 2>/dev/null \
        | jq -r '.text // ""' > "$WORK/$slug.raw" || : > "$WORK/$slug.raw"
    if [[ -s "$WORK/$slug.raw" ]]; then
        strip_ansi < "$WORK/$slug.raw" > "$WORK/$slug.clean" || : > "$WORK/$slug.clean"
        extract_report "$WORK/$slug.clean" | unwrap_md > "$body" || : > "$body"
    fi
    # A live TUI always yields *something*, so "non-empty" is not evidence of a
    # report -- without this check an agent that never answered gets a screenful
    # of box-drawing published as its status. Demand the report's own shape.
    if [[ -s "$body" ]] && grep -q '\*\*Status:\*\*' "$body" \
                        && grep -q '\*\*Follow-ups:\*\*' "$body"; then
        echo scrape > "$WORK/$slug.src"
    else
        : > "$body"
        echo none > "$WORK/$slug.src"
    fi
}

# Enrich every agent, including the ones we cannot prompt: `agent show` is
# answered from the Conductor's snapshot even for hosts we cannot route to, so
# an unreachable agent still contributes its terminal title to the roster.
PIDS=""
while IFS="$US" read -r host key pty name mode status cwd slug action; do
    echo '{}' > "$WORK/$slug.info"
    enrich_agent "$host" "$pty" "$slug" &
    PIDS="$PIDS $!"
done < "$WORK/targets.tsv"
for pid in $PIDS; do wait "$pid" || true; done

PIDS=""
while IFS="$US" read -r host key pty name mode status cwd slug action; do
    [[ "$action" == "prompt" ]] || continue
    probe_agent "$host" "$pty" "$slug" &
    PIDS="$PIDS $!"
done < "$WORK/targets.tsv"

for pid in $PIDS; do wait "$pid" || true; done

# --- Assemble the orientation doc ----------------------------------------
field() {  # field <body-file> <label>
    [[ -s "$1" ]] || return 0
    # Labels contain '/', so they have to be escaped before going into an s/// pattern.
    local label
    label="$(printf '%s' "$2" | sed 's#/#\\/#g')"
    sed -n "s/^[[:space:]]*[-*][[:space:]]*\*\*${label}:\*\*[[:space:]]*//p" "$1" | head -1
}
md_cell() { printf '%s' "${1:-}" | tr '\n' ' ' | sed -e 's/|/\\|/g' -e 's/[[:space:]]\{2,\}/ /g'; }

: > "$WORK/table.md"

while IFS="$US" read -r host key pty name mode status cwd slug action; do
    body="$WORK/$slug.body"
    # Terminal titles carry a leading status glyph that is noise in a document.
    title="$(jq -r '.terminalTitle // ""' "$WORK/$slug.info" 2>/dev/null \
        | sed 's/^[^[:alnum:]]*[[:space:]]*//' || true)"

    st="$(field "$body" 'Status')"
    fu="$(field "$body" 'Follow-ups')"

    # No reply: say so plainly and fall back to the agent's own terminal title
    # rather than inventing a summary for it.
    if [[ -z "$st" ]]; then
        case "$action" in
            skip:*)        st="_skipped_" ;;
            unreachable:*) st="_unreachable_" ;;
            *)             st="_no reply_" ;;
        esac
        [[ -n "$title" ]] && st="$st -- last title: $title"
    fi

    printf '| %s | %s | %s | %s |\n' \
        "$(md_cell "$host")" "$(md_cell "$name")" \
        "$(md_cell "$st")" "$(md_cell "${fu:--}")" >> "$WORK/table.md"
done < "$WORK/targets.tsv"

{
    printf '# Agent roundup -- %s\n\n' "$STAMP"
    printf '| Machine | Agent | Status | Follow-ups |\n'
    printf '|---|---|---|---|\n'
    cat "$WORK/table.md"
} > "$OUT"

echo "agent-roundup: wrote $OUT" >&2

# --- Publish --------------------------------------------------------------
if [[ $DO_MDOC -eq 0 ]]; then
    echo "$OUT"
    exit 0
fi

# `meta` exits non-zero on failure and prints its error JSON to stdout, so the
# assignment has to tolerate a failure -- a bare `RESP=$(meta ...)` would abort
# under `set -e` before the handler below could report where $OUT landed. An
# update without --publish only writes a draft, leaving the old content live.
# stderr is kept out of $RESP: `meta` emits unrelated settings warnings there
# that would make the response unparseable. On failure it writes its error JSON
# to stdout, so $RESP stays the useful thing to show.
RESP=""
if [[ -n "$SHARE_ID" ]]; then
    RESP="$(meta mdoc.document update --share-id "$SHARE_ID" --file "file://$OUT" \
        --title "Agent orientation -- $STAMP" --publish -o json 2>"$WORK/publish.err")" || true
else
    RESP="$(meta mdoc.document share --file "file://$OUT" \
        --title "Agent orientation -- $STAMP" --visibility private \
        -o json 2>"$WORK/publish.err")" || true
fi

URL="$(printf '%s' "$RESP" | jq -r '.url // empty' 2>/dev/null || true)"
if [[ -z "$URL" ]]; then
    echo "agent-roundup: mdoc publish failed; the collected report is at $OUT" >&2
    echo "agent-roundup: meta said:" >&2
    printf '%s\n' "$RESP" >&2
    [[ -s "$WORK/publish.err" ]] && tail -5 "$WORK/publish.err" >&2
    echo "$OUT"
    exit 1
fi

echo "$URL"
if [[ $OPEN_DOC -eq 1 ]]; then
    acd urlopen "$URL" >/dev/null 2>&1 || echo "agent-roundup: could not open $URL" >&2
fi
exit 0
