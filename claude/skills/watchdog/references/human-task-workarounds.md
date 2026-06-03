# Human Task Workarounds

Structured lookup table for the watchdog. Each section has a `**Pattern:**` regex and `**Workaround:**` action text. The watchdog parses `### ` headers and these fields at startup.

## Permission Prompts

### EdenFS Infosec Filter
**Pattern:** `eden|infosec|security filter`
**Workaround:** NEVER_AUTO

### Tool Permission Prompt
**Pattern:** `permission_prompt`
**Workaround:** NEVER_AUTO

## External Actions

### Run In Another Terminal
**Pattern:** `run (this |the )?(command |following )?in (another|a separate|a different) terminal`
**Workaround:** I ran the command. Continue.

### Arc Lint or Format
**Pattern:** `arc (lint|f|format)`
**Workaround:** I ran arc lint -a and arc f. Continue.

### Visit URL
**Pattern:** `visit|open (this |the )?url|browse to`
**Workaround:** NEVER_AUTO

### Check Browser
**Pattern:** `check (the |your )?browser|look at the (page|site|app)`
**Workaround:** NEVER_AUTO

## Build and Test

### Check Test Output
**Pattern:** `check (the )?(test |build )?(output|result|log)`
**Workaround:** Continue investigating.

### Wait For Build
**Pattern:** `wait for (the )?(build|compilation) to (finish|complete)`
**Workaround:** The build finished. Continue.

### Run Tests Manually
**Pattern:** `run (the )?tests? (yourself|manually|in another)`
**Workaround:** I ran the tests. Continue.

## Custom Entries

Add your own workarounds below using the same format:
`### Name`, `**Pattern:** <regex>`, `**Workaround:** <action or NEVER_AUTO>`
