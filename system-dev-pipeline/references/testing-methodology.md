# Testing methodology

How the pipeline validates requirements. It is applied to each requirement's
`validation` section to produce the **Test Spec** (see
`references/stages/test-spec-generator.md`); the implementation back-test and
`test-spec-critic` follow the same rules. This is reusable guidance, not a stage.

## Principles

- **Prefer full end-to-end execution.** Validate a requirement by exercising the
  real product path end to end (user-visible behavior / cross-component flow), not
  a unit-level proxy. The point is to prove the *system* works, not that a
  function returns.
- **Avoid mocks.** Use real components, services, and data wherever feasible. A
  mock is a last resort — only when a real dependency is genuinely unavailable
  (external/paid/nondeterministic) — and then it must be **explicitly flagged** in
  the scenario and kept as narrow as possible. Never mock the thing under test; a
  green test built on mocks of the subject proves nothing.
- **Validate negative and boundary cases**, not just the happy path: failure
  modes, error handling, malformed / empty / oversized input, permission denials,
  and the stated **non-goals** (things that must *not* happen).
- **Executing tests + real numbers.** A validation runs and produces an observable
  pass/fail — a command that exits 0, a measured latency/throughput vs a
  threshold, an asserted output — not a description or a claim (evidence over
  introspection, same ethos as prototyping).
- **Deterministic & repeatable.** Control inputs/environment so the same run gives
  the same verdict; flag and quarantine inherent nondeterminism rather than
  letting it flake the gate.
- **One condition ↔ one requirement.** Every validation condition traces to the
  `REQ-*` (and its `validation` intent) it proves; no orphan conditions, and no
  requirement without at least one condition.
- **Proportionate.** Match validation depth to the requirement's stakes — don't
  gold-plate trivial requirements; exhaustively cover load-bearing/risky ones.

## Kinds of validation condition

Map each requirement's `validation` intent to the right executable form:

- **Behavioral E2E** — drive the product through the user flow, assert the outcome.
- **Integration** — exercise a cross-component contract with real components.
- **Performance / reliability** — measure against a threshold under realistic load
  or fault injection.
- **Negative** — assert the guard/failure behaves and the non-goals don't occur.

Each becomes a Test-Spec `SCN-*` with a concrete **setup → action → expected** plus
a **pass/kill condition**, linked `satisfies` → its `REQ-*`.
