# system-dev-pipeline

A plugin that takes a **vague idea to a built system** through a chain of named, gated, durable **markdown** artifacts, run as a **workflow** with a **3-tier feedback/escalation loop**.

**Design of record:** `docs/design.md` (+ `docs/design-review-1.md`). Work log: `docs/log.md`. Skill review: `docs/skill-review-1.md`; critic survey: `docs/critics-survey.md`. Read the design doc first — it is the source of truth for the pipeline, the stage gates, the feedback loop, the run layout, and the substrate decision (markdown; beads deferred).

## The pipeline (stages)

```
concept → MVP description → product spec → test spec (E2E scenarios) → ERD/system architecture
        → component detailed designs (design + impl plan) → implementation
```

Each stage emits a durable artifact and passes a **signoff gate**. A **milestone** loop fans out over components; the **Test Spec** back-tests each milestone. Discoveries during implementation are triaged to the lowest tier (within-component = autonomous; architecture / spec = human-gated) and re-enter the workflow there.

## Skills & stages (single-entry design)

**One registered skill** — the only thing in ambient context: **`build-it`** — sets up and runs the whole pipeline (`/build-it`) and manages session execution. Everything else loads **on demand** from `references/stages/` and is *not* a separate skill, so the pipeline stays invisible until the user invokes `build-it`.

| Loaded on demand | Stage / role |
|---|---|
| `references/stages/clarify-product.md` | Stage 1: idea → MVP description + product-spec inputs |
| `references/stages/product-manager.md` | Stage 2: author the Product Spec; review spec changes |
| `references/stages/milestone-slicing.md` | derive delivery milestones from the product spec |
| `references/stages/test-spec-generator.md` | Stage 3t: E2E validation scenarios from the product spec |
| `references/stages/product-architect.md` | Stage 3: ERD / system architecture |
| `references/stages/prototype-runner.md` | spikes — evidence, any point |
| `references/stages/component-detailed-design.md` | Stage 4: per-component design + implementation plan |
| `references/stages/product-architect-reviewer.md` | Stage 5: dispatch implementers, review, adjust |
| `references/stages/test-spec-critic.md` | Test Spec quality gate (critic) |
| `agents/implementer.md`, `agents/reviewer.md` | context-free implementer / reviewer personas |

**Reused external skills** (installed separately — see Dependencies): `adversarial-plan`, `technical-design-doc`, `lightweight-design-doc`, `writing-plans`, `decision-matrix`, `10x-engineer:brainstorming`, `10x-engineer:design-review`, `csc:grill`, `adversarial-diff-review`, `review-code`/`paladin`.

## Substrate

Durable state is a **markdown work log + linked manifest** under a per-product run root (`runs/<product-slug>/…`), with `history/` for superseded versions. See the design doc's "Work substrate" and "Artifact paths" sections. (A graph tracker like beads is deferred, not chosen.)

## Critics (quality gates)

Every authored artifact has a **paired critic** — a gate passes on a critic **verdict**, not "LGTM". Engine + per-artifact critic map: `references/conventions.md` (§ Critics). Survey of existing critics + install candidates: `docs/critics-survey.md`. Only the Test Spec lacked an existing critic, so this plugin ships **`test-spec-critic`**; other artifacts reuse installed critics (`csc:grill`, `10x-engineer:design-review`, `adversarial-plan`, `review-code`/`paladin`, …).

## Conventions

`references/conventions.md` holds the cross-cutting rules the stage skills defer to: manifest schema + ID scheme, refit bookkeeping (`path`/`history`/`supersedes`), gate hand-back, proportionality, planning risk-triage, and the critic engine. `references/testing-methodology.md` holds **how requirements are validated** (prefer full E2E, avoid mocks, cover negative/boundary cases) — the Test Spec is built from each requirement's `validation` section via it.

## Dependencies & setup

This plugin **composes existing skills** — it does not vendor them. After installing/enabling the plugin, ensure its dependencies are installed. The **SessionStart hook runs `scripts/check-deps.sh`** automatically and warns about anything missing; run it manually with `bash scripts/check-deps.sh`.

**Required:** `10x-engineer:brainstorming`, `10x-engineer:design-review`, `csc:grill`, `decision-matrix`, `writing-plans`, `technical-design-doc`, `lightweight-design-doc`, `adversarial-plan`, `adversarial-diff-review`, `review-code` (or `paladin`).
**Optional — critic upgrades:** `adversarial-review`, `plan-review`, `design-doc-reviewer`, `devils-advocate`, `prd-quality-check`, `cold-read-review`, `plan-critic`.

Install a missing standalone skill with `claude-templates skill <name> install`; plugin-provided skills (brainstorming/design-review/grill/review-code) come with their plugin.

## Status

Source of truth lives here in `~/src/dotfiles/system-dev-pipeline/` (git-tracked, durable — dotsync2 does not manage it). First-draft; R1 review P0/P1 addressed. **Single-entry**: 1 registered skill (`build-it`) + 9 stage reference docs + shared `references/conventions.md` + `scripts/check-deps.sh`. Not yet installed into `~/.claude` (later: register as a marketplace + enable). Skills still want the skill-creator eval loop; see `docs/log.md`.
