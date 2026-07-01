# system-dev-pipeline — shared conventions

The stage skills stay lean by pointing here for the cross-cutting rules. The
orchestrator (`system-dev`) enforces these; stage skills follow them.

## Manifest / spine schema

Every artifact and work item is a manifest entry (markdown table or list under the
run root's `manifest.md`):

`id` · `type` (epic|task|spike|scenario) · `status` · `priority` · `milestone` ·
`path` (the artifact file) · `deps` {`blocks`, `parent`, `relates`, `supersedes`,
`discovered-from`, `informs`, `satisfies`} · `design` · `acceptance`.

**ID scheme (orchestrator assigns; stage skills propose):** `REQ-*` (product-spec
requirements), `SCN-*` (test-spec E2E scenarios), component ids + `IFC-*`
(interfaces), detailed-design ids, task ids. Cross-level links:
`REQ → SCN`, `REQ → component/IFC → component-detailed-design → impl-task`.

## Refit bookkeeping (every stage, on any revision)

1. Write the new artifact to its **canonical path**; record that `path` on the entry.
2. On a **refit**, move the prior version to `history/<artifact>@<rev>.md` and add a
   `supersedes` link to it. Never overwrite silently. `<rev>` is a monotonic
   counter / timestamp supplied at run time (not derived inside the workflow).
3. `prototypes/`, `decision-matrix/`, `signoffs/`, `history/` are **append-only**.
4. After a refit, run the **spine-resync**: update affected links + `blocks` edges
   so `ready` order and the back-test re-gate correctly.

## Gates are the orchestrator's job

Stage skills **do not self-gate**. A stage produces its artifact, records `path`
+ spine links, then **hands the gate back to the orchestrator**, which publishes
the artifact, runs the paired **critic** (below) to a verdict, and — for arch/spec
and milestone gates — waits for human signoff (recorded under `signoffs/`). Only
`adversarial-plan` gates natively; the orchestrator wraps the rest.

## Proportionality

Be proportionate to the task. A small task collapses stages (e.g.
clarify-product+spec in one step, a minimal component detailed design, skip
milestone-slicing) and uses a single `csc:grill` critic pass instead of the
multi-agent variant. The full pipeline + cross-model critics are for genuine
multi-component systems.

## Planning cost / risk-triage (adversarial-plan vs writing-plans)

Reserve **`adversarial-plan`** (expensive, ~15–25 CLI calls + a gate) for (a) the
architecture-hardening critique and (b) the plan portion of a component that is
**high-risk / novel / cross-cutting** — i.e. any of: touches ≥2 components'
interfaces; no prior art / unproven approach; a hard perf/reliability/security
bar; or a prototype flagged it uncertain. Otherwise use single-agent
**`writing-plans`**. The **component detailed design** itself always originates
from `technical-design-doc`.

## Critics (the quality-gate engine)

**Principle: every authored artifact has a paired critic.** A gate is not passed
on "LGTM" — the orchestrator runs the artifact's critic to a **verdict** first.

**Engine (one pattern, forked per artifact):**
1. Run the paired critic independently against the artifact + its inputs.
2. Findings are **severity-graded** using the reusable vocabulary in
   `~/.claude/skills/adversarial-diff-review/references/severity-rubric.md`
   (**HIGH / MED / LOW × confidence 0-100**; cross-critic agreement boosts
   confidence). Fork it per artifact via a `severity_rubric_path` if you want
   artifact-specific anchors.
3. The critic emits a **VERDICT: APPROVE | NEEDS-REVISION** with the graded
   findings and (ideally) paste-ready fixes.
4. **APPROVE** → the artifact clears its gate (plus human signoff at arch/spec/
   milestone). **NEEDS-REVISION** → the findings become feedback-loop discoveries,
   triaged to the lowest tier and refit; re-critique after the refit.
5. **Stakes dial:** routine artifact → a single `csc:grill` pass; high-stakes
   (spec, ERD) → the cross-model / multi-agent variant.

**Per-artifact critic map** (installed default → install-worthy upgrade):

| Artifact | Default critic (installed) | Upgrade |
|---|---|---|
| MVP description | `csc:grill` | `cold-read-review` |
| Product Spec | `csc:grill` + `devils-advocate`* | `prd-quality-check` |
| Test Spec (E2E scenarios) | **`test-spec-critic`** (`references/stages/test-spec-critic.md`) + `csc:grill` | — |
| ERD / architecture | `10x-engineer:design-review` (+ `adversarial-plan` critique, high-stakes) | `plan-review` / `design-doc-reviewer` |
| Component detailed design (+plan) | `adversarial-plan` (high-risk plan) / `csc:grill` (routine) | `adversarial-review` / `plan-critic` |
| Implementation | `review-code` / `paladin` / `adversarial-diff-review` + `product-architect-reviewer` PASS/ADJUST/FAIL | — |
| Any doc — internal consistency | `csc:grill` | `devils-advocate` |

\* `devils-advocate`, `prd-quality-check`, `plan-review`, `design-doc-reviewer`,
`adversarial-review`, `cold-read-review`, `plan-critic` are **marketplace skills
not yet installed** — see `docs/critics-survey.md`. Until installed, the installed
defaults apply.

Rubric shape for a forked critic (from `surreal-review` / `debrief:skill-evaluator`):
a short **done-bar checklist** per artifact → per-item ✅/🟡/❌ → severity-graded
findings → ranked paste-ready fixes → a mandatory **strengths** note → VERDICT.
