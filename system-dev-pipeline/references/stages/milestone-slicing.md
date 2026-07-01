---
name: milestone-slicing
description: >-
  Derive the ordered delivery milestones from a Product Spec — vertical slices
  that each exercise the product end-to-end and prove primary infrastructure,
  MVP first. Part of the system-dev pipeline (Stage 2 companion). Use after the
  product spec exists to "break this into milestones", "define the MVP and the
  delivery increments", or "what's the milestone plan". Distinct from component
  decomposition (that's the ERD's job) — this is the delivery axis.
---

# milestone-slicing

Turn the Product Spec into an **ordered list of milestones** — the delivery axis
(orthogonal to component decomposition). A milestone is a **vertical slice** that
exercises the product E2E and proves out the primary infra, not a horizontal
layer.

## Rules

- **Milestone 1 = MVP / walking skeleton:** a compelling feature set *and* the
  major components stood up enough to be iterated in isolation afterward. It
  exercises the cross-cutting interfaces end-to-end so interface-invalidating
  discoveries surface early (when a re-architect is cheap).
- Each later milestone is an independently buildable, **validatable** increment. At
  this stage it carries **provisional acceptance intents**; these bind to Test-Spec
  `SCN-*` once the Test Spec is generated (Stage 3t) via a spine-resync — `SCN-*`
  don't exist yet at this stage.
- Order by value + de-risking: put the scariest cross-cutting proof first.
- Keep the set small; milestones are learning checkpoints, not a Gantt chart.

## Output

An ordered milestone list folded into `product-spec.md` (and onto the manifest as
`milestone` labels), each milestone naming: its goal, the components/slice it
touches, the `REQ-*` it advances, and provisional acceptance intents (bound to
`SCN-*` after the Test Spec, Stage 3t). This feeds the orchestrator's
per-milestone workflow loop. See the design doc's "two orthogonal axes" and
"execution workflow" sections.
