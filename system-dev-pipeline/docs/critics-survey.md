# Critic / critical-feedback survey (2026-07-01)

Goal: every authored artifact in the pipeline should have a paired **critic** (a skill that judges its quality and returns actionable, ideally severity-graded feedback + a verdict). Survey of existing critics — installed + marketplace — so we reuse rather than reinvent. (Two parallel survey agents: installed skills, and the ARK skillbook catalog + claude-templates component library.)

## The reusable "critic engine" (key finding)

Rather than a bespoke critic per artifact, standardize on **one pattern + a forkable rubric per artifact**:
- **Pattern:** independent critic → structured findings → **severity grading** → explicit **VERDICT (approve / needs-revision)** → optional iterate-to-convergence. (This is what `brainstorming`'s review loop, `adversarial-plan`, and `csc:grill` already do.)
- **Grading vocabulary (reuse verbatim):** `adversarial-diff-review/references/severity-rubric.md` — HIGH/MED/LOW × confidence(0-100), **explicitly forkable** via a `severity_rubric_path`. Best single reusable grading language.
- **Per-artifact rubric:** a short "done-bar" checklist per artifact (the `surreal-review` engine — checklist → ✅/🟡/❌ per item → ranked paste-ready fixes → mandatory strengths; or `skill-evaluator`'s weighted `required_present`/`semantic_checks` schema).
- **Stakes dial:** high-stakes artifacts (spec, ERD) → cross-model / multi-agent adversarial variant; routine → a single `csc:grill` pass. This plugs straight into the pipeline: **the critic's verdict is the signoff-gate input; NEEDS-REVISION findings become feedback-loop refit discoveries.**

## Best generic critics already INSTALLED (use now)

| Skill | What it gives | Best for |
|---|---|---|
| **`csc:grill`** | Ruthless coarse→fine adversarial probing of an idea/plan/**document**; one critique/turn; ends with Verdict/Accepted/Open | default generic critic for any authored artifact |
| **`surreal-review`** | Rubric → per-item ✅/🟡/❌ → ranked fixes → strengths; forkable via `calibrate` | the rubric-engine to fork per artifact |
| **`adversarial-plan`** | Two cross-model agents draft→blind cross-review→grill→vote→converge; decision-matrix; mdoc signoff | plan + our architecture-hardening critique (already in the design) |
| **`10x-engineer:design-review`** | 6 parallel expert agents, each must **cite codebase evidence**; risks ranked CRITICAL/HIGH/MED | ERD / architecture validation |
| **`surreal-comms:slide-deck-critic`** | Clarifying-Qs → tiered Critical/Significant/Minor → 5-axis 0-5 scorecard | transplantable tiered-output + scorecard shape |
| **`adversarial-diff-review`** (+ `severity-rubric.md`) | Dual-model diff review; forkable severity vocabulary | implementation + the reusable grading language |
| **`review-code` / `paladin`** | Multi-agent code review | implementation |
| **`debrief:skill-evaluator`** | LLM-as-judge: weighted anchored rubric, verdict, grade | quantitative scoring of an output step |
| **`verification-before-completion`** | Gate: no "done" without fresh evidence | self-check before any gate |

## Strong critics NOT installed (worth installing) — from the catalog survey

> Names/paths from `sb-skill-search` (ARK) + the claude-templates component dir; confirm exact install alias before installing.

| Skill | Focus | Why |
|---|---|---|
| **adversarial-review** `[ct:skills/adversarial-review]` | plan + design-doc + impl | closest match to "judge a plan/spec/design/impl step"; two modes (plan / impl) |
| **plan-review** `[ct:skills/plan-review]` | plan + design | 3 cross-model archetypes (Architect/Practitioner/Skeptic), codebase-grounded, one prioritized verdict |
| **design-doc-reviewer** `[ct:skills/design-doc-reviewer]` | design/doc | Meta bluedoc/greendoc rubric + readiness verdict + can scaffold missing sections |
| **devils-advocate** `[skillbook nb 9938608]` | design/doc + spec | contradiction / cross-doc assumption-conflict / claim-without-mechanism hunter; every finding quoted, no speculation — great for spec+ERD internal consistency |
| **prd-quality-check** `[ct:skills/prd-quality-check]` | product/spec | 6-dimension PRD check w/ Pass/Needs-Work + anti-patterns — closest fit for the **Product Spec** |
| **multi-model-doc-critique** `[skillbook nb 11150800]` | design/doc | 4 models hunt logic gaps/incoherence/complexity; merged report + validation round |
| **plan-critic**, **adversarial-refinement**, **independent-review**, **doc-review-panel**, **metacritic**, **cold-read-review** | plan/doc/generic | secondary options (red-team, iterate-to-convergence, process-isolated reviewer, persona panels, clarity cold-read) |

## Mapping to our pipeline artifacts

| Artifact (stage) | Reuse now (installed) | Install-worthy upgrade | Gap? |
|---|---|---|---|
| MVP description / concept | `csc:grill` | `cold-read-review` (clarity) | ok |
| **Product Spec** | `csc:grill` + `surreal-review` engine | **`prd-quality-check`** + **`devils-advocate`** | mostly covered |
| **Test Spec (E2E scenarios)** | — (weak fit) | — | **GAP — author a test-spec critic** (every REQ→≥1 SCN? scenarios truly E2E/integration? kill-criteria present? milestone-mapped?) |
| **ERD / architecture** | `10x-engineer:design-review` + `adversarial-plan` critique | **`plan-review`** / **`design-doc-reviewer`** / `arch-quality-review` | covered |
| **Component detailed design (+plan)** | `adversarial-plan` (plan portion) | **`adversarial-review`** / `plan-critic` | covered |
| **Implementation** | `review-code` / `paladin` / `adversarial-diff-review` + `product-architect-reviewer` PASS/ADJUST/FAIL | (installed suffices) | covered |
| **Any doc — internal consistency** | `csc:grill` | **`devils-advocate`** | covered |

## Recommendation

1. **Adopt the critic engine as a pipeline convention** (fold into the P2 `conventions.md`): each stage gate = run its paired critic to a **verdict** using the shared severity vocabulary; NEEDS-REVISION → feedback-loop refit; APPROVE → signoff. High-stakes stages use the cross-model/multi-agent variant.
2. **Install 5** to fill doc/spec/design/plan critic slots: `adversarial-review`, `plan-review`, `design-doc-reviewer`, `devils-advocate`, `prd-quality-check` (verify aliases first).
3. **Author 1 gap:** a **test-spec critic** (no good existing fit) — checks REQ↔SCN coverage, true E2E/integration, kill-criteria, milestone mapping.
4. Reuse verbatim: `adversarial-diff-review/references/severity-rubric.md` as the grading language; `surreal-review`/`skill-evaluator` schema as the rubric shape.
