# Plan: Add Documentation Update Rule for aria_ai

## Goal
Add a rule that reminds Claude users to check and update documentation after completing changes in `fbcode/surreal/aria_ai`, while minimizing interruptions during iterative work.

## Context

### Existing Structure
- `fbcode/surreal/aria_ai/.llms/rules/DEVMATE_RULES.md` - Code file rules (cpp, h, py, rs)
- `fbcode/surreal/aria_ai/.llms/rules/MARKDOWN_RULES.md` - Markdown formatting rules

### Existing Documentation Guidance
DEVMATE_RULES.md already contains documentation update conditions:
- Rename/move files with documentation references
- Delete functionality mentioned in docs
- Change API signatures documented in README
- Add deprecations affecting documented behavior
- Update configurations mentioned in docs

## Design Considerations

### Challenge: Timing the Reminder
The user wants reminders only at the end of work, not during iteration. Rule triggers include:
- `apply_to_regex` - triggers on file modifications (too frequent)
- `apply_to_user_prompt` - triggers on prompt keywords

### Proposed Approach: Combined Triggers
Use both prompt-based triggers AND plan exit guidance:

**1. Prompt-based triggers** - Activate when users signal completion:
- "done", "finished", "complete", "ready to submit"
- "jf submit", "commit", "create diff"
- "final", "wrap up"

**2. Plan exit guidance** - Rule content instructs Claude to:
- Always include a documentation update step in plans for aria_ai work
- Check documentation when completing the final step of a plan
- Not check during intermediate steps

This belt-and-suspenders approach:
1. Catches users when they signal completion intent (prompt triggers)
2. Ensures plans explicitly include documentation review (instructions)
3. References existing documentation rules in DEVMATE_RULES.md

## Implementation

### Files to Create/Modify

| File | Action |
|------|--------|
| `fbcode/surreal/aria_ai/.llms/rules/DOC_UPDATE_REMINDER.md` | Create - documentation reminder rule |
| `fbcode/surreal/aria_ai/.llms/rules/README_RULES.md` | Create - README content guidelines (moved from MARKDOWN_RULES.md) |
| `fbcode/surreal/aria_ai/.llms/rules/MARKDOWN_RULES.md` | Modify - keep only formatting rules |

---

### 1. DOC_UPDATE_REMINDER.md (Create)

```markdown
---
oncalls: ['aria_ai']
apply_to_regex: 'fbcode/surreal/aria_ai/.*'
apply_to_user_prompt: '(?i)(done|finished|complete|ready|submit|jf submit|create diff|commit|wrap up|final|ship it|plan|implement|build|add feature|refactor)'
---

# Documentation Update Reminder

## For Plans

**IMPORTANT**: When creating a plan for work in `fbcode/surreal/aria_ai/` that
modifies code:

- **Always include "Review and update documentation" as the final step**
- This step should check if any documentation needs updating based on the
  conditions in DEVMATE_RULES.md
- Only add this step for plans that modify code (not pure research/exploration)

## After Completing Changes

When you have **completed** code changes in `fbcode/surreal/aria_ai/`, check if
documentation needs to be updated.

### When This Applies

This check should happen:
- At the **end** of implementing a change (not during iteration)
- When completing the **final step** of a plan
- Before submitting a diff

**Do NOT** check documentation:
- After every individual file edit
- While iterating on a solution
- During intermediate plan steps

### What to Check

Review the documentation update conditions in DEVMATE_RULES.md. Documentation
updates are needed when:
- Files are renamed or moved that are referenced in documentation
- Functionality is deleted that is mentioned in docs
- API signatures change that are documented in README files
- Deprecations are added that affect documented behavior
- Configurations are updated that are mentioned in docs

### How to Offer Updates

After completing changes, briefly check if any documentation conditions apply.
If they do:
1. Identify which markdown files may need updates
2. Offer to update them, explaining what changed
3. Follow the formatting rules in MARKDOWN_RULES.md and content rules in
   README_RULES.md

If no documentation updates are needed, no action is required.
```

---

### 2. README_RULES.md (Create)

This file contains the content-focused guidance extracted from MARKDOWN_RULES.md.

