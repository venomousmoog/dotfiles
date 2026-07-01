---
name: test-spec-critic
description: >-
  Critic for a Test Specification — judge its E2E integration validation
  scenarios against the Product Spec and return severity-graded findings + a
  verdict. The quality gate paired with Stage 3t of the system-dev pipeline.
  Checks REQ↔SCN coverage, whether scenarios are genuinely end-to-end/integration
  (not unit), concrete acceptance/kill criteria, milestone mapping, and that
  scenarios derive from the spec (not from the code). Use to "review/critique the
  test spec", "check scenario coverage", "is this test spec good enough to gate on",
  or when the orchestrator runs the Stage 3t gate. Not a code-test reviewer — it
  judges the validation contract, not test implementations.
---

# test-spec-critic

Judge a **Test Specification** (E2E integration validation scenarios, `SCN-*`)
against the **Product Spec** it must validate, and return a severity-graded
verdict. This is the quality gate for Stage 3t — the one artifact the survey found
no existing critic for. Follow the critic engine + severity vocabulary in
[`../../references/conventions.md`](../../references/conventions.md) (§ Critics).

## Inputs

- Test Spec: `runs/<slug>/test-spec.md` (the `SCN-*` scenarios)
- Product Spec: `runs/<slug>/product-spec.md` (the `REQ-*` and milestones)

## Done-bar checklist (score each ✅ / 🟡 / ❌ with evidence)

1. **Coverage** — every `REQ-*` is validated by **≥1 `SCN-*`**. List any requirement
   with no scenario (a HIGH gap) and any scenario with no `satisfies` → `REQ-*`.
2. **Genuinely E2E / integration** — each scenario exercises a **user-visible
   behavior or cross-component flow end-to-end**, not a unit/function-level check.
   Flag scenarios that are really unit tests in disguise.
3. **Concrete & checkable** — each scenario has **setup → action → expected**
   specific enough to execute, and a clear **pass/kill condition** (its
   `--acceptance`). Flag vague "works correctly" outcomes.
4. **Milestone mapping** — each `SCN-*` names the **milestone** whose slice first
   makes it go green; the **MVP milestone's** scenarios actually prove the primary
   infrastructure (the walking-skeleton claim).
5. **From-spec-not-code** — scenarios trace to the spec's requirements/behaviors,
   not to an implementation. Flag anything that reads like a rationalization of a
   built thing.
6. **Boundaries & failure modes** — critical user journeys, key failure/error
   paths, and stated **non-goals** (things that must NOT happen) are covered.
7. **No redundancy / right grain** — scenarios aren't duplicative; each earns its
   place (proportionality).

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
