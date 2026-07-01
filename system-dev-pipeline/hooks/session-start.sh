#!/usr/bin/env bash
# SessionStart hook for the system-dev-pipeline plugin.
# Surfaces the design-of-record + any active run manifest, and runs the
# dependency check so missing composed skills are flagged at session start.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DIR/.." && pwd)}"

echo "system-dev-pipeline: design=${ROOT}/docs/design.md log=${ROOT}/docs/log.md"

# If a run is active in the current tree, point at its manifest (the spine).
for m in ./runs/*/manifest.md; do
  [ -e "$m" ] && echo "system-dev-pipeline: active run manifest -> $m"
done 2>/dev/null || true

# Dependency check — the pipeline composes existing skills; warn if any is missing.
[ -x "$ROOT/scripts/check-deps.sh" ] && bash "$ROOT/scripts/check-deps.sh" || true

exit 0
