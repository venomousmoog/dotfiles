# System-Dev Pipeline — Work Log

Lightweight markdown tracker for building the `system-dev-pipeline` plugin.
Replaces the beads `adp` DB (we stopped using beads for this dev process on 2026-07-01 — see Decision log). **Source of truth now lives in the git repo `~/src/dotfiles/system-dev-pipeline/`** (this log = `docs/log.md`, design = `docs/design.md`).

Status keys: ⬜ ready/todo · 🔵 in-progress · ✅ done · ⛔ blocked

## Work items (dependency order)

| id | item | status | blocked by |
|----|------|--------|-----------|
| ADP-2 | Optimize adversarial-plan prompts (L1+L7+L8) | ✅ done — shipped live | — |
| ADP-3 | Optimize clarify-task prompts (C1+C2+C3+C6) | ✅ done — shipped live | — |
| ADP-4 | Design system-dev pipeline (this design doc) | 🔵 in review (awaiting user validation) | — |
| ADP-11 | Scaffold `system-dev-pipeline` plugin (manifest, skills/agents/commands/hooks) | ⛔ blocked | ADP-4 |
| ADP-12 | Split `product-architect` → product-manager / product-architect / product-architect-reviewer skills | ⛔ blocked | ADP-11 |
| ADP-9 | Build `clarify-product` skill (from clarify-task) | ⛔ blocked | ADP-11 |
| ADP-10 | Build test-spec-generator (E2E scenarios from product spec) | ⛔ blocked | ADP-11 |
| ADP-5 | Build `system-dev` orchestrator skill (driver + gating + spine + triage + back-test) | ⛔ blocked | ADP-11 |
| ADP-8 | Markdown spine/manifest tooling (ID scheme, dependency links, ready-order, export) | ⛔ blocked | ADP-11 |
| ADP-6 | clarify round-3: soften C2 question cap (recover multi-gap recall) | ⬜ ready | — |
| ADP-7 | Fix groundedness sub-metric in clarify eval harness | ⬜ ready | — |

**Ready now:** ADP-6, ADP-7 (independent follow-ups). Everything else waits on ADP-4 → ADP-11.

## Decision log

- **2026-06-28/29** — Optimized `adversarial-plan` (L1+L7+L8) and `clarify-task` (C1+C2+C3+C6); both validated on held-out seeds and shipped live. Harnesses at `~/.claude/planner-opt` and `~/.claude/clarify-opt`.
- **2026-06-29** — Designed the system-dev pipeline: idea → spec → architecture → detailed designs → implementation, with a 3-tier feedback/escalation loop (plan auto / arch+spec gated). R1 adversarial review incorporated (fixed the adversarial-plan/product-architect composition inversion, etc.).
- **2026-06-30** — Added: prototyping (spikes) phase; `clarify-product` front gate; durable artifact pipeline diagram; Test Specification (E2E validation scenarios back-testing the build); split `product-architect` into three standalone skills (product-manager / product-architect / product-architect-reviewer); merged component design + implementation plan into one Component Detailed Design; packaged everything as the `system-dev-pipeline` plugin.
- **2026-07-01** — **Stopped using beads for this dev process** and reverted to this markdown log (user: not confident enough about beads / the in-Meta workflow to commit). Reverted the design's substrate to a **markdown work log + manifest** (beads deferred, not chosen). Stopped the `dolt sql-server` daemon; the beads `adp` DB is retained on disk (`~/.claude/agentic-dev-pipeline/.beads`) but unused.
- **2026-07-01** — `~/.claude/plans/` was reverted twice by **dotsync2** (dotfile sync; rare). Fix per user: **no git**. Renamed the design doc `2026-06-29-system-dev-pipeline-design.md` → `system-dev-pipeline-design.md` (dropping the date-prefix dotsync2 knew about) to dodge future reverts; reconstructed the doc to the correct state first.

- **2026-07-01** — Documented the **execution workflow** (orchestrator runs the pipeline as a workflow: sequential gated front stages → per-milestone fan-out over components → E2E back-test → next milestone; feedback = workflow re-entry) and a **run-layout of artifact paths** (`runs/<product-slug>/…`, with `history/` for superseded versions and a `path` field per manifest entry). Both in the design doc.

