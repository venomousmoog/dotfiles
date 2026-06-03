---
name: review-code
description: Multi-agent code review for arbitrary files, directories, uncommitted changes, or code snippets. Runs 5 specialized agents in parallel with validation phase. Use when the user wants to review code that isn't a Phabricator diff.
argument-hint: [path/to/file, src/, changes, or paste code inline]
---

# Review Code - Multi-Agent Code Review

You are an expert code reviewer orchestrating a comprehensive, multi-agent analysis of arbitrary code.

## Overview

This skill uses **5 specialized agents in parallel** followed by a **validation phase** to provide high-confidence findings:

| Agent | Focus |
|-------|-------|
| 01-bug-hunter | Bugs, logic errors, runtime issues |
| 02-security-reviewer | Security vulnerabilities |
| 03-slop-detector | AI slop detection (dynamically loaded rules) |
| 04-simplification-coach | Over-complexity (dynamically loaded rules) |
| 05-convention-checker | CLAUDE.md and project conventions |
| 06-finding-validator | Independent two-phase verification |

**Key principles:**
- **HIGH SIGNAL ONLY** — Only flag issues with 80%+ confidence after validation
- **Two-phase validation** — Review agents find issues, validator agents independently verify
- **Parallel execution** — 5 review agents run simultaneously for speed
- **Dynamic rules** — Slop and simplification rules loaded at runtime from source skills

## Phase 1: Input Resolution (Steps 1-3)

### Step 1: Determine Input Mode

Determine what the user wants reviewed based on their invocation:

| Mode | Trigger | Action |
|------|---------|--------|
| Files | `/review-code path/to/file.py` or `/review-code path/to/a.py path/to/b.py` | Verify each file exists, read full content |
| Directory | `/review-code src/` (path ends with `/` or is a directory) | Glob for code files (`**/*.{py,js,ts,tsx,jsx,cpp,c,h,hpp,java,go,rs,rb,php,hack,swift,kt}` etc.), cap at 50 files. If exceeded, ask user to narrow scope via AskUserQuestion |
| Changes | `/review-code changes` OR `/review-code` with no args in a dirty worktree | Auto-detect VCS: check for `.sl` dir → use `sl status`/`sl diff`, else check `.git` dir → use `git status`/`git diff`. Read full files + diff hunks |
| Snippet | User pastes code inline with the command | Store as virtual file `<snippet>` |

If `/review-code` is invoked with no args and the worktree is clean, ask the user what they want to review via AskUserQuestion.

### Step 2: Discover CLAUDE.md Rules

Walk up from each target file's directory to the repo root (or home directory), collecting all `CLAUDE.md` files found. Read and store the rules as `claude_md_rules`.

### Step 3: Read Context

- **Read all target files in full** — not just hunks
- **For file/dir/changes modes:** Read 3-5 nearby files (same directory or sibling directories) for convention detection. Look for files with similar extensions and purposes. Store detected patterns as `nearby_conventions`.
- **For changes mode:** Capture both the diff hunks AND full file content. The diff hunks tell us what changed; the full files provide context.

## Phase 2: Dynamic Skill Loading (Step 4)

Read external skill files at runtime to extract review rules. This ensures the review stays current as those skills evolve.

### Step 4: Load External Rules

For each rules variable, try user path first, then system path. Extract the specified section.

| Variable | Skill Source | Section to Extract |
|----------|-------------|-------------------|
| `SLOP_RULES` | `unslop-code/SKILL.md` | From "## Slop Patterns" through "## Detection Guidelines" |
| `TEXT_SLOP_RULES` | `unslop-text/SKILL.md` | "## Detection Patterns" section (all subsections) |
| `SIMPLIFICATION_RULES` | `simplify-coach/SKILL.md` | From "## Simplification Heuristics" through end of file |

**Paths to check (first match wins):**
1. `~/.claude/skills/<skill-name>/SKILL.md`
2. `/usr/local/claude-templates-cli/components/skills/<skill-name>/SKILL.md`

**If a skill file can't be read:** Log a warning to the user (e.g., "Could not load unslop-code rules, skipping slop detection agent") and skip the corresponding agent. Do NOT fail the entire review.

## Phase 3: Parallel Review (Step 5)

### Step 5.1: Prepare Context Bundle

Assemble the review context from all gathered information:

```python
REVIEW_CONTEXT = {
    "input_mode": "files|directory|changes|snippet",
    "target_description": "human-readable description of what's being reviewed",
    "files": [
        {
            "path": "relative/path/to/file.py",
            "content": "full file content",
            "diff_hunks": "diff output or null"
        }
    ],
    "nearby_conventions": "detected patterns from nearby files",
    "claude_md_rules": "discovered CLAUDE.md rules"
}
```

### Step 5.2: Launch 5 Review Agents in Parallel

**CRITICAL: Launch all agents in a SINGLE message for parallel execution.**

Read each agent's prompt file from `~/.claude/skills/review-code/agents/` and launch them:

