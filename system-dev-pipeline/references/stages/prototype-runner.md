---
name: prototype-runner
description: >-
  Run a prototype/spike — isolate and test one load-bearing design claim with
  real numbers, real code, and executing tests (performance, reliability,
  feasibility, complexity) — answering questions introspection on code cannot.
  Part of the system-dev pipeline, usable at any point. Use up front to explore
  options and find the MVP, or on demand before an expensive refit whose
  direction hinges on an unclear claim ("will this meet latency", "is this
  dependency reliable", "how complex is X"). Feeds the decision-matrix or a refit.
---

# prototype-runner (spikes)

Settle an **unclear, load-bearing design claim with evidence** — real numbers,
real code, executed tests — not introspection. A prototype answers
**performance** (benchmark), **reliability** (inject failures), **feasibility**
(does it even work?), and **complexity** (how much code / how hard, measured)
questions. Deliverable = **evidence + a verdict**, not shippable code.

## Discipline (so it stays cheap)

- **Question-first:** name the exact claim and its **success / kill criteria** up
  front. A spike with no kill criterion is a side project.
- **Time-boxed:** it's an investigation, not production. Only spike genuinely
  unclear, load-bearing claims — don't spike the obvious.
- **Throwaway by default:** the *evidence* persists; the *code* usually doesn't.
  A clean prototype may graduate into the milestone-1 walking-skeleton seed, but
  "prototype quietly becomes prod" is an anti-goal.
- **Feeds a decision or a refit:** the verdict lands in a `decision-matrix` cell,
  an architecture choice, or a tier refit.

## Two entry points

1. **Up front (Exploration & Prototyping):** prototype the riskiest/most-uncertain
   options to *find the MVP* — surface options you hadn't considered, **kill
   non-viable ones**, and feed `decision-matrix` measured values instead of
   speculation.
2. **On demand (feedback loop's evidence arm):** before an expensive arch/spec
   refit, prototype first, then refit on the numbers.

## Output

`runs/<slug>/prototypes/<spike-id>.md` — the claim, kill criteria, method,
**measured evidence**, and **verdict** — as a `spike` manifest entry linked
(`informs`) to the decision/design it feeds and (`discovered-from`) to any
discovery that spawned it. Append-only. See the design doc's "Prototyping" section.