- **2026-07-01** — **Wired critic-per-artifact + shared conventions (closes P2).** Added `system-dev-pipeline/references/conventions.md` (manifest schema/ID scheme, refit bookkeeping `path`/`history`/`supersedes`, gate hand-back, proportionality, planning risk-triage, and the **critic engine** — independent critic → severity-graded findings [reuse `adversarial-diff-review/references/severity-rubric.md`] → VERDICT → gate/refit — plus the per-artifact critic map). Authored the one gap, **`test-spec-critic`** (10 skills now). Wired into `system-dev` (Critic-gated discipline + conventions pointer), the design doc (new "Critics (quality gates)" section + status), and the README. Verified the 5 marketplace critics exist (`adversarial-review`, `plan-review`, `design-doc-reviewer`, `devils-advocate`, `prd-quality-check`) — install commands proposed, awaiting user approval (not installed).

- **2026-07-01** — Restructured to **single-entry**: renamed orchestrator `system-dev` → **`build-it`** (the only registered skill / `/build-it`); moved the other 9 stage/critic skills to `references/stages/*.md` (loaded on demand by build-it, NOT registered) so ambient context = 1 skill. Updated plugin.json (skills glob → only build-it; dropped agents registration), the command, README skills section, conventions (critic-map path), and the design doc (build-it renames). **⚠ dotsync2 ALERT:** verification found the plugin dir was reverted at a prior session boundary — the R1 **P0/P1 fixes and the deps-setup (README "Dependencies & setup" + hook dep-check) are GONE from disk**; the 9 moved stage refs are the **pre-P0 versions**. (New files — conventions.md, check-deps.sh, test-spec-critic, CRITICS-SURVEY — survived; edits to pre-existing files were reverted.) Plugin is **untracked** in the agentic-dev-pipeline git repo; `dotsync2` at `/usr/bin/dotsync2` manages `~/.claude`. **Durability decision needed before re-applying the lost fixes** (else they revert again).

- **2026-07-01** — **Moved everything into `~/src/dotfiles/system-dev-pipeline/`** (git-tracked, durable — dotsync2 does **not** manage `src/dotfiles`) as the source of truth, after dotsync2 repeatedly reverted the copy under `~/.claude`. Consolidated docs under `docs/` (design, design-review-1, log, skill-review-1, critics-survey). **Re-applied the dotsync2-eaten R1 P0/P1 fixes** (reviewer triage-ownership + `${CLAUDE_PLUGIN_ROOT}/agents/` paths; product-architect ID-ownership; milestone SCN-sequencing) **and the deps-setup** (README + hook `check-deps.sh`); fixed doc-path refs to `docs/` / `${CLAUDE_PLUGIN_ROOT}`. Committed to git. `~/.claude` install deferred (later: register a marketplace + enable). `check-deps` still flags one missing required dep: `technical-design-doc`.

- **2026-07-02** — **Reworked the testing model.** Requirements now carry **description / justification / validation** sections (`product-manager`). Added reusable **`references/testing-methodology.md`** (prefer full E2E, avoid mocks, validate negatives/boundaries, executing tests + real numbers, one-condition-per-requirement, proportionate). **Redefined the Test Spec = exactly the set of validation conditions for each requirement**: `test-spec-generator` turns each `REQ.validation` into executable `SCN-*` via the methodology (no scope-creep beyond requirements). Updated `test-spec-generator`, `test-spec-critic` (coverage-of-validation + methodology-adherence + no-orphans checks), the design doc (Requirements & Test Spec section, artifact table, traceability, summary), `build-it` stages table, and README. Committed to git.

## Notes / open threads

- `ADP-4` design doc is complete and R1-reviewed; awaiting user validation to "close" (then ADP-11 becomes the next actionable).
- Durability: `~/.claude/plans/` was reverted by **dotsync2** (rare). Per user: **no git repo**. Mitigation = renamed the design doc to a name dotsync2 didn't have. If this log or the review revert too, rename them the same way (do NOT create a git repo).
