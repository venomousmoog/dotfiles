---
name: component-detailed-design
description: >-
  Produce a component's detailed design AND its implementation plan as one
  artifact, straight from the ERD's component scoping — JIT for the current
  milestone. Stage 4 of the system-dev pipeline. Use to "detail-design this
  component", "turn the architecture into a buildable plan for component X", or
  when the orchestrator fans out designs for a milestone. Originates from
  technical-design-doc (full TDD, with the plan folded in); adversarial-plan or
  writing-plans supplies the plan portion; lightweight-design-doc derives a
  review summary. Not a separate design-then-plan step — one combined artifact.
---

# component-detailed-design

Produce the **Component Detailed Design** — design *and* implementation plan in
one artifact — for a single component, scoped to the **current milestone** (JIT,
YAGNI). The ERD carries enough scoping to jump straight here from the component's
high-level requirements; there is no separate design-then-plan step.

## Produce it

Write `runs/<slug>/milestones/<m>/components/<component>/detailed-design.md`:

- **Design** — internal structure, the interfaces it implements (`IFC-*` from the
  ERD), data/state it owns, key decisions. **Originated by `technical-design-doc`**
  (the full TDD) — this is the sole originator; `lightweight-design-doc` does not
  originate, it only derives a review summary (below).
- **Implementation plan** — the executable steps to build the milestone's slice
  of this component, with acceptance tied to the relevant `SCN-*`/`REQ-*`.
  - **High-risk / novel / cross-cutting** component → use `adversarial-plan` for
    the plan portion.
  - **Routine** component → use single-agent `writing-plans`.

Keep it milestone-scoped: only what this milestone needs.

## Derived review artifact

Run `lightweight-design-doc` over the detailed design to produce
`…/review-summary.md` — a condensed summary for tech-lead review (artifact `5r`).
It is derived, never the originator.

## Record

Manifest entry per component (epic → subtasks), with `--design`/`--acceptance`
content, `path`, and `satisfies`/`implements` links up to `REQ-*`/`IFC-*`. Hands
off to `product-architect-reviewer` (Stage 5). See the design doc's
"component detailed design" and cost/proportionality sections.
