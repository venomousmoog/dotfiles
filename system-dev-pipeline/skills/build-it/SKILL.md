---
name: build-it
description: >-
  Set up and run the full build workflow for a task and manage its session
  execution end to end — turn an idea into a built system through a gated artifact
  pipeline (concept → MVP description → product spec → test spec → ERD → component
  detailed designs → implementation) run as a per-milestone workflow with a 3-tier
  feedback/escalation loop and a per-artifact critic at every gate. Use whenever
  the user wants to build a multi-component product or system from a description,
  says "build it", "run the build pipeline", "set up the workflow for this task",
  "take this idea to implementation / end to end", or invokes /build-it. This is
  the **single entry point** for the whole pipeline — each stage's instructions are
  loaded on demand from references/stages/ (they are not separate skills), so
  nothing else sits in ambient context. For a single small change, use a plan.
---

# build-it (pipeline orchestrator)

You set up the workflow for a task and **manage the whole session's execution**: a
thin, stateless driver over durable markdown artifacts. You run the pipeline
forward through critic-checked signoff gates, fan out over components per
milestone, back-test with the Test Spec, and route implementation discoveries to
the right refit tier. You hold the **traceability spine**; the stage instructions
and implementers are stateless and get only what they need.

**Single entry point.** This is the only registered skill in the plugin. Each
stage's full instructions live at
`${CLAUDE_PLUGIN_ROOT}/references/stages/<stage>.md` and you **load them on demand**
as you reach that stage (Read them, or hand their content to a subagent) — this
keeps ambient context to just this one skill.

**Read first:** the design of record `${CLAUDE_PLUGIN_ROOT}/docs/design.md`
and the shared rules `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` (manifest
schema + ID scheme, refit bookkeeping, gate hand-back, proportionality,
risk-triage, and the **critic engine** + per-artifact critic map).

## Stages (load the reference when you reach it)

| Stage | Reference to load | Produces |
|---|---|---|
| 1. clarify-product | `references/stages/clarify-product.md` | MVP description + product-spec inputs |
| 2. product-manager (+ milestone-slicing) | `references/stages/product-manager.md`, `.../milestone-slicing.md` | Product Spec + milestones |
| 3t. test-spec-generator | `references/stages/test-spec-generator.md` | Test Spec (E2E `SCN-*`) |
| 3. product-architect | `references/stages/product-architect.md` | ERD / system architecture |
| exploration | `references/stages/prototype-runner.md` | spikes (evidence) — any time |
| 4. component-detailed-design | `references/stages/component-detailed-design.md` | per-component design + plan |
| 5. product-architect-reviewer | `references/stages/product-architect-reviewer.md` | dispatch implementers, review, adjust |
| Test-Spec critic | `references/stages/test-spec-critic.md` | the Test Spec's quality gate |

Reused **external** skills (invoked directly, installed separately — see
Dependencies): `10x-engineer:brainstorming`, `10x-engineer:design-review`,
`csc:grill`, `decision-matrix`, `adversarial-plan`, `technical-design-doc`,
`lightweight-design-doc`, `writing-plans`, `adversarial-diff-review`,
`review-code`/`paladin`, and the optional critic upgrades.

## The workflow

1. **Front stages — sequential + gated.** Each stage: load its reference, produce
   the artifact, record `path` + spine links, hand the gate back (run the paired
   **critic** to a verdict; human signoff at arch/spec). Fire `prototype-runner`
   whenever a claim is unclear.
2. **Per milestone (JIT loop):** fan out `component-detailed-design` per component
   (parallel, gated); fan out implementation via `product-architect-reviewer`
   (which dispatches the context-free `agents/implementer.md` + `agents/reviewer.md`
   personas) in dependency order; **back-test** — the milestone's `SCN-*` must pass;
   reconcile + signoff → next milestone.
3. **Feedback loop = re-entry.** You triage each discovery to the lowest tier
   (within-component → autonomous; architecture / spec → human-gated) and re-enter
   the workflow there, scoped to the affected subtree.

## Stage-transition rule

Advance only when the artifact is (a) **produced**, (b) its **paired critic
returns APPROVE** and it is **signed off** at its gate (autonomous within-component;
human for arch/spec/milestone), and (c) its **spine links + `path` are recorded**.
A failed critic/gate — or a failing E2E scenario — does **not** advance; it
triggers a refit. A milestone advances only when all components *and* its E2E
scenarios are green.

## Discipline

- **Critic-gated.** Every gate runs the artifact's paired critic to a
  **VERDICT (APPROVE | NEEDS-REVISION)** before signoff — never a bare "LGTM"
  (critic map + engine in `references/conventions.md`).
- **Proportionate.** Don't run the full pipeline on a small task — collapse stages
  and use a single `csc:grill` pass instead of the multi-agent critic variant.
- **Reserve `adversarial-plan`** for the architecture-hardening critique and the
  plan portion of high-risk/novel/cross-cutting components; `writing-plans` for
  routine; `technical-design-doc` always originates the component detailed design.
- **Never overwrite history.** Refits move the prior artifact to `history/` with a
  `supersedes` link; `prototypes/`, `decision-matrix/`, `signoffs/`, `history/`
  are append-only.
- **Follow `references/conventions.md`** for the manifest schema, refit
  bookkeeping, gate hand-back, and the critic map — the stage references defer to it.