```python
# Agent 1: Bug Hunter (opus)
Agent(
    model="opus",
    description="Bug and logic error analysis",
    prompt=f"""
    {Read('agents/01-bug-hunter.md')}

    ## Review Context
    {json.dumps(REVIEW_CONTEXT, indent=2)}

    Analyze and return ONLY valid JSON with your findings.
    """
)

# Agent 2: Security Reviewer (opus)
Agent(
    model="opus",
    description="Security vulnerability analysis",
    prompt=f"""
    {Read('agents/02-security-reviewer.md')}

    ## Review Context
    {json.dumps(REVIEW_CONTEXT, indent=2)}

    Analyze and return ONLY valid JSON with your findings.
    """
)

# Agent 3: Slop Detector (opus) — SKIP if SLOP_RULES failed to load
Agent(
    model="opus",
    description="AI slop detection",
    prompt=f"""
    {Read('agents/03-slop-detector.md')}

    ## Dynamically Loaded Rules
    ### SLOP_RULES (from unslop-code)
    {SLOP_RULES}

    ### TEXT_SLOP_RULES (from unslop-text)
    {TEXT_SLOP_RULES}

    ## Review Context
    {json.dumps(REVIEW_CONTEXT, indent=2)}

    Analyze and return ONLY valid JSON with your findings.
    """
)

# Agent 4: Simplification Coach (opus) — SKIP if SIMPLIFICATION_RULES failed to load
Agent(
    model="opus",
    description="Over-complexity detection",
    prompt=f"""
    {Read('agents/04-simplification-coach.md')}

    ## Dynamically Loaded Rules
    ### SIMPLIFICATION_RULES (from simplify-coach)
    {SIMPLIFICATION_RULES}

    ## Review Context
    {json.dumps(REVIEW_CONTEXT, indent=2)}

    Analyze and return ONLY valid JSON with your findings.
    """
)

# Agent 5: Convention Checker (opus)
Agent(
    model="opus",
    description="Convention and pattern enforcement",
    prompt=f"""
    {Read('agents/05-convention-checker.md')}

    ## Review Context
    {json.dumps(REVIEW_CONTEXT, indent=2)}

    Analyze and return ONLY valid JSON with your findings.
    """
)
```

## Phase 4: Validation and Output (Steps 6-8)

### Step 6: Validate Findings

**6.1 Aggregate findings** from all agent JSON responses. Group findings by file path.

**6.2 Launch validation agents** — one per file with findings:

For each file that has findings, launch a `06-finding-validator` agent:
- Use **opus** for files with BUG-* or SEC-* findings
- Use **sonnet** for files with only SLOP-*, SIMP-*, or CONV-* findings

Each validator receives the file content and the findings to validate (but NOT the original agent's reasoning).

**6.3 Apply two-tier confidence scoring:**

For each finding, compute final confidence:

- **Confirmed findings:** `final = min(raw_confidence + (100 - raw_confidence) * 0.3, 99)`
  - Example: raw 85% → confirmed → final 89.5% → cap at 99%
- **Rejected findings:** `final = raw_confidence * 0.5`
  - Example: raw 90% → rejected → final 45%
- **Threshold: Only include findings with >= 80% final confidence**

**6.4 Error handling:**
- **Partial agent failure:** Continue with findings from successful agents; inform user which agents failed
- **All agents failed:** Fall back to standard single-pass review (just read and review the code directly)
- **Validator timeout/failure:** Use raw confidence scores (skip boost/reduction), still apply 80% threshold
- **Always inform user** of any failures

### Step 7: Present Results

Display the validation results table:

```
## Code Review Results for [target]

| Issue | Location | Raw | Validation | Final | Status |
|-------|----------|-----|------------|-------|--------|
| BUG-001: Null pointer deref | file.py:42 | 85% | CONFIRMED (95%) | 98% | Include |
| SEC-001: SQL injection | db.py:88 | 75% | REJECTED (85%) | 38% | Exclude |
| SLOP-003: Narrator comments | util.py:10-25 | 90% | CONFIRMED (90%) | 93% | Include |
| SIMP-001: Single-impl interface | svc.py:5-30 | 80% | CONFIRMED (75%) | 86% | Include |
| CONV-001: Naming mismatch | util.py:15 | 70% | CONFIRMED (70%) | 79% | Exclude |

**Blocking:** N findings (BUG-*, SEC-*)
**Quality:** N findings (SLOP-*, SIMP-*)
**Nits:** N findings (CONV-*)
**Excluded:** N findings (below 80% threshold)
```

### Step 8: Offer Actions

Ask the user what they'd like to do with the findings:

```javascript
AskUserQuestion({
  questions: [{
    header: "Review Actions",
    question: `Found ${total} validated findings. What would you like to do?`,
    options: [
      { label: "Fix all", description: "Edit files directly for all findings" },
      { label: "Fix by category", description: "Pick categories: bugs, security, slop, simplification, conventions" },
      { label: "Fix interactively", description: "Review each finding one by one, approve or skip" },
      { label: "Report only", description: "No changes, just the report" }
    ]
  }]
})
```

**If user selects "Fix all":** Apply all suggested fixes by editing the files directly.

**If user selects "Fix by category":** Ask which categories to fix, then apply fixes for those categories.

**If user selects "Fix interactively":** Present each finding one at a time with its suggested fix. User approves or skips each.

**If user selects "Report only":** No changes made. Review complete.

**After fixes:** Offer to re-run the review on modified files:
```javascript
AskUserQuestion({
  questions: [{
    header: "Re-review",
    question: "Files have been modified. Run review again on changed files?",
    options: [
      { label: "Yes", description: "Re-run review on modified files" },
      { label: "No", description: "Done" }
    ]
  }]
})
```

## Important Reminders

### DO:
- Read entire files, not just hunks
- Analyze 3-5 nearby files for conventions
- Load external rules dynamically (don't hardcode)
- Launch all review agents in parallel (single message)
- Validate all findings through the validator agent
- Apply the 80% confidence threshold
- Ask user before making any changes
- Handle failures gracefully (skip failed agents, continue with rest)

### DON'T:
- Flag issues below 80% final confidence
- Make changes without user approval
- Fail the entire review if one agent or skill file fails
- Flag pre-existing issues in unchanged code (for `changes` mode)
- Hardcode slop/simplification rules (always load dynamically)
- Report more than 10 findings per agent (prioritize by severity)
