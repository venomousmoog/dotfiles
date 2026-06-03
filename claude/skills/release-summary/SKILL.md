---
name: release-summary
description: Generate release summaries for Conveyor-based deployments by analyzing all diffs landed between the last prod push and the current release. Use when the user asks to create a release summary, release notes, or wants to know what changed since the last prod push for a conveyor. Triggers on phrases like "release summary", "release notes", "what shipped", "what landed since prod", or "changelog for conveyor".
---

# Release Summary

Generate a user-facing release summary by comparing the last successful prod push to the current conveyor release, reading all commit messages in between, and categorizing changes.

## Workflow

1. Gather inputs (conveyor IDs, code paths, conveyor config locations)
2. Find commit range (last prod push → current release)
3. Extract commit messages
4. Read formatting instructions and example output
5. Write the summary
6. Output as markdown file

## Step 1: Gather Inputs

Ask the user for:
- **Conveyor IDs** (e.g., `surreal/aria_ai_interactions`). There may be multiple.
- **Code path filter** for `sl log` (e.g., `fbcode/surreal/aria_ai`). This is critical — without it, `sl log` returns every commit in the monorepo.
- **Conveyor config file paths** if not already known. Typically in `~/src/configerator/source/` under a team-specific subdirectory.

If the user has a formatting instructions doc (Google Doc or local file), read it. Otherwise use `references/formatting_instructions.md`.

## Step 2: Find the Commit Range

Run `scripts/get_release_range.py` for each conveyor:

```bash
python3 <skill_dir>/scripts/get_release_range.py <conveyor_id>
```

This returns JSON with `prod_release`, `prod_commit`, `current_release`, `current_commit`.

**Fallback** if the script fails: use the conveyor CLI directly:

```bash
conveyor release status -c <conveyor_id> -l 100 -j 2>/tmp/conv_stderr.txt
```

The JSON output may have stderr warnings appended. Extract the JSON array with:

```python
import re, json
match = re.search(r'^\[.*?\n\]', raw_output, re.DOTALL)
releases = json.loads(match.group(0))
```

Scan releases for the first one with a prod node whose `status` is `"succeeded"`. That's the last prod push. The first release in the list is the current release.

To get a release's commit hash:

```bash
conveyor release get -c <conveyor_id> -r R<number> -j
```

Note: the release number must be prefixed with `R` (e.g., `R620`, not `620`).

## Step 3: Extract Commit Messages

Use `sl log` with a path filter to get only relevant commits:

```bash
sl log <code_path> -r '<prod_commit>::<current_commit>' --template '{desc}\n---COMMIT_SEPARATOR---\n'
```

The path filter is essential. Without it, this returns every commit in fbsource between those two points.

For large sets (100+ commits), write the output to a temp file and process it:

```bash
sl log <code_path> -r '<prod_commit>::<current_commit>' --template '{desc}\n---COMMIT_SEPARATOR---\n' > /tmp/commit_messages.txt
```

Read the full commit descriptions — the `Summary:` sections contain the context needed to understand the intent behind each change.

## Step 4: Read Formatting Instructions

Read `references/formatting_instructions.md` for the output format rules and `references/example_output.md` for a real example.

Key rules:
- Use `[+]` for new features, `[=]` for improvements, `[-]` for removals
- Focus on end-user effect, not engineering details
- Simple, non-technical language
- Combine similar changes — don't itemize every diff
- Don't link diffs
- ~5 items per category max
- Three sections: Agent Features, Timeline Features, System Features

## Step 5: Write the Summary

Analyze all commit messages and categorize changes into the three sections. Read the full `Summary:` text of each commit to understand stacks and context — don't just use the title line.

Write output to a markdown file (e.g., `release_summary.md`) in the repo root or user-specified location.

## Gotchas

- **Monorepo scale**: Always use path filters on `sl log`. Without them, queries between contbuild commits return hundreds of thousands of commits.
- **Conveyor CLI stderr**: The `conveyor release status` command often appends ODS warning lines after the JSON array. Parse carefully.
- **Release number format**: `conveyor release get` requires `R` prefix (e.g., `R620`).
- **WebFetch limitations**: `internalfb.com` URLs are not fetchable via WebFetch. Use CLI tools (`sl log`, `jf diff-properties`) to read diff details instead.

## Resources

- `scripts/get_release_range.py` — Finds the commit range between last prod push and current release
- `references/formatting_instructions.md` — Output format rules and template
- `references/example_output.md` — Real example of a completed release summary
