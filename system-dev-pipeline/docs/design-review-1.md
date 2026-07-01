VERDICT: NEEDS_REVISION

## Summary Assessment

The artifact-pipeline + 3-tier-feedback architecture is sound and the beads mapping is accurate, but two load-bearing composition claims do not hold as written: `adversarial-plan` emits *plans* (ordered executable steps), not the *architecture docs* and *detailed designs* the pipeline asks of it, and "re-run adversarial-plan on just the affected subsystem" is not supported by how the skill takes input or gates output. The triage loop is under-specified at exactly the points where it must be mechanical, and several partial-failure/in-flight cases are missing.

## Critical Issues (must fix)

### C1. `adversarial-plan` produces *plans*, not *architecture* or *detailed designs* — the central composition claim is mis-stated.

The doc assigns `adversarial-plan` to Stage 2 (architecture: "components, cross-cutting interfaces, dependencies") and Stage 3 (per-component detailed designs). But the actual skill is a *planning* engine, and its prompts explicitly forbid the artifact the pipeline wants:

- `references/planner-prompt.md` line 18-23: "A plan is an ordered set of executable steps... It is NOT a brainstorm, design exploration, or pros/cons survey."
- line 95: "Don't write a design doc. This is a plan, not a treatise."
- Required structure (lines 27-73): `Summary / Approach / Assumptions / Steps / Risks / Open questions` — a step list, not a component/interface/dependency decomposition.

Contrast with `product-architect` Phase 2 (Steps 2.1-2.5), which *does* emit exactly the architecture artifact the doc describes (component specs, interface contracts, tech-decision table, requirements traceability, dependency/wave table). So the doc has the two back-end skills inverted at the architecture layer: the thing that produces architecture is `product-architect`, and `adversarial-plan` produces the per-component *plans* (`product-architect` Phase 3 currently calls single-agent `writing-plans` for that — see Suggestion S1). As written, Stage 2/3 will hand `adversarial-plan` a prompt and get back a flat step list with no component graph, no interface contracts, and no traceability table — which then breaks the traceability spine (C3) and product-architect's review phase, both of which assume a component/interface/requirement structure exists. Either (a) re-assign architecture to product-architect's Phase 2 and use adversarial-plan only for plans, or (b) wrap adversarial-plan's prompt to demand an architecture-shaped output and accept that you are fighting the skill's own prompts.

### C2. "Re-run `adversarial-plan` on just the affected subsystem/interface" is not feasible as the skill is built.

This is the linchpin of the Architecture tier and the doc treats it as a given ("its mdoc signoff = the gate", manifest table). Three concrete obstacles, all verified against the skill:

1. **Input shape.** `adversarial-plan` takes one free-form `{{PROMPT}}` (`planner-prompt.md` line 14-15) and both agents draft *from scratch, independently, with no awareness of each other* (SKILL.md Phase 1, lines 106-107). There is no input slot for "here is the existing architecture, here is the one interface that's wrong, change only that." You would be re-deriving a plan for the subsystem in isolation, not surgically editing the existing arch doc. Re-derivation from scratch is exactly the "expensive and unstable" full re-derivation the doc says the ladder avoids (line 61) — just scoped smaller.
2. **No diff/merge back into the spine.** The skill emits a standalone aligned-plan mdoc (Phase 6-7). Nothing in the skill reconciles that new artifact against the existing architecture doc or updates the traceability links. The doc's "every refit is an auditable, logged edit to the spine" (line 72) has no mechanism behind it for the adversarial-plan path.
3. **Output shape mismatch** (follows from C1): even scoped, the rerun emits a step-list plan, not a revised component/interface spec.

The doc needs to either define a real "refit mode" for adversarial-plan (new input contract: existing-arch + scoped-delta-request; new output contract: a diff against the named components) — which is net-new build, not reuse — or drop the claim and route Architecture-tier refits through product-architect's existing Phase 5.2 adjustment machinery (which *is* designed for "update the architecture document, adjust sibling/downstream plans" — SKILL.md lines 279-294).

### C3. The traceability spine is asserted but not buildable from the composed parts.

