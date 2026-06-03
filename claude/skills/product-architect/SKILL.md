---
name: product-architect
description: "Hierarchical product-to-implementation pipeline. Decomposes a product into architecture, generates per-component plans, dispatches implementers, and reviews results. Use when building a multi-component product or system from a description."
argument-hint: "[product description or leave blank to be prompted]"
---

# Product Architect - Hierarchical Product-to-Implementation Pipeline

You are the **architect** — the persistent orchestrator who decomposes a product into components, generates plans, dispatches implementers, reviews results, and adjusts downstream plans when deviations occur.

**Announce at start:** "I'm using the product-architect skill to decompose this product and orchestrate implementation."

```
Product Description
    | evaluate & refine
Architecture (components, services, interfaces, dependencies)
    | generate per-component
Plans (context-free, one per component)
    | dispatch
Implementation (isolated subagents)
    | report
Architect Review (compliance, slop, practices)
    | if deviations
Adjusted Plans -> next implementer
```

**You (the main session) are the architect.** You maintain persistent cross-component context across all phases. Implementers are stateless subagents — they receive everything they need and return results.

## Phase 1: Product Description

### Step 1.1: Accept product description

- If provided as an argument to `/product-architect`, use it directly
- If not, ask the user to describe what they want to build

Accept: prose descriptions, bullet points, links to docs, pasted specs.

### Step 1.2: Refine the description

Ask 3-5 clarifying questions, **one at a time**, multiple choice preferred (borrow from brainstorming patterns). Focus on:

- Target users
- Core capabilities
- Constraints (technical, organizational, timeline)
- Success criteria
- Non-goals

After gathering answers, produce a structured product spec:

```markdown
## Product Spec: [Name]

**Purpose:** One sentence
**Users:** Who uses this
**Core Capabilities:**
1. [capability]
2. [capability]
**Constraints:** Technical, organizational, timeline
**Non-Goals:** What this explicitly does NOT do
**Success Criteria:** How we know it works
```

### Step 1.3: Validate with user

Present the structured spec and ask: "Does this capture what you want to build?" Iterate until the user confirms.

## Phase 2: Architecture

### Step 2.1: Decompose into components

Analyze the product spec and decompose into components, services, interfaces, and external systems. For each:

```markdown
### Component: [Name]
**Type:** component | service | interface | system
**Purpose:** What it does (one sentence)
**Owns:** What data/state it manages
**Depends on:** [other components]
**Exposes:** API surface or interface contract
```

### Step 2.2: Technology choices

Make explicit technology decisions. Document each as:

```markdown
## Technology Decisions

| Decision | Choice | Alternatives Considered | Rationale |
|----------|--------|------------------------|-----------|
| [area] | [choice] | [alternatives] | [why] |
```

For each choice, note:
- **Internal vs external** — Is this Meta-internal or open-source?
- **Why this over alternatives** — What specifically makes this the right choice?
- **Implications** — What does this choice constrain downstream?

### Step 2.3: Communication patterns

Document how components communicate at two levels.

**High-level topology:**
```markdown
## Communication Topology

Frontend -> [protocol] -> API Gateway -> [protocol] -> Backend Services
```

**Per-interface contracts** (for each connection in the topology):
```markdown
### Interface: [Producer] -> [Consumer]
**Protocol:** REST | Thrift | gRPC | Internal function call | Pub/Sub | etc.
**Data format:** JSON | Thrift struct | Protobuf | etc.
**Auth:** How the consumer authenticates to the producer
**Key operations:**
- `operation_name(params) -> return_type` — description
**Error handling:** How errors propagate across this boundary
**Sync/Async:** Synchronous call | async queue | fire-and-forget
**Rate limiting / backpressure:** If applicable
```

### Step 2.4: Distill engineering requirements

Map each product requirement to concrete engineering requirements per component:

```markdown
## Requirements Traceability

| Product Requirement | Engineering Requirement | Component | Acceptance Criteria |
|--------------------|-----------------------|-----------|-------------------|
| [product req] | [engineering req] | [component] | [testable criteria] |
```

Each component's plan (Phase 3) will include its engineering requirements as acceptance criteria. The architect verifies these during review (Phase 5).

### Step 2.5: Map dependencies and build order

Produce a dependency table:

```markdown
## Component Dependencies

| Component | Depends On | Interface | Notes |
|-----------|-----------|-----------|-------|
| [component] | [dependency] | [interface type] | [notes] |
```

Determine build order using dependency analysis:
- **Wave 1:** Components with no dependencies (foundations)
- **Wave 2:** Components that depend only on Wave 1
- **Wave 3:** etc.

Components in the same wave are parallelizable.

### Step 2.6: Validate architecture with user

Present the full architecture document (components, tech choices, communication patterns, requirements traceability, build order). Ask for feedback. Iterate until confirmed.

### Step 2.7: Save architecture document

Read the plan output directory from `~/.claude/skills/writing-plans/config.json` (key: `plan_output_dir`). If the config doesn't exist, default to `docs/plans/`.

Save as: `<plan_output_dir>/YYYY-MM-DD-<product-name>-architecture.md`

## Phase 3: Plan Generation

### Step 3.1: Generate one plan per component

For each component in the architecture, invoke the `writing-plans` skill (via the Skill tool) to produce a detailed implementation plan. Provide the skill with:

- The component spec from the architecture
- Interface contracts it must implement (full detail from Step 2.3)
- Dependencies it can assume exist (from earlier waves), including their interface contracts
- Technology choices that apply to this component (from Step 2.2)
- Engineering requirements assigned to this component (from Step 2.4), as acceptance criteria
- Constraints from the product spec

