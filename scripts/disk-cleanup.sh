#!/bin/bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Aggressive devserver disk cleanup. Targets the big space hogs:
#   - DotSlash binary cache (~/.cache/dotslash)
#   - dotsync conflict snapshots (~/.dotsync/conflicts)
#   - Stale /tmp PAR unpack dirs from dead PIDs
#   - Eden GC, stale XAR/sandbox mounts, hg/sl backups, etc.
#
# Usage:
#   disk-cleanup.sh              # run cleanup
#   disk-cleanup.sh --dry-run    # show what would be cleaned
#   disk-cleanup.sh --aggressive # also clear caches that take a while to rebuild
#                                # (yarn, ~/.cache/ricardo, ~/.maui/cache)

set -uo pipefail

DRY_RUN=false
AGGRESSIVE=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        --aggressive|-a) AGGRESSIVE=true ;;
        -h|--help)
            sed -n '3,14p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown arg: $arg (use --help)" >&2
            exit 1
            ;;
    esac
done

MY_UID=$(id -u)

# ---- helpers ----------------------------------------------------------------

bytes_free() {
    df --output=avail / 2>/dev/null | tail -1 | tr -d ' '
}

human_size() {
    local p="$1"
    [ -e "$p" ] || { echo "(missing)"; return; }
    du -sh "$p" 2>/dev/null | cut -f1
}

run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        eval "$@"
    fi
}

section() {
    echo ""
    echo "=============================="
    echo "  $1"
    echo "=============================="
}

report_disk() {
    df -h / 2>/dev/null | grep -E 'Filesystem|/dev/'
}

START_FREE=$(bytes_free)

echo "=================================================="
echo "  Devserver Disk Cleanup ($([ $DRY_RUN = true ] && echo "DRY RUN" || echo "LIVE"))"
echo "=================================================="
report_disk

# ---- 1. DotSlash binary cache (often 50-90 GB) ------------------------------
section "DotSlash binary cache  (~/.cache/dotslash)"
DOTSLASH="$HOME/.cache/dotslash"
if [ -d "$DOTSLASH" ]; then
    echo "  Size: $(human_size "$DOTSLASH")  (binaries are re-fetched on demand)"
    run "rm -rf '$DOTSLASH'"
else
    echo "  Not present, skipping."
fi

