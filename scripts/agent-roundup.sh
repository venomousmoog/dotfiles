#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Morning orientation roundup: ask every live acd agent in the AC mesh what it
# is working on, collect the replies, and publish them as one mdoc.
#
# Cross-host prompting only works from the Conductor daemon. A Worker sees every
# agent (the Conductor pushes a read-only snapshot) but can only route RPCs to
# itself, so agents this daemon cannot reach are reported as unreachable rather
# than silently dropped.
#
# Usage:
#   agent-roundup.sh [options]
#
# Options:
#   --timeout N        per-agent reply budget in seconds (default 300)
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

TIMEOUT=300
START_TIMEOUT=90
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
# The agent hands its report back through a PTY env marker rather than a file:
# `acd cp` between peer workers reports success while writing nothing, and
# scraping the TUI loses text to wrap padding. set-env/get-env round-trips
# base64 byte-exact and is readable cross-host.
prompt_text() {
    local file="$1" pty="$2"
    printf '%s' "STATUS ROUNDUP (automated, run $RUN_ID) -- read-only: do not start, change, submit or land any work. Step 1: with the Write tool, write a short status report to $file (create parent directories) using exactly these markdown lines: '### <one-line headline of what you are working on>' then '- **State:** <blocked|needs-input|in-progress|waiting-on-ci|idle|done>' then '- **Working on:** <1-2 sentences>' then '- **Diffs:** <D-numbers with their current status, or none>' then '- **Blocked on / needs Dave:** <the decision or input you need from Dave; if you need none, write the single word nothing and nothing else -- never write nothing and then add caveats>' then '- **Next step:** <one line>'. Step 2: hand the report back to the roundup by running exactly the bash command between these markers, and nothing else: <<CMD>> acd agent set-env $pty --env $ENV_KEY=\"\$(base64 < $file | tr -d '\n')\" <</CMD>> Step 3: print the report. Rules: if you cite any diff status you MUST re-query it in this same turn with 'meta phabricator.diff describe -n D<num>', otherwise write 'not checked'; do not edit any file other than $file; do not run builds or tests; keep the report under 180 words; then stop."
}

# --- Topology -------------------------------------------------------------
acd agent list --all --json > "$WORK/roster.json"
acd host list --json  > "$WORK/topo.json"  2>/dev/null || echo '{"hosts":[]}' > "$WORK/topo.json"
acd agent list --json > "$WORK/local.json" 2>/dev/null || echo '{"hosts":[]}' > "$WORK/local.json"

ROUTABLE="$(jq -r '(.hosts // [])[] | .canonicalHostname // empty' "$WORK/topo.json")"
LOCAL_PTYS="$(jq -r '(.hosts // [])[] | (.agents // [])[] | (.ptyId // .id) // empty' "$WORK/local.json")"