The doc's localization story depends on a 4-level link chain: spec requirement → arch component/interface → detailed design → impl task (lines 64-65). But:

- `clarify-task` emits a Goal Brief (`SKILL.md` lines 111-121): Task / Why / Deliverable / Done-when / Depth / Non-goals / open-option-spaces / Context. **It has no "requirements" list with stable IDs and no "milestones."** (See C4.) So level 1 of the spine has no anchor to link from.
- The only traceability that exists in the composed skills is `product-architect`'s Requirements Traceability table (Step 2.4) — product-req → eng-req → component → acceptance. That is 1 hop (req→component), not the 4-level spine, and it is keyed off product-architect's *own* spec, not clarify-task's brief.

The doc acknowledges product-architect "already has a lightweight version" (line 65) but then says "the ladder leans on it much harder" without specifying who builds the missing levels, what the ID scheme is, or how clarify-task's prose brief gets turned into linkable requirement IDs. This is the spine the whole novelty rests on; it needs an explicit schema and a build step, not a lean-on.

### C4. `clarify-task` does not emit milestones — the spec's stated responsibility is unsupported.

The pipeline table (line 29) and line 34 make clarify-task responsible for naming the milestones ("the spec is responsible for naming the milestones"). I read the full skill: clarify-task produces a Goal Brief and a `/goal` completion condition. There is **no milestone concept anywhere** in clarify-task — not in the seven questions, not in the output template, not in the handoff. Milestones (vertical slices, MVP/walking-skeleton) are a core axis of this design (the whole "components × milestones" section), and the skill assigned to produce them has no notion of them. This is either a clarify-task extension that must be specified as build-new work, or milestone identification belongs in a later stage (it arguably belongs at the architecture stage, since slicing vertically requires knowing the components).

### C5. The mdoc gate does not compose across artifacts the way the doc assumes.

The doc reuses "adversarial-plan's mdoc-publish + monitor pattern" as the gate for every stage (line 25, lines 101-102). But that signoff loop is wired *inside* adversarial-plan Phase 7 and is specific to its aligned-plan artifact. Concretely:

- `clarify-task` (Stage 1) has **no mdoc publish/monitor step at all** — it writes `aligned-goal.md` locally and hands off. So Stage 1's "human signoff gate" has no implementation in the reused skill.
- `product-architect` (Stage 4) gates via *user validation in-conversation* (Steps 1.3, 2.6) and auto-review, not mdoc. Its Phase 5 is autonomous review, not a human mdoc gate.
- Only adversarial-plan actually does mdoc+monitor, and on post-publish substantive comments it loops back to *its own* Phase 5 redraft (SKILL.md lines 348-356) — it has no concept of "this comment is actually a spec-tier escalation, hand it up the ladder." So a reviewer comment on the architecture mdoc that really invalidates a *requirement* has nowhere to go in the reused machinery.

The "gates compose across 3+ artifacts" assumption (your question 4) is the issue: today they don't compose; each skill gates differently (or not at all), and only one speaks mdoc. The orchestrator must supply a uniform gating layer — that is build-new, and should be named as such.

### C6. Feedback-loop triage is under-defined at the points that must be mechanical.

The 3-tier table is a good conceptual taxonomy but leaves the implementation-critical questions open, and the doc's own Open Question 4 admits the central one (who classifies). Specifically ambiguous in practice:

- **Who classifies, and when.** Open Q4 leans "autonomous classification + propose, human gate at arch/spec." But the classifier is the implementer subagent, which in `product-architect` is *context-free* (receives ONLY its plan file — SKILL.md Step 4.1 line 236, lines 256-257). A context-free implementer structurally *cannot* tell whether a wrong interface is a local plan fix (Plan tier) or a cross-component contract break (Architecture tier) — it can't see the other components or the spec. So triage must happen at the architect/orchestrator level on the implementer's report, which contradicts "the implementation discovers and triages." This needs to be resolved explicitly.
- **Discoveries that span tiers.** The doc's "what happens when a discovery spans tiers" is unanswered. Example: an interface contract is wrong (Arch) *because* a requirement was infeasible (Spec). The ladder says triage to "the lowest tier that contains them," but a spanning discovery has no single lowest tier. Define: does it escalate to the highest touched tier, or fork into linked refit beads per tier?
- **Spine sync under refit.** "Every refit is an auditable, logged edit to the spine" — but if a Spec-tier refit changes a requirement, every downstream link (arch → design → task) may be stale. The doc never says whether the spine is re-derived, hand-patched, or invalidated-and-rebuilt. `product-architect`'s Adjustments Log (Step 3.3 / 5.2) logs the *change* but does not re-validate the link graph.

