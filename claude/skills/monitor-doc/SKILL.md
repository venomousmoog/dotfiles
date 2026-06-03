---
name: monitor-doc
description: Use when a published mdoc needs ongoing monitoring for reviewer comments. Polls for new comments, triages them as wording/semantic clarifications (auto-addressed) or model/architecture changes (escalated to user). Triggers on "monitor the doc", "watch for comments", "monitor mdoc", "watch this doc".
argument-hint: "[share_id or leave blank to select from mdoc list]"
---

# Monitor Doc

Monitors a published mdoc for new comments. Automatically addresses wording and semantic clarifications. Escalates model and architecture changes to the user.

## Workflow

```
Identify target doc (arg or mdoc list)
  → whoami to determine the doc owner
  → Export doc content for context
  → Loop:
      mdoc sync <share_id> --status open
        → New comment → check author:
            Owner's comment → apply directly to doc, reply, resolve
            Other's comment → classify:
                Wording/semantic → clarify, update doc, reply (leave open)
                Model/architecture → notify user, wait for guidance
        → If doc updated → mdoc update + mdoc publish
  → Until: no open comments + user says stop
```

## Phase 1: Identify Document

1. If a share_id was provided as argument, use it directly
2. Otherwise, run `mdoc list` and ask the user which document to monitor
3. Run `whoami` to determine the doc owner's username — this is used to distinguish your own comments from others'
4. Run `mdoc export <share_id>` to capture the full document content — this is your reference for understanding context when addressing comments
5. Run `mdoc sync <share_id>` to get initial comment state — note all existing comment IDs so you only process new ones

## Phase 2: Monitor Loop

Poll with `mdoc sync <share_id> --status open` every 2-3 minutes. For each new open comment not previously seen:

### 2.1 Read the Comment

Extract from the sync output:
- **Comment ID** (e.g. `#3407`)
- **Author** (who left the comment)
- **Selected text** (the passage the comment refers to)
- **Comment body** (the actual feedback or question)
- **Any existing replies** (thread context)

### 2.2 Route by Author

Check the comment author against the `whoami` result.

**Owner's comment** (matches `whoami`) → go to **2.3 Handle Owner Comments**

**Other's comment** (anyone else) → classify per **2.4**, then go to **2.5** or **2.6**

### 2.3 Handle Owner Comments

The owner's comments are direct instructions. Apply them to the document without classification.

1. Read the comment as an instruction for what to change
2. Locate the relevant section in the exported document
3. Apply the change directly to the local markdown file
4. Run `mdoc update <share_id> <file>` to push the update
5. Run `mdoc publish <share_id>` to publish
6. Reply to the comment summarizing what was changed: `mdoc reply <share_id> <comment_id> "<summary>"`
7. Resolve the comment: `mdoc resolve <share_id> <comment_id>`

### 2.4 Classify External Comments

Read the comment in the context of the selected text and the full document.

**Wording / Semantic (auto-address):**
- Asks for clarification on existing content
- Questions what a term or phrase means
- Requests expanding on a point already made
- Suggests rewording for clarity
- Points out ambiguity, typos, or missing context
- Asks "what does X mean?" or "can you elaborate on Y?"

**Model / Architecture (escalate to user):**
- Proposes changing the data model, schema, or system design
- Challenges the core approach or design philosophy
- Suggests a different architecture or component structure
- Questions fundamental assumptions or trade-offs
- Proposes adding/removing system components
- Would require rethinking downstream design decisions

When uncertain, escalate — false escalations are cheap, silent model changes are expensive.

### 2.5 Handle External Wording/Semantic Comments

1. Locate the relevant section in the exported document
2. Draft the clarification or expansion that addresses the comment
3. Update the local markdown file with the change
4. Run `mdoc update <share_id> <file>` to push the update
5. Run `mdoc publish <share_id>` to publish
6. Reply to the comment explaining what was clarified or expanded: `mdoc reply <share_id> <comment_id> "<explanation>"`
7. Do **NOT** resolve — leave open for the commenter to read and resolve themselves

### 2.6 Handle External Model/Architecture Comments

1. Present the comment to the user with full context:
   - The selected text
   - The comment and any thread
   - Your assessment of what model change is being proposed
2. Wait for the user's guidance:
   - **Implement**: make the change, update the doc, reply (leave open for commenter)
   - **Push back**: user provides reasoning, draft a reply explaining why the current approach is preferred (leave open for discussion)
   - **Defer**: reply acknowledging the feedback and noting it for future consideration (leave open for commenter)

### 2.5 Re-export After Changes

After any document update, re-export the document to keep your reference copy current:
```
mdoc export <share_id> --output <local_file>
```

## Phase 3: Completion

Continue the loop until:
- No open comments remain
- User explicitly says to stop monitoring

Report final status: how many comments were addressed, how many escalated, current open count.

## Principles

- **Owner comments are instructions.** Apply directly, reply, resolve. No classification needed.
- **Only resolve your own comments.** External comments stay open for the commenter to review your reply and resolve themselves.
- **Escalate model changes, never silently implement them.** The user's design intent comes first. A wording fix is reversible; a model change may not be.
- **Every comment gets a reply.** Never silently resolve or ignore. State what changed or why it didn't.
- **Deslop your replies.** No "Great question!", no "I've gone ahead and...". State what was clarified and where.
- **Re-export after every update.** Your reference copy must match the published version to avoid drift.
- **When uncertain, escalate.** A false escalation costs the user 10 seconds of reading. A silent model change costs hours of rework.