```markdown
---
oncalls: ['aria_ai']
apply_to_regex: '.*/README\\.md$'
apply_to_user_prompt: '(?i)(readme|documentation|docs)'
---

# README Content Rules for Aria AI

These rules govern the **content** of README.md files. For formatting rules,
see MARKDOWN_RULES.md.

## General Content Guidelines

- The documents being authored are intended for a technical audience with
  familiarity with the Aria AI project. There's no need to explain core project
  concepts in every file.
- Write as concisely as possible.
- Don't duplicate lots of code inline in the documentation, but add references
  to code when it makes sense.
- Include code blocks to describe component interfaces or abstractions.
- Focus on documenting the intent of the code and data flow that are difficult
  to observe directly in the code itself.

## README.md Structure

- The README.md should give a high level description of the purpose of the files
  in the directory and how they are used.
- If necessary it should include how the component fits into the wider
  architecture.
- It should include links to any other markdown files in the directory in
  appropriate context, as well as links to child directories when necessary to
  refer to that documentation.
- Not every folder must have a README - only if the folder contains non-trivial
  code.

## README Template

The README should include the content from the template below if relevant -
it's not necessary to stick exactly to this template if deviating and adding
or removing sections makes the content more clear.

```md
# Title

The title will be used as the title of the published wiki page, generally should
be the same as the directory.

## Overview

Describe this directory in a paragraph. This should give the intent of the
directory and how it should be used in other areas. This should be considered to
be the executive summary, and should be sufficient for engineers to understand
if the changes they make belong within this directory, or another.

## Setup and Usage

Information on how to install, setup, run the code, or include example code for
consumers

## Diagram

If relevant, include a diagram for how the objects within in the directory are
put together. When creating diagrams prefer plantUML or mermaid diagrams to
ASCII art.

## Architecture

Detailed architecture description. This should include sub-sections for each
component called out in the diagram section.

## API Reference

If the library exposes APIs for other parts of the codebase, the API should be
documented here
```

## What NOT to Include

- **No todo lists or future work** - Split future work into a separate markdown
  file if needed.
- **No scratchpad content** - Don't use README to keep track of progress.
- **No changeset-specific content** - Don't add things relevant only to the
  current changeset.
- **No easily-obtained info** - Avoid content that is easily obtained from the
  code itself.

**Bad Example**: "now function X does not need parameter Y any longer because of
reason Z" - this is reasoning related to the current context, not the final
state of the system.

## What TO Include

- **Intent and context** - Capture why the code is designed the way it is.
- **Architecture overview** - How the component fits into the wider system.
- **Data flow** - Information difficult to observe directly in the code.

## Splitting Large Sections

- Any section of the README that is large can be extracted out into a relevant
  linked document.
- For example, the Diagram and Architecture sections can be split out into a
  single Architecture.md file and linked from the README.
```

---

### 3. MARKDOWN_RULES.md (Modify)

Update to focus only on formatting, removing content-specific guidance.

```markdown
---
oncalls: ['aria_ai']
apply_to_regex: ".*\\.(md)$"
apply_to_content: .
apply_to_user_prompt: .
---

# Markdown Formatting Rules for Aria AI

These rules govern the **formatting** of markdown files. For README content
guidelines, see README_RULES.md. For when to update documentation, see
DEVMATE_RULES.md.

## Basic Formatting

- Markdown should be formatted according to the markdownlint rules at
  <https://github.com/markdownlint/markdownlint/blob/main/docs/RULES.md>

## CFM Syntax

Markdown files within the surreal/aria_ai folder are published using Codehub
Flavored Markup to the wiki. They must follow:
- CFM syntax at
  <https://www.internalfb.com/wiki/CodeHub/Codehub_Flavored_Markdown/CFM_Syntax/>
- Syntax extensions at
  <https://www.internalfb.com/wiki/CodeHub/Codehub_Flavored_Markdown/CFM_Extensions/>

## Line Wrapping

- Prose lines should be wrapped at 80 columns.

## Links

**IMPORTANT**: A link must _always_ have a relative prefix if it is to be
treated as relative by the publisher.

Examples:
- Same directory: `[mylink](./relative_link.md)`
- Child directory: `[mylink](./child/child_link.md)`
- Parent directory: `[mylink](../../README.md)`

Never use absolute paths. Always use relative paths.

## When Editing

- Run `arc lint -a` to ensure that the content is well formatted.
```

---

## Verification

1. Test that the rule triggers when creating a plan for aria_ai work (includes
   documentation step)
2. Test that the rule triggers when saying "done" or "ready to submit" while
   working in aria_ai
3. Verify it doesn't trigger excessively during iteration
4. Confirm README_RULES.md triggers when editing README.md files
5. Confirm MARKDOWN_RULES.md triggers for all .md files (formatting only)
