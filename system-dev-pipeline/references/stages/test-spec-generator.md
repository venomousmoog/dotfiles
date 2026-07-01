---
name: test-spec-generator
description: >-
  Derive a Test Specification — E2E integration validation scenarios — from a
  Product Spec (not from the code), so the build can be back-tested and each
  milestone gated on passing scenarios. Stage 3t of the system-dev pipeline. Use
  after the product spec exists to "write the validation scenarios", "define the
  E2E acceptance tests", or when a spec-tier refit requires re-deriving affected
  scenarios. Maps each scenario (SCN-*) to the requirements it validates.
---

# test-spec-generator

Produce the **Test Specification** from the Product Spec — the validation
contract, fixed early, that **back-tests the final implementation** and gates
each milestone. Writing it from the spec (not the code) is what makes it a
contract rather than a rationalization of whatever got built.

## Produce the scenarios

Write `runs/<slug>/test-spec.md`: a set of **E2E integration validation
scenarios** — user-visible behaviors and cross-component flows that must hold for
the product to be "done." For each scenario:

- a stable **`SCN-*` id**;
- the **user-visible behavior / cross-component flow** it exercises (end to end);
- concrete **setup → action → expected outcome** (executable as an integration check);
- **`satisfies`** links to the `REQ-*` it validates;
- the **milestone** whose slice first makes it go green.

Prefer real integration scenarios over unit-level checks — the point is to prove
the product works across components, which introspection can't.

## Use in the loop

- **Milestone gate:** a milestone closes only when its `SCN-*` pass (the
  orchestrator's back-test). A failing scenario is a first-class,
  dependency-gating discovery.
- **Spec-tier refit:** when `product-manager` changes a requirement, re-derive
  only the affected `SCN-*` and re-gate.

Record scenarios on the manifest as `scenario` entries with their `path` and
`satisfies` links. See the design doc's "Test specification" section.