### C7. Missing: in-flight implementers when an arch refit lands; partial-failure behavior.

Your question 5, and the doc is silent on all of it:

- **In-flight implementers during a refit.** The whole point of milestone-1 de-risking is that interface-invalidating discoveries surface while siblings are mid-build. `product-architect` Step 5.2 handles the *justified-deviation* case (adjust siblings in flight), but the *human-gated arch refit* case is different: the refit is blocked on human signoff (could be hours/days), and meanwhile implementers are running against the now-known-wrong contract. The doc's beads mapping says the refit bead `blocks` consumers so `bd ready` withholds *future* work — but it does nothing about *already-dispatched* subagents. Need: a pause/abort/quarantine policy for in-flight work when an Architecture-or-Spec refit is opened.
- **adversarial-plan partial failure.** The skill aborts the whole run if a CLI returns empty twice (SKILL.md lines 96-99) and explicitly refuses single-agent fallback. In a pipeline that calls it many times (arch + every milestone's designs + every arch-tier refit), this is a frequent abort surface. The doc has no story for "Stage 3 adversarial-plan aborted mid-pipeline" — does the orchestrator resume, retry, degrade?
- **Milestone-boundary handling** is named as a concern in the prompt but absent from the doc: what marks milestone N done, what triggers JIT design of milestone N+1, what if milestone N's build reveals the milestone *slicing* itself was wrong (a meta-tier the ladder doesn't cover).

### C8. Cost/runtime of running adversarial-plan many times is unbudgeted, and contradicts the YAGNI framing.

Each adversarial-plan run is: 2 parallel drafts + 2 cross-reviews + 2 probe-gen + 2 probe-answer + 2 votes + up to 5 serial redraft round-trips + 2 decision-matrices + 2 mdoc publishes + a human signoff wait (SKILL.md Phases 1-7). That is ~14-24 model CLI invocations *plus a human gate* per run. The pipeline calls it for the architecture, for *each milestone's* detailed designs, and for *every Architecture-tier refit*. A 5-milestone product with a couple of refits is easily 8-10 adversarial-plan runs = ~150+ CLI calls and 8-10 human signoff cycles. The doc's Open Q1 gestures at this ("adversarial for high-stakes, single-agent for routine") but ships no triage rule, and the success criterion "proportionate... small tasks don't get heavyweight pipelines" (line 128) has no enforcing mechanism. This needs an explicit cost-tier rule before build, or the pipeline will be too heavy to dogfood.

## Suggestions (nice to have)

- **S1. Lean harder on `product-architect`, which already is 70% of this.** product-architect already does: spec refinement (Phase 1), architecture decomposition with interface contracts + tech decisions + requirements traceability + wave/build-order (Phase 2), per-component context-free plans (Phase 3), interleaved dispatch + review + downstream adjustment with an Adjustments Log (Phases 4-5). Much of the "build new" orchestrator is reframing product-architect, not writing from scratch. The genuinely-new parts are: the milestone axis, the spec↔arch↔design↔task spine, the explicit 3-tier ladder, and the beads substrate. Framing the build around "extend product-architect" rather than "thin new driver over three peers" would shrink the work and reduce integration seams.

