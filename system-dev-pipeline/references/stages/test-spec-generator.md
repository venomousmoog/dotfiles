---
name: test-spec-generator
description: >-
  Assemble the Test Specification — the set of executable **validation conditions
  for each requirement** — from the Product Spec's per-requirement `validation`
  sections, applying the shared testing methodology (prefer full E2E, avoid mocks,
  cover negatives). Stage 3t of the system-dev pipeline. Use after the product spec
  exists to "build the test spec", "turn the requirements' validation into
  executable conditions", or when `product-manager` flags a spec change and the
  affected conditions must be re-derived. Each condition (SCN-*) satisfies a REQ-*.
---

# test-spec-generator

The **Test Specification is exactly the set of validation conditions for each
requirement** — nothing more, nothing less. You build it from the Product Spec's
per-requirement `validation` sections (not from the code), which is what makes it a
contract rather than a rationalization of whatever got built. It **back-tests the
final implementation** and gates each milestone.

## Assemble the validation conditions

Write `runs/<slug>/test-spec.md`. **For each `REQ-*`**, take its `validation`
intent and apply **`../testing-methodology.md`** to turn it into one or more
executable **validation conditions** (`SCN-*`). Each condition has:

- a stable **`SCN-*` id**;
- **`satisfies` → the `REQ-*`** it proves (every SCN traces to exactly one
  requirement's `validation`; no orphan conditions, no requirement left uncovered);
- the **kind** (behavioral E2E / integration / performance-reliability / negative — per the methodology);
- concrete **setup → action → expected** + a **pass/kill condition**, executable
  and deterministic — real end-to-end path, **no mocks** unless a real dependency
  is genuinely unavailable (then flag it);
- the **milestone** whose slice first makes it go green.

Cover the negative and boundary cases the methodology calls for (failure modes,
bad input, permission denials, non-goals), not just the happy path. Do **not**
invent conditions beyond the requirements' `validation` — the Test Spec is the
union of the per-requirement conditions, so if something needs testing that no
requirement covers, that's a **spec-tier gap** to raise with `product-manager`,
not a scenario to add here.

## Use in the loop

- **Milestone gate:** a milestone closes only when its `SCN-*` pass (the
  orchestrator's back-test). A failing scenario is a first-class,
  dependency-gating discovery.
- **Spec-tier refit:** when `product-manager` changes a requirement, re-derive
  only the affected `SCN-*` and re-gate.

Record scenarios on the manifest as `scenario` entries with their `path` and
`satisfies` links. See the design doc's "Test specification" section.
