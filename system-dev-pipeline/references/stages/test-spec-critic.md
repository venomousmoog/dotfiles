---
name: test-spec-critic
description: >-
  Critic for a Test Specification — judge whether it is exactly the set of
  validation conditions for each requirement, following the testing methodology,
  and return severity-graded findings + a verdict. The quality gate paired with
  Stage 3t of the system-dev pipeline. Checks REQ.validation↔SCN coverage (every
  requirement's `validation` proven; no orphan / scope-creep conditions),
  adherence to the testing methodology (genuine full E2E, no unjustified mocks,
  negative + boundary cases), concrete executable pass/kill conditions, and
  milestone mapping. Use to "review/critique the test spec", "check validation
  coverage", or when the orchestrator runs the Stage 3t gate. Judges the
  validation contract, not test implementations.
---

# test-spec-critic

Judge a **Test Specification** (E2E integration validation scenarios, `SCN-*`)
against the **Product Spec** it must validate, and return a severity-graded
verdict. This is the quality gate for Stage 3t — the one artifact the survey found
no existing critic for. Follow the critic engine + severity vocabulary in
[`../../references/conventions.md`](../../references/conventions.md) (§ Critics), and
judge scenarios against the shared [`../testing-methodology.md`](../testing-methodology.md).

## Inputs

- Test Spec: `runs/<slug>/test-spec.md` (the `SCN-*` validation conditions)
- Product Spec: `runs/<slug>/product-spec.md` (the `REQ-*` with description/justification/**validation**, and milestones)
- Testing methodology: `../testing-methodology.md` (the rules each `SCN-*` must follow)

## Done-bar checklist (score each ✅ / 🟡 / ❌ with evidence)

1. **Coverage of every requirement's `validation`** — each `REQ-*`'s `validation`
   intent is proven by **≥1 `SCN-*`**. List any requirement whose `validation` is
   unproven (a HIGH gap).
2. **No orphans / no scope-creep** — every `SCN-*` `satisfies` exactly one `REQ-*`;
   the Test Spec is the *union of per-requirement conditions* and nothing more.
   Flag any condition testing something no requirement covers (that's a spec-tier
   gap for `product-manager`, not a scenario to keep).
3. **Methodology adherence** (per `../testing-methodology.md`) — genuine **full
   E2E**, not a unit/function proxy; **no mocks** unless a real dependency is truly
   unavailable *and* the mock is flagged; the subject under test is never mocked.
4. **Negative & boundary coverage** — failure modes, malformed/empty/oversized
   input, permission denials, and stated **non-goals** are validated, not just the
   happy path.
5. **Concrete, executable, deterministic** — each `SCN-*` has **setup → action →
   expected** + a **pass/kill condition** that runs and yields an observable
   verdict (no vague "works correctly"); repeatable.
6. **Milestone mapping** — each `SCN-*` names the **milestone** whose slice first
   makes it go green; the **MVP milestone's** conditions prove the primary infra.
7. **From-spec-not-code** — conditions trace to `REQ.validation`, not to an
   implementation (no rationalizing a built thing).

## Output (the engine)

- **Findings**, each **severity-graded** (HIGH/MED/LOW × confidence 0-100 per the
  shared `severity-rubric.md`) with a quoted evidence line and a **paste-ready fix**
  (e.g. the missing scenario stub for an uncovered `REQ-*`).
- A **coverage line**: `N REQ-* total · M covered · K uncovered (list)`.
- A **mandatory Strengths** note (what's already solid).
- **VERDICT: APPROVE | NEEDS-REVISION.** NEEDS-REVISION when any HIGH finding
  stands (e.g. an uncovered requirement, a non-E2E "E2E" scenario, a missing
  kill criterion). On NEEDS-REVISION the findings go back to `test-spec-generator`
  (spec-derived scenarios) or, if a requirement itself is untestable, up to
  `product-manager` as a spec-tier discovery.

Stakes dial: a routine test spec gets a single pass; a high-stakes one can be
run cross-model (a second critic) with confidence-boosting on agreement.
