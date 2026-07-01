#!/usr/bin/env bash
# Dependency check for the system-dev-pipeline plugin.
# The pipeline composes several EXISTING skills (it does not vendor them). This
# reports which required/optional dependency skills are installed so the user can
# install any that are missing. Non-blocking — always exits 0.
#
# Run manually:  bash scripts/check-deps.sh
# Also invoked from hooks/session-start.sh at session start.

roots=(
  "$HOME/.claude/skills"
  "$HOME/.llms/skills/claude-templates"
  "$HOME/.claude/agent-market/skills"
)
shopt -s nullglob
for d in "$HOME"/.claude/agent-market/plugins/*/skills; do roots+=("$d"); done

have() {  # have <skill-basename>  — true if a SKILL.md by that name exists in any root
  local s="$1" r
  for r in "${roots[@]}"; do [ -f "$r/$s/SKILL.md" ] && return 0; done
  return 1
}

# Required — the pipeline actively invokes these (basename = skill dir name).
required=(brainstorming design-review grill decision-matrix writing-plans \
          technical-design-doc lightweight-design-doc adversarial-plan \
          adversarial-diff-review review-code)
# Optional — critic-map upgrades (installed defaults are used until present).
optional=(adversarial-review plan-review design-doc-reviewer devils-advocate \
          prd-quality-check cold-read-review plan-critic)

miss_req=(); for s in "${required[@]}"; do have "$s" || miss_req+=("$s"); done
miss_opt=(); for s in "${optional[@]}"; do have "$s" || miss_opt+=("$s"); done

if [ ${#miss_req[@]} -eq 0 ]; then
  echo "system-dev-pipeline: ✅ all required dependency skills present."
else
  echo "system-dev-pipeline: ⚠ MISSING required skills → $(IFS=' '; echo "${miss_req[*]}")"
  echo "  install with:  claude-templates skill <name> install   (per skill)"
fi
[ ${#miss_opt[@]} -gt 0 ] && \
  echo "system-dev-pipeline: (optional critic upgrades not installed → $(IFS=' '; echo "${miss_opt[*]}"))"
exit 0
