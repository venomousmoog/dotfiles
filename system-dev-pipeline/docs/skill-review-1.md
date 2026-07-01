# system-dev-pipeline — Skill Review R1 (2026-07-01)

Parallel per-skill review (skill-creator / skill-evaluator criteria): triggering, structure/leanness, fidelity to the design doc, executability. One reviewer agent per skill.

## Scorecard (1-5)

| Skill | Trigger | Structure | Fidelity | Executability | Overall |
|---|---|---|---|---|---|
| system-dev | 4 | 5 | 4 | 3 | **4** |
| clarify-product | 4 | 5 | 4 | 3 | **4** |
| product-manager | 4 | 5 | 4 | 4 | **4** |
| milestone-slicing | 4 | 5 | 4 | 3 | **4** |
| test-spec-generator | 4 | 5 | 5 | 4 | **4** |
| product-architect | 3 | 5 | 3 | 3 | **3** |
| prototype-runner | 4 | 5 | 4 | 3 | **4** |
| component-detailed-design | 4 | 5 | 4 | 3 | **4** |
| product-architect-reviewer | 3 | 4 | 3 | 3 | **3** |

**Structure/leanness is uniformly excellent** (progressive disclosure worked). The gaps are in fidelity/executability detail and cross-skill triggering — expected for first drafts.

## Cross-cutting themes (the real signal)

**P0 — correctness bugs (skills contradict the design's control model):**
1. **`product-architect` ID ownership** — frontmatter says it "owns component/IFC-* ids", but design C3 says the **orchestrator** assigns IDs and the architect only *seeds* the traceability table. Fix → "proposes/seeds ids; orchestrator registers."
2. **`product-architect-reviewer` triage ownership** — claims it "owns in-flight adjustment" and classifies within-component vs cross-interface, but design C6 puts triage on the **orchestrator** (which holds the spine). Fix → "reports/proposes; orchestrator classifies + gates."
3. **`product-architect-reviewer` broken agent paths** — references `agents/implementer.md` / `agents/reviewer.md` as skill-relative, but they live at the **plugin root** `agents/`. Fix → `${CLAUDE_PLUGIN_ROOT}/agents/…`.
4. **`system-dev` role mislabel** — calls `product-architect-reviewer` "the implementers"; it *dispatches* the implementer/reviewer personas.
5. **`milestone-slicing` sequencing bug** — requires mapping milestones to `SCN-*`, but the Test Spec (SCN-* source) is a *later* stage (3t). Fix → milestones carry provisional acceptance; bind `SCN-*` on spine-resync after test-spec. (Also worth a one-line clarification in the design doc.)

**P1 — triggering collisions (top risk in a 9-skill plugin; fix in descriptions with explicit boundary lines):**
- spec-refit re-derivation: `product-manager` ↔ `test-spec-generator` (both claim it).
- milestones / "the MVP": `product-manager` ↔ `milestone-slicing` ↔ `clarify-product`.
- "decompose components / design component X": `product-architect` ↔ `component-detailed-design`.
- mid-build refit / in-flight adjustment: `product-architect-reviewer` ↔ `system-dev`.
- "write the product spec": `clarify-product` ↔ `product-manager`.
- mid-scope "idea → spec + design": `system-dev` ↔ stage skills.

**P2 — recurring omissions (same fix applies to many skills → do it once, shared):**
- **Refit bookkeeping** missing: record `path` on the manifest entry; on a refit, write the new version to the canonical path and move the prior to `history/…@<rev>.md` with a `supersedes` link.
- **Gate hand-back**: skills read as if they self-gate; they must hand the gate to the orchestrator (only the orchestrator publishes + mdoc-monitors).
- **Proportionality/collapse rule** (design C8) absent from most stage skills.
- **Inline manifest-entry template + ID scheme** (system-dev, component-detailed-design).
- **Named inputs/paths** (clarify-product's `product-spec-inputs`, test-spec-generator's `product-spec.md` input).
- **Risk-triage rubric** for the adversarial-plan-vs-writing-plans fork (component-detailed-design).

## Recommended fixes

1. **Add `references/conventions.md`** to the plugin (shared): the manifest schema + ID scheme, the refit bookkeeping rule (`path`/`history`/`supersedes`), gate hand-back to the orchestrator, and the proportionality rule. Have each stage skill point to it in one line — fixes all the P2 items **once** without bloating nine skills (keeps leanness).
2. **P0 correctness edits** to `product-architect` (ID ownership), `product-architect-reviewer` (triage ownership + `${CLAUDE_PLUGIN_ROOT}/agents/` paths), `system-dev` (implementer role line), `milestone-slicing` (provisional-acceptance/SCN binding).
3. **P1 description boundary lines** — one clause per colliding pair, ceding the neighbor's job.
4. Reflect the milestone↔SCN sequencing note back into the design doc.

## Next
Apply P0 + the shared conventions.md first (highest value, cheap), then P1 description tuning. Deeper skill-creator execute-and-grade eval loop is best reserved for `system-dev` and `clarify-product` after these edits.
