---
name: clarify-product
description: >-
  Turn a vague product idea into an MVP description plus the inputs a proper
  product spec needs (users, core capabilities, success metrics, constraints,
  non-goals, MVP seed). The front gate of the system-dev pipeline. Use at the
  start of a product/system build, when the user says "flesh out this idea",
  "what do we need to write the product spec", or hands a one-liner concept for a
  larger build. Distinct from clarify-task (fast task-framing, fewest questions);
  this gathers enough for a product spec without becoming a research project.
---

# clarify-product

The pipeline's front gate. Take a concept and elicit **enough to write a product
spec** — no more. Built on `clarify-task`'s elicitation discipline (ask only
load-bearing gaps, offer defaults to confirm, don't over-ask), but aimed at
product-spec readiness rather than task framing.

## Elicit (only the gaps — offer defaults to react to)

- **Users / audience** — who it's for, primary vs secondary.
- **Core capabilities** — the handful of things it must do.
- **Why now / underlying goal** — so the build optimizes globally.
- **Success metrics** — how we'll know it works (measurable where possible).
- **Constraints** — technical, org, timeline, dependencies.
- **Non-goals** — explicitly out of scope, with a concrete wrong-outcome example.
- **MVP seed** — the smallest compelling slice that proves the primary infra.

Ask in one batched round; prefer a stated default the user can correct over an
open question; stop at "enough to write the spec" — the `product-manager` skill
formalizes it. If framing needs real investigation, that's a signal to fire a
`prototype-runner` spike, not to keep asking.

## Output

1. **MVP Description** → `runs/<slug>/mvp-description.md` — the compelling minimal
   slice + the major components it stands up for later isolated iteration.
2. **Product-spec inputs** — the elicited material above, structured for
   `product-manager` to formalize into the Product Spec.

Record both on the manifest with their `path`. See the design doc's
"clarify-product" section for the rationale.