# Which roster host are we? The mesh-wide view labels the Conductor's own host
# "local", which is daemon-relative -- it means "the mac" in the Conductor's
# snapshot but "this box" to a Worker's own RPCs. Identify self by PTY overlap
# with the local daemon rather than by that label.
SELF_HOST="$(jq -r --arg ptys "$LOCAL_PTYS" '
    ($ptys | split("\n") | map(select(length > 0))) as $mine
    | (.hosts // [])[]
    | select([(.agents // [])[] | (.ptyId // .id)]
             | map(. as $p | ($mine | index($p)) != null) | any)
    | .hostname' "$WORK/roster.json" | head -1)"
if [[ -z "$SELF_HOST" ]]; then
    _fqdn="$( { hostname -f 2>/dev/null || hostname; } | tr -d '\n')"
    if jq -e --arg h "$_fqdn" '(.hosts // []) | map(.hostname == $h) | any' \
            "$WORK/roster.json" >/dev/null 2>&1; then
        SELF_HOST="$_fqdn"
    fi
fi

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

CONDUCTOR_LABEL="$(acd agent list --all 2>/dev/null \
    | sed -n 's/^\([^ ].*\) (conductor,.*/\1/p' | head -1)"
[[ -n "$CONDUCTOR_LABEL" ]] || CONDUCTOR_LABEL="the Conductor"

# `local` is only a valid RPC target when this daemon *is* the Conductor.
is_routable() {
    [[ -n "$SELF_HOST" && "$1" == "$SELF_HOST" ]] && return 0
    [[ "$1" == "local" ]] && return 1
    printf '%s\n' "$ROUTABLE" | grep -Fxq -- "$1"
}

display_host() {
    if [[ "$1" == "local" ]]; then printf '%s' "$CONDUCTOR_LABEL"; else printf '%s' "$1"; fi
}

# --- Build the target list ------------------------------------------------
SELF_PTY="$(acd agent whoami --json 2>/dev/null | jq -r '.ptyId // empty' || true)"

# Fields are separated by US (0x1f), not tab. Tab is an IFS *whitespace*
# character, so `IFS=tab read` collapses runs of it -- one empty column (jq
# defaults several to "") would silently shift every field after it. US is not
# IFS whitespace, so empty fields survive. Values are scrubbed of the separator
# and of newlines because agent names, cwds and titles are not trusted input.
US="$(printf '\037')"
jq -r '
    def clean: (. // "") | tostring | gsub("[\n\r\t\u001f]"; " ");
    (.hosts // [])[] as $h | ($h.agents // [])[]
    | [ ($h.hostname | clean), ((.ptyId // .id) | clean), (.name | clean),
        (.mode | clean), (.status | clean), (.cwd | clean) ]
    | join("\u001f")' "$WORK/roster.json" \
    | sort -t"$US" -k1,1 -k3,3 > "$WORK/agents.tsv"

: > "$WORK/targets.tsv"
IDX=0
while IFS="$US" read -r host pty name mode status cwd; do
    [[ -n "$pty" ]] || continue
    IDX=$((IDX + 1))
    slug="$IDX-$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"

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
    elif ! is_routable "$host"; then
        action="unreachable:no route from this daemon -- run the roundup on $CONDUCTOR_LABEL"
    fi

    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$host" "$US" "$pty" "$US" "$name" "$US" "$mode" "$US" "$status" "$US" \
        "$cwd" "$US" "$slug" "$US" "$action" >> "$WORK/targets.tsv"
done < "$WORK/agents.tsv"

TOTAL=$(wc -l < "$WORK/targets.tsv" | tr -d ' ')
ASKING=$(grep -c -- "${US}prompt\$" "$WORK/targets.tsv" || true)

echo "agent-roundup $RUN_ID: $TOTAL agent(s) in the mesh, prompting $ASKING" >&2
if [[ -n "$SELF_HOST" ]]; then
    echo "  this daemon: $(display_host "$SELF_HOST")" >&2
else
    echo "  this daemon: could not identify itself in the mesh view" >&2
fi

if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n%-22s %-34s %-9s %-9s %s\n' AGENT HOST MODE STATUS ACTION >&2
    while IFS="$US" read -r host pty name mode status cwd slug action; do
        printf '%-22s %-34s %-9s %-9s %s\n' \
            "$name" "$(display_host "$host")" "$mode" "$status" "$action" >&2
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
    start="$(grep -n '^[[:space:]]*###[[:space:]]' "$f" | tail -1 | cut -d: -f1 || true)"
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
    [[ "$1" == "$SELF_HOST" ]] || printf -- '--host %s' "$1"
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
        echo "timeout" > "$WORK/$slug.rc"
    fi

    # A timed-out prompt may still have produced an answer, so always collect.
    : > "$body"

    # 1. The env marker: lossless and routable to any host we can prompt.
    acd agent get-env $hf "$pty" --key "$ENV_KEY" 2>/dev/null \
        | tr -d '\r\n' | b64_decode > "$body" 2>/dev/null || : > "$body"
    if [[ -s "$body" ]]; then
        echo env > "$WORK/$slug.src"
        acd agent unset-env $hf "$pty" --key "$ENV_KEY" >/dev/null 2>&1 || true
        return 0
    fi
    acd agent unset-env $hf "$pty" --key "$ENV_KEY" >/dev/null 2>&1 || true

    # 2. Same host: read the report the agent wrote.
    if [[ "$host" == "$SELF_HOST" && -s "$remote" ]]; then
        cat "$remote" > "$body"
        echo file > "$WORK/$slug.src"
        return 0
    fi

    # 3. Remote file copy. `acd cp` reports success between peer workers even
    #    when it writes nothing, so the destination is checked, not trusted.
    if [[ "$host" != "$SELF_HOST" && -n "$SELF_CANON" ]]; then
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
    if [[ -s "$body" ]] && grep -q '^[[:space:]]*###[[:space:]]' "$body" \
                        && grep -q '\*\*State:\*\*' "$body"; then
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
while IFS="$US" read -r host pty name mode status cwd slug action; do
    echo '{}' > "$WORK/$slug.info"
    enrich_agent "$host" "$pty" "$slug" &
    PIDS="$PIDS $!"
done < "$WORK/targets.tsv"
for pid in $PIDS; do wait "$pid" || true; done

PIDS=""
while IFS="$US" read -r host pty name mode status cwd slug action; do
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
headline() {
    [[ -s "$1" ]] || return 0
    sed -n 's/^[[:space:]]*###[[:space:]]*//p' "$1" | head -1
}
is_nothing() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' .')" in
        ''|nothing|none|na|n/a|-|nothingyet) return 0 ;;
        *) return 1 ;;
    esac
}
md_cell() { printf '%s' "${1:-}" | tr '\n' ' ' | sed -e 's/|/\\|/g' -e 's/[[:space:]]\{2,\}/ /g'; }

REPLIED=0; SCRAPED=0; SILENT=0; SKIPPED=0; UNREACHABLE=0

: > "$WORK/needs-you.md"
: > "$WORK/table.md"
: > "$WORK/reports.md"
: > "$WORK/not-reached.md"

while IFS="$US" read -r host pty name mode status cwd slug action; do
    dhost="$(display_host "$host")"
    body="$WORK/$slug.body"
    src="none"; [[ -f "$WORK/$slug.src" ]] && src="$(cat "$WORK/$slug.src")"
    # Terminal titles carry a leading status glyph that is noise in a document.
    title="$(jq -r '.terminalTitle // ""' "$WORK/$slug.info" 2>/dev/null \
        | sed 's/^[^[:alnum:]]*[[:space:]]*//' || true)"

    case "$action" in
        prompt)
            case "$src" in
                env|file|cp) REPLIED=$((REPLIED + 1)) ;;
                scrape)      SCRAPED=$((SCRAPED + 1)) ;;
                *)           SILENT=$((SILENT + 1)) ;;
            esac
            ;;
        unreachable:*) UNREACHABLE=$((UNREACHABLE + 1)) ;;
        skip:*)        SKIPPED=$((SKIPPED + 1)) ;;
    esac

    hl="$(headline "$body")"
    st="$(field "$body" 'State')"
    blocked="$(field "$body" 'Blocked on / needs Dave')"
    [[ -n "$hl" ]] || hl="$title"
    if [[ -z "$st" ]]; then
        case "$action" in
            prompt)        st="_no reply_" ;;
            skip:*)        st="_skipped_" ;;
            unreachable:*) st="_unreachable_" ;;
        esac
    fi

    printf '| %s | %s | %s | %s | %s | %s |\n' \
        "$(md_cell "$name")" "$(md_cell "$dhost")" "$(md_cell "$mode")" \
        "$(md_cell "${status:--}")" "$(md_cell "$st")" "$(md_cell "${hl:--}")" >> "$WORK/table.md"

    if [[ -n "$blocked" ]] && ! is_nothing "$blocked"; then
        printf -- '- **%s** (%s) -- %s\n' "$name" "$dhost" "$(md_cell "$blocked")" >> "$WORK/needs-you.md"
    fi

    if [[ -s "$body" ]]; then
        {
            printf '### %s -- %s\n\n' "$name" "$dhost"
            printf '`%s` | cwd `%s` | AC status `%s`' "$mode" "${cwd:-?}" "${status:-?}"
            [[ "$src" == "scrape" ]] && printf ' | _recovered from terminal scrollback_'
            printf '\n\n'
            # Truncate BEFORE the rewrite: with `sed ... | head`, head closes the
            # pipe first, sed dies on SIGPIPE, and pipefail + set -e abort the
            # whole run here -- after every agent has already been prompted.
            # The agent's own '###' headline nests under the per-agent heading above.
            head -80 "$body" | sed 's/^[[:space:]]*###[[:space:]]*\(.*\)$/**\1**/'
            printf '\n'
        } >> "$WORK/reports.md"
    else
        reason="$action"
        case "$action" in
            prompt)       reason="prompted, no report within ${TIMEOUT}s" ;;
            skip:*)       reason="${action#skip:}" ;;
            unreachable:*) reason="${action#unreachable:}" ;;
        esac
        printf -- '- **%s** (%s, `%s`, status `%s`) -- %s%s\n' \
            "$name" "$dhost" "$mode" "$status" "$reason" \
            "$([[ -n "$title" ]] && printf ' | last title: %s' "$(md_cell "$title")")" \
            >> "$WORK/not-reached.md"
    fi
done < "$WORK/targets.tsv"

{
    printf '# Agent orientation -- %s\n\n' "$STAMP"
    printf 'Run `%s` from `%s`. %s agent(s) in the mesh: %s reported, %s recovered from scrollback, %s silent, %s skipped, %s unreachable.\n\n' \
        "$RUN_ID" "$(display_host "${SELF_HOST:-unknown}")" \
        "$TOTAL" "$REPLIED" "$SCRAPED" "$SILENT" "$SKIPPED" "$UNREACHABLE"

    printf '## Needs you\n\n'
    if [[ -s "$WORK/needs-you.md" ]]; then cat "$WORK/needs-you.md"; else printf 'Nothing reported as blocked on you.\n'; fi
    printf '\n'

    printf '## Roster\n\n'
    printf '| Agent | Host | Mode | AC status | State | Headline |\n'
    printf '|---|---|---|---|---|---|\n'
    cat "$WORK/table.md"
    printf '\n'

    if [[ -s "$WORK/not-reached.md" ]]; then
        printf '## Not reached\n\n'
        cat "$WORK/not-reached.md"
        printf '\n'
    fi

    if [[ -s "$WORK/reports.md" ]]; then
        printf '## Reports\n\n'
        cat "$WORK/reports.md"
    fi
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
