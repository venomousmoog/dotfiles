---
name: product-architect
description: >-
  Define the ERD / system-architecture document from a Product Spec — components,
  cross-cutting interfaces, dependencies, build order — milestone-set-aware, with
  a requirements-traceability table. Stage 3 of the system-dev pipeline; split
  from the product-architect monolith's Phase 2 (architecture only — it does NOT
  author the product spec or run implementation here). Use to "define the
  architecture / ERD", "decompose into components and interfaces", or when an
  architecture-tier refit needs a subsystem re-planned. Proposes component/IFC-*
  ids in the traceability table; the orchestrator assigns/registers them on the spine.
---

# product-architect (ERD)

Define the **Engineering Requirements / System Architecture Document (ERD)** from
the Product Spec. This is the architecture role only (Stage 3) — the split-out
Phase-2 of the old product-architect monolith. It does not write the product
spec (`product-manager`) or run implementation (`product-architect-reviewer`).

## Produce the ERD

Write `runs/<slug>/architecture/erd.md`, **milestone-set-aware** (design for the
whole forward journey so a later milestone isn't painted into a corner):

- **Components** — each with an id, purpose, owned data/state, dependencies.
- **Cross-cutting interfaces** — `IFC-*` contracts: producer→consumer, protocol,
  data shape, auth, key operations, error propagation, sync/async, backpressure.
- **Technology decisions** — with alternatives + rationale + downstream implications.
- **Dependencies & build order** — dependency table → waves (parallelizable sets).
- **Requirements traceability** — map each `REQ-*` to component(s)/`IFC-*` (seeds
  the spine: REQ → component/IFC → detailed-design → task).

Scope the ERD so a component's detailed design can be started **straight from
its high-level requirements** — the ERD must carry enough scoping that Stage 4
jumps directly into the combined design+plan.

## Hardening & refits

- Optionally harden with an `adversarial-plan` critique (reserve for high-stakes /
  cross-cutting architecture).
- **Architecture-tier refit:** re-run scoped to the affected subsystem, feeding
  current artifacts as context, then diff/merge into the spine and re-point
  dependency links. Human-gated. If the refit direction hinges on an unclear
  claim, fire a `prototype-runner` spike first.

See the design doc's ERD/architecture and feedback-loop sections.