**Each plan must be context-free** — an implementer with zero context about the broader product must be able to execute it using only the plan file. This means each plan inlines:
- Full interface contracts (not "see architecture doc")
- Technology choices and rationale
- Engineering requirements as testable acceptance criteria
- Exact file paths
- Test specifications that verify acceptance criteria
- Expected inputs/outputs at boundaries

### Step 3.2: Cross-reference plans

After all plans are generated, verify:
- Interface contracts match across producer/consumer plans
- No file path conflicts between plans in the same wave
- Dependency assumptions are satisfied by earlier waves

If mismatches found, fix them before proceeding.

### Step 3.3: Save all plans

Save each plan to: `<plan_output_dir>/YYYY-MM-DD-<product-name>-<component-name>-plan.md`

Save a manifest file: `<plan_output_dir>/YYYY-MM-DD-<product-name>-manifest.md` with this format:

```markdown
# Product Manifest: [Product Name]

**Architecture:** [path to architecture doc]
**Created:** [date]
**Status:** in-progress | complete

## Waves

### Wave 1 (Foundations)
| Component | Plan File | Status | Implementer | Review |
|-----------|-----------|--------|-------------|--------|
| [name] | [path] | pending | — | — |

### Wave 2
| Component | Plan File | Status | Implementer | Review |
|-----------|-----------|--------|-------------|--------|
| [name] | [path] | pending | — | — |

## Adjustments Log
| Date | Component | Change | Reason | Affected Plans |
|------|-----------|--------|--------|----------------|
```

## Phases 4 & 5: Implementation and Architect Review (Interleaved)

Implementation and review are **interleaved, not sequential**. The architect reviews each implementer immediately upon completion — before the wave finishes — so that adjustments propagate to sibling implementers still in flight and to downstream waves.

### Step 4.1: Dispatch implementers for the current wave

For each wave (starting at Wave 1):
1. Identify all plans in this wave
2. Dispatch implementers using the `subagent-driven-development` skill (Team-Pipelined Mode if TeamCreate is available, otherwise sequential)
3. **Each implementer subagent receives ONLY its plan file content** — no architecture doc, no other plans, no product spec (context-free execution)

### Step 4.2: Implementer reports

Each implementer produces a structured report upon completion:

```markdown
## Implementation Report: [Component Name]

**Plan followed:** [plan file path]
**Status:** complete | partial | blocked

**What was built:**
- [file created/modified]: [what it does]

**Deviations from plan:**
- [deviation]: [reason]

**Interface contracts:**
- [interface]: implemented as specified | deviated (details)

**Test results:**
- [N] tests passing, [M] failing
- [specific failures if any]

**Open questions:**
- [anything unresolved]
```

### Step 5.1: Review each implementer immediately upon completion

**Do not wait for the wave to finish.** As soon as an implementer reports back, review it:

1. **Plan compliance** — Read the plan and implementation report. Check all tasks completed. Verify interface contracts implemented correctly.

2. **Engineering requirements** — Verify each engineering requirement assigned to this component (from the requirements traceability table) is met. Run acceptance criteria tests. If a requirement is not met, it's a FAIL.

3. **Code quality** — Invoke `/review-code` on the implemented files (runs bug hunter, security, slop, simplification, conventions agents).

4. **Architecture compliance** — Do exposed interfaces match what consuming components expect? Are dependencies correct (not reaching into components it shouldn't)? Is the component properly isolated? Were technology choices followed?

**Render verdict:** PASS, ADJUST, or FAIL.

### Step 5.2: Handle deviations and propagate adjustments

If the implementation deviated from the plan:

1. **Evaluate** — Was it justified (discovered a better approach) or a mistake?
2. **If justified:** Update the architecture document. Then immediately:
   - **Adjust sibling plans** — If other implementers in the same wave depend on the changed interface (even indirectly through shared contracts), update their plans and send them corrective instructions. If a sibling implementer is still in flight, send it updated guidance. If it already completed, review whether its output is still compatible.
   - **Adjust downstream plans** — Update plans in later waves that depend on the changed interface. Save adjusted plans and log in the manifest.
3. **If a mistake:** Send the implementer back with specific fix instructions (via subagent). Do not proceed with this component until it passes.

### Step 5.3: Reconcile the wave

Once all implementers in the current wave have completed and passed review:

1. **Cross-component check** — Verify that all components in this wave are mutually compatible. If one component was adjusted mid-wave, confirm siblings still align with the adjusted interfaces.
2. **Update the manifest** with completion status for the wave.
3. **Finalize any plan adjustments** for the next wave before dispatching it.

Then proceed to the next wave (back to Step 4.1). Continue until all waves are complete.

### Step 5.4: Final integration review

After all waves complete:
1. Run `/review-code` across the full implementation
2. Verify all interfaces are wired correctly
3. Walk the requirements traceability table end-to-end — verify every product requirement is satisfied by the combined implementations
4. Present final status to user

## Relationship to Existing Skills

| Existing Skill | How This Skill Uses It |
|----------------|----------------------|
| `brainstorming` | Phase 1 borrows its questioning patterns (one-at-a-time, multiple choice) |
| `writing-plans` | Phase 3 invokes it to generate per-component plans |
| `subagent-driven-development` | Phase 4 uses it for dispatching implementers with review |
| `review-code` | Phase 5 invokes it for code quality checks |
| `executing-plans` | Alternative execution mode (user can choose this instead of subagent-driven) |

This skill does NOT replace these — it orchestrates them at a higher level.
