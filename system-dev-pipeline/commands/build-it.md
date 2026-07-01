---
description: Build it — set up and run the full build pipeline for a task and manage its session execution (idea → spec → test spec → architecture → component designs → implementation), per-milestone workflow with a feedback loop and per-artifact critics. Use for "build this product/system", "run the build pipeline", "set up the workflow for this task", or starting a multi-component build from a description.
argument-hint: "[task/product idea, or a run-root path to resume]"
---

# /build-it

Invoke the **`build-it`** skill to set up and run (or resume) the pipeline for `$ARGUMENTS`.

- If `$ARGUMENTS` is an **idea/description**: start a new run — scaffold a run root, then drive the front stages (clarify-product → product spec → test spec → ERD), then the per-milestone build loop.
- If `$ARGUMENTS` is a **run-root path** (contains `manifest.md`): resume from the manifest — read the spine, find the next ready work, and continue.
- If `$ARGUMENTS` is empty: ask for the idea, or offer to resume a run found under `./runs/`.

Follow the `build-it` skill exactly. It loads each stage's instructions on demand from `references/stages/`, and is proportionate: small tasks collapse stages; large ones use the full pipeline.
