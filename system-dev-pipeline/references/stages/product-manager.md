---
name: product-manager
description: >-
  Author the Product Spec from clarify-product's output, and review/own
  product-spec changes (the spec tier of the system-dev feedback loop). Stage 2
  of the pipeline; split from product-architect Phase 1. Use to "write the
  product spec", "formalize the MVP into a spec", or when a spec-tier refit needs
  the spec revised (requirement infeasible, need shifted, a non-goal turns out
  load-bearing). Owns the REQ-* requirements on the traceability spine.
---

# product-manager

Author and own the **Product Spec** — the durable contract the rest of the
pipeline builds against. (Stage 2; the spec-tier owner in the feedback loop.)

## Write the spec

From the `clarify-product` output, produce `runs/<slug>/product-spec.md`:

```
## Product Spec: <name>
Purpose:            <one sentence>
Users:              <primary / secondary>
Success metrics:    <measurable>
Constraints:        <technical / org / timeline>
Non-goals:          <out of scope> (wrong outcome would be: <example>)
Milestones:         <derived by milestone-slicing; MVP first>
Context:            <repos, prior art, dependencies>

### Requirements
REQ-<id> — each with THREE sections:
  - description:   what it must do
  - justification: why it matters (the underlying need / value)
  - validation:    the condition(s) that prove it is met
```

Give every requirement a stable **`REQ-*` id** with **description / justification /
validation**. These anchor the traceability spine (REQ → SCN validation conditions
→ components → detailed designs → tasks). The **`validation`** section is the seed
the Test Spec is built from: `test-spec-generator` turns each requirement's
`validation` into executable `SCN-*` conditions by applying
`references/testing-methodology.md` (prefer full E2E, avoid mocks, cover negatives).
Write `validation` as the *intent* ("must be provably true that …"), not the test
mechanics — the methodology + test-spec-generator handle the how.

## Review spec changes (spec-tier refits)

When the orchestrator routes a spec-tier discovery here: revise only the affected
slice of the spec, keep `REQ-*` ids stable where the requirement is unchanged,
add/supersede where it changed, and flag the affected `SCN-*` scenarios so
`test-spec-generator` re-derives them. Then re-gate (human signoff) and merge.

Hand off to `milestone-slicing` (milestones), `test-spec-generator` (scenarios),
and `product-architect` (ERD). See the design doc for the gate + spine detail.
