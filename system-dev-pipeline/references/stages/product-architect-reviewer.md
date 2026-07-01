---
name: product-architect-reviewer
description: >-
  Run implementation for a milestone: dispatch context-free implementers per
  component in dependency order, review each result against its detailed
  design/acceptance and the architecture, and adjust downstream when a deviation
  lands. Stage 5 of the system-dev pipeline; split from the product-architect
  monolith's Phases 4–5. Use to "implement this milestone", "dispatch the
  component implementers and review them", or when the orchestrator enters the
  build loop. Reports discoveries as structured facts for the orchestrator to
  triage and gate — it does not own the milestone loop, triage, or the spine
  (those belong to `build-it`).
---

# product-architect-reviewer

Run and review implementation for the current milestone (Stage 5) — the split-out
Phases 4–5 of the old product-architect monolith. Interleave dispatch and review
so adjustments propagate to siblings still in flight.

## Dispatch (dependency-ordered fan-out)

For each component in the milestone slice, in build order (a component starts only
when its deps are ready), dispatch a **context-free implementer** (see
`${CLAUDE_PLUGIN_ROOT}/agents/implementer.md`) with **only** its detailed-design + implementation plan —
no ERD, no other components, no product spec. That isolation is deliberate: the
implementer reports discoveries as facts; the orchestrator (holding the spine)
classifies them.

## Review each result

As each implementer returns (don't wait for the wave), review with `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`:
- **Plan/design compliance** — tasks done, acceptance met.
- **Interface compliance** — exposed `IFC-*` match what consumers expect.
- **Requirement/scenario coverage** — the component's `REQ-*`/`SCN-*` hold.
- **Code quality** — run the team's review (e.g. `/review-code`).
Verdict: **PASS / ADJUST / FAIL**.

## Refits & in-flight adjustment

Report every discovery as a structured fact; the **orchestrator** (which holds the
spine) classifies its tier — this skill does not decide the tier itself.
- When the orchestrator routes a discovery back as **within-component**: adjust
  that component's detailed design/plan and re-dispatch — **autonomous**.
- **Crosses an interface / requirement:** the orchestrator routes it to the
  architecture or spec tier (human-gated). When an arch refit lands, adjust
  sibling/downstream detailed designs, send updated guidance to in-flight
  implementers, and re-review already-completed siblings for compatibility. Hold
  new work until the refit's gate clears.

## Milestone close

Reconcile all components, walk the traceability, and confirm the milestone's
**Test-Spec `SCN-*` scenarios pass** (the back-test) before signoff. See the
design doc's feedback-loop and partial-failure sections.