- **S2. The markdown-manifest-as-beads-subset claim is the *cleanest* part of the design — keep it, it checks out.** I verified every mapping in the beads table against `bd` 1.0.5: `--design`/`--acceptance` fields, `--parent`, dep types `blocks|discovered-from|supersedes|relates-to|parent-child`, `bd ready --claim` as the wave scheduler, `bd supersede --with`, `bd doctor --check=conventions` (orphan/drift), `bd prime`, `bd remember`, `bd branch` (Dolt). The manifest schema on line 94 is a faithful strict subset. One caveat: the manifest schema has no field for the *milestone* axis or for the traceability links between artifact levels — both are central to the design but absent from the proposed schema, so it is not yet a complete subset of what the design needs (vs. what beads offers).

- **S3. Resolve Open Q5 (beads server vs embedded) before adp-8, not after.** The dogfood DB is in server mode (a `dolt sql-server` daemon must stay running — confirmed: `.beads/dolt-server.port` present). A "resumable across sessions and teams" orchestrator whose substrate depends on a long-lived local daemon has a resumability hole exactly when sessions are lost (the scenario the design optimizes for). Decide embedded-mode before committing the substrate.

- **S4. Define the milestone-vs-component grid concretely with one worked example.** The "components × milestones" section is the clearest conceptual contribution but stays abstract. One filled-in 3×3 grid (3 components, 3 milestones, showing which cells milestone-1/walking-skeleton touches) would de-risk the whole design and expose whether JIT per-milestone design actually composes with up-front full architecture.

- **S5. State the human-attention budget as a first-class constraint.** With per-stage mdoc gates plus per-arch-refit gates, a single product build could demand 10+ human signoff cycles. That is the real bottleneck, not compute. Consider batching gates (e.g., one signoff for "spec + milestone-1 designs" together) or a lighter approval for low-risk refits.

## Verified Claims (confirmed correct from reading the skills/tooling)

- **beads model maps ~1:1 as the doc claims.** Verified against `bd` 1.0.5: `bd create --design/--acceptance/--parent`, dep `--type blocks|tracks|related|parent-child|discovered-from|until|caused-by|validates|relates-to|supersedes`, `bd ready --claim` (blocker-aware ready-work *is* a wave scheduler), `bd supersede <id> --with <new>` (auto-closes superseded, built for "evolving artifacts/specs"), `bd doctor --check=conventions` (warns on stale/orphaned issues — the "drift signal"), `bd prime`, `bd remember`, `bd branch` (Dolt backend). The escalation-gate mechanic ("refit bead blocks consumers → `bd ready` withholds downstream") is correct for *not-yet-started* work.
- **The `adp` tracking issues exist and match the doc.** `bd list` shows adp-1 (epic), adp-4 (this design, in-progress), adp-5, adp-6, adp-7, adp-8 with the dependencies the phased-build section describes.
- **`adversarial-plan` does emit a signed-off artifact via mdoc + monitor** (Phase 7, lines 297-366) and *does* iterate on post-publish reviewer comments via a capped Phase-5 loop (lines 348-356). The signoff detection (review-status accepted, or approved/lgtm/signoff comment) is real. The gate mechanic exists — it just (a) lives only in this one skill and (b) loops back only within adversarial-plan's own planning, not up the pipeline ladder (see C5).
- **`product-architect` Phases 4-5 do dispatch / review / adjust** as the doc claims (line 102): Step 4.1 dispatches via `subagent-driven-development`, Step 5.1 reviews each implementer immediately (plan compliance, eng-requirements, `/review-code`, arch compliance, verdict PASS/ADJUST/FAIL), Step 5.2 propagates adjustments to siblings-in-flight and downstream + logs them. This is the most accurately-described composition claim in the doc.
- **product-architect has a real (if shallow) traceability table + adjustments log** (Steps 2.4, 3.3, 5.2) — the doc's "lightweight version already exists" is accurate; the gap is depth (1 hop, not 4 levels) and that it's keyed off product-architect's own spec, not clarify-task's brief (C3).
- **The anti-bloat / proportionality concern is genuinely in the source skills' DNA** — clarify-task caps at ~3 questions and warns against over-asking; adversarial-plan's redraft prompts repeatedly enforce "proportional to Depth, cut over-built steps." The design's stated goal of inheriting these lessons is consistent with the skills; it just lacks an enforcing mechanism at the pipeline level (C8).