# ---- 2. dotsync conflict snapshots ------------------------------------------
section "dotsync conflict snapshots  (~/.dotsync/conflicts)"
CONFLICTS="$HOME/.dotsync/conflicts"
if [ -d "$CONFLICTS" ]; then
    COUNT=$(find "$CONFLICTS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    echo "  $COUNT snapshots, $(human_size "$CONFLICTS")"
    # Keep the 5 most recent in case the user is mid-resolution.
    if [ "$COUNT" -gt 5 ]; then
        # shellcheck disable=SC2012
        OLD_DIRS=$(ls -1t "$CONFLICTS" 2>/dev/null | tail -n +6)
        echo "  Removing $(echo "$OLD_DIRS" | wc -l) old snapshots, keeping 5 newest."
        echo "$OLD_DIRS" | while read -r d; do
            [ -n "$d" ] && run "rm -rf '$CONFLICTS/$d'"
        done
    else
        echo "  Only $COUNT snapshots, keeping all."
    fi
else
    echo "  Not present, skipping."
fi

# ---- 3. /tmp PAR unpack dirs from dead PIDs ---------------------------------
section "Stale /tmp PAR unpack dirs"
DEAD_BYTES=0
DEAD_COUNT=0
declare -A SEEN_PIDS
while IFS= read -r path; do
    [ -z "$path" ] && continue
    # par_unpack.<bin>.runtime.<pid>.<hash> — extract the PID
    pid=$(echo "$path" | awk -F. '{print $(NF-1)}')
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if [ -z "${SEEN_PIDS[$pid]:-}" ]; then
        if kill -0 "$pid" 2>/dev/null; then
            SEEN_PIDS[$pid]="alive"
        else
            SEEN_PIDS[$pid]="dead"
        fi
    fi
    if [ "${SEEN_PIDS[$pid]}" = "dead" ]; then
        sz=$(stat -c '%s' "$path" 2>/dev/null || echo 0)
        sz_dir=$(du -sb "$path" 2>/dev/null | awk '{print $1}')
        DEAD_BYTES=$((DEAD_BYTES + ${sz_dir:-$sz}))
        DEAD_COUNT=$((DEAD_COUNT + 1))
        run "rm -rf '$path'"
    fi
done < <(find /tmp -maxdepth 1 -name "par_unpack.*" -user "$USER" 2>/dev/null)
echo "  Removed $DEAD_COUNT dirs from dead PIDs (~$((DEAD_BYTES / 1024 / 1024)) MB)"

# ---- 4. Misc /tmp space hogs ------------------------------------------------
section "/tmp deep clean"
echo "  Before: $(human_size /tmp)"

# Stale segment/buck logs/large standalone files older than 1 day
for pattern in \
    "/tmp/segment*.bin" \
    "/tmp/buck-out-*" \
    "/tmp/buck_*.log" \
    "/tmp/buck_*.out" \
    "/tmp/buck-out.log" \
    "/tmp/aai-*.log" \
    "/tmp/adb.*.log" \
    "/tmp/below.log" \
    "/tmp/hsperfdata_$USER" \
    "/tmp/.com.google.*" \
    "/tmp/rust_*" \
    "/tmp/clangd-*" \
    "/tmp/vscode-*" \
    "/tmp/pyright-*" \
    "/tmp/.cache-*" \
; do
    for f in $pattern; do
        [ -e "$f" ] || continue
        # Only remove if older than 1 day or owner not us is impossible (these patterns are user-owned)
        if [ "$(find "$f" -maxdepth 0 -mtime +1 2>/dev/null)" ]; then
            run "rm -rf '$f'"
        fi
    done
done

# User-owned files in /tmp older than 7 days, excluding active session dirs
find /tmp -maxdepth 1 -user "$USER" -mtime +7 \
    -not -name "eden_redirections" \
    -not -name "claude-*" \
    -not -name "sandbox_*" \
    -not -name "tmux-*" \
    -print 2>/dev/null | while read -r f; do
        run "rm -rf '$f'"
    done

echo "  After:  $(human_size /tmp)"

# ---- 5. Stale XARFuse mounts ------------------------------------------------
section "Stale XARFuse mounts"
XARFUSE="/mnt/xarfuse/uid-${MY_UID}"
if [ -d "$XARFUSE" ]; then
    UNMOUNTED=0
    for mnt in "$XARFUSE"/*/; do
        [ -d "$mnt" ] || continue
        if ! stat "$mnt" &>/dev/null; then
            run "fusermount -uz '$mnt' 2>/dev/null || umount -l '$mnt' 2>/dev/null || true"
            UNMOUNTED=$((UNMOUNTED + 1))
        fi
    done
    echo "  Unmounted $UNMOUNTED stale mounts. Current size: $(human_size "$XARFUSE")"
else
    echo "  No xarfuse dir for uid $MY_UID."
fi

# ---- 6. Stale sandbox dirs --------------------------------------------------
section "Stale /tmp/sandbox_* dirs"
SANDBOX_COUNT=0
for sandbox in /tmp/sandbox_*/; do
    [ -d "$sandbox" ] || continue
    FUSE="$sandbox/fuse_mount"
    # Only act on sandboxes whose fuse_mount is broken (stat fails on stale FUSE).
    if [ -d "$FUSE" ] && ! stat "$FUSE" &>/dev/null; then
        run "fusermount -uz '$FUSE' 2>/dev/null || umount -l '$FUSE' 2>/dev/null || true"
        # After unmount succeeds, fuse_mount is just an empty dir; rm -rf works.
        run "rm -rf '$sandbox' 2>/dev/null"
        SANDBOX_COUNT=$((SANDBOX_COUNT + 1))
    fi
done
echo "  Cleaned $SANDBOX_COUNT stale sandbox dirs."

# ---- 7. Eden doctor + GC ----------------------------------------------------
section "Eden doctor + GC"
if command -v eden &>/dev/null; then
    if $DRY_RUN; then
        echo "  [dry-run] eden doctor (would auto-fix)"
        echo "  [dry-run] eden gc"
    else
        echo ">>> eden doctor (auto-fix)..."
        eden doctor 2>&1 | tail -10
        echo ""
        echo ">>> eden gc..."
        eden gc 2>&1 | tail -5
    fi

    echo ""
    echo ">>> Current Eden checkouts:"
    eden list 2>&1
    echo ""
    echo "  Note: 'eden rm <path>' to drop unused checkouts (biggest single win"
    echo "  if you have stale fbsource-* or src/clown/* clones you no longer need)."
else
    echo "  eden not installed."
fi

# ---- 8. Clown clones --------------------------------------------------------
section "Clown clones (inactive)"
if [ -x "$HOME/src/dotfiles/scripts/clown.sh" ]; then
    if $DRY_RUN; then
        echo "  [dry-run] would run clown.sh --clean"
        ls -d "$HOME"/src/clown/*/ 2>/dev/null || echo "  (no clown clones)"
    else
        "$HOME/src/dotfiles/scripts/clown.sh" --clean 2>&1
    fi
else
    echo "  clown.sh not found, skipping."
fi

# ---- 9. SCM backups + eden logs ---------------------------------------------
section "SCM backups + Eden logs"
if command -v eden &>/dev/null; then
    while IFS= read -r repo_dir; do
        [ -z "$repo_dir" ] && continue
        for backup in strip-backup shelve-backup; do
            d="$repo_dir/.hg/$backup"
            if [ -d "$d" ]; then
                echo "  $(basename "$repo_dir")/$backup: $(human_size "$d")"
                run "rm -rf '$d'"
            fi
        done
    done < <(eden list 2>/dev/null)
fi

EDEN_LOGS="$HOME/.eden/logs"
if [ -d "$EDEN_LOGS" ]; then
    echo "  Eden logs: $(human_size "$EDEN_LOGS")"
    run "find '$EDEN_LOGS' -type f -name '*.log.*' -delete 2>/dev/null"
    run "find '$EDEN_LOGS' -type f -name '*.log' -size +10M -exec truncate -s 0 {} \;"
fi

for hgcache in "$HOME/.hgcache" "$HOME/.cache/sapling"; do
    if [ -d "$hgcache" ]; then
        echo "  $hgcache: $(human_size "$hgcache")"
        run "find '$hgcache' \( -name '*.pack' -o -name '*.idx' \) -mtime +3 -delete"
    fi
done

# ---- 10. Caches -------------------------------------------------------------
section "Caches"
for d in \
    "$HOME/.cache/pip" \
    "$HOME/.cache/buck" \
    "$HOME/.cache/clangd" \
    "$HOME/.cache/pyright" \
    "$HOME/.cache/pylsp" \
    "$HOME/.cache/bazel" \
    "$HOME/.cargo/registry/cache" \
    "$HOME/.npm/_cacache" \
    "$HOME/.local/share/Trash" \
; do
    if [ -d "$d" ]; then
        echo "  $d: $(human_size "$d")"
        run "rm -rf '$d'"
    fi
done

if $AGGRESSIVE; then
    echo ""
    echo "  --aggressive: clearing caches that take longer to rebuild..."
    for d in \
        "$HOME/.cache/yarn" \
        "$HOME/.cache/ricardo" \
        "$HOME/.maui/cache" \
    ; do
        if [ -d "$d" ]; then
            echo "  $d: $(human_size "$d")"
            run "rm -rf '$d'"
        fi
    done
fi

# ---- 11. Core dumps ---------------------------------------------------------
section "Core dumps"
COUNT=$(find /tmp "$HOME" /var/tmp -maxdepth 3 \( -name "core.*" -o -name "*.core" \) -user "$USER" 2>/dev/null | wc -l)
echo "  Standalone core.* / *.core files: $COUNT"
[ "$COUNT" -gt 0 ] && run "find /tmp '$HOME' /var/tmp -maxdepth 3 \\( -name 'core.*' -o -name '*.core' \\) -user '$USER' -delete 2>/dev/null"

# ~/dumps/coredumps_default.* — written by xarexec'd binaries, often gigabytes each.
# Anything older than 30 days is almost certainly post-mortem-irrelevant.
if [ -d "$HOME/dumps" ]; then
    mapfile -t OLD < <(find "$HOME/dumps" -maxdepth 1 -name "coredumps_default.*" -mtime +30 2>/dev/null)
    if [ "${#OLD[@]}" -gt 0 ]; then
        SZ=$(du -sch "${OLD[@]}" 2>/dev/null | tail -1 | cut -f1)
        echo "  Old (>30d) coredumps in ~/dumps: ${#OLD[@]} files, $SZ"
        for f in "${OLD[@]}"; do
            run "rm -f '$f'"
        done
    else
        echo "  No old coredumps in ~/dumps."
    fi
fi

# ---- 12. fbpkg cache --------------------------------------------------------
section "fbpkg cache (~/fbpkgs)"
if [ -d "$HOME/fbpkgs" ]; then
    echo "  Size: $(human_size "$HOME/fbpkgs")  (re-fetched on demand)"
    # Drop fbpkgs older than 14 days.
    OLD=$(find "$HOME/fbpkgs" -mindepth 1 -maxdepth 1 -mtime +14 2>/dev/null)
    if [ -n "$OLD" ]; then
        echo "$OLD" | while read -r p; do
            [ -n "$p" ] && run "rm -rf '$p'"
        done
    else
        echo "  All packages <=14 days old, keeping."
    fi
fi

# ---- summary ----------------------------------------------------------------
section "Summary"
report_disk
END_FREE=$(bytes_free)
RECLAIMED_KB=$((END_FREE - START_FREE))
RECLAIMED_GB=$(awk "BEGIN { printf \"%.1f\", $RECLAIMED_KB / 1024 / 1024 }")
echo ""
if $DRY_RUN; then
    echo "DRY RUN — no changes made. Re-run without --dry-run to actually clean."
else
    echo "Reclaimed: ${RECLAIMED_GB} GB"
fi
echo ""
echo "Sizes of cleanup target dirs after run:"
for d in \
    "$HOME/.cache/dotslash" \
    "$HOME/.dotsync/conflicts" \
    /tmp \
    "$HOME/dumps" \
    "$HOME/fbpkgs" \
    "$HOME/.cache/yarn" \
    "$HOME/.cache/ricardo" \
    "$HOME/.maui/cache" \
; do
    [ -e "$d" ] && printf "  %-30s %s\n" "$(basename "$(dirname "$d")")/$(basename "$d")" "$(human_size "$d")"
done
echo ""
echo "For a full breakdown, run:  du -shx ~/*/ ~/.[a-zA-Z]*/ 2>/dev/null | sort -rh | head"
echo ""
echo "If still tight, the next biggest wins are usually:"
echo "  1. Drop unused Eden checkouts:  eden list ; eden rm <path>"
echo "  2. buck2 clean inside fbsource"
echo "  3. Re-run with --aggressive to also clear yarn / .maui / ricardo caches"
