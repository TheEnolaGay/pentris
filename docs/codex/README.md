# Codex Handbook

This directory is the local workflow memory for Codex in this repo.

Use it to avoid re-discovering repo-specific commands, validation paths, and failure cases. Prefer these docs over generic assumptions when working in `pentris`.

## Maintenance Contract

Update `docs/codex` in the same task whenever any of the following change:

- scripts or commands used to run, test, or capture the game
- visual scenarios exposed by `prepare_visual_scenario()`
- input or control surfaces that affect validation expectations
- workflow expectations for screenshots, tests, or review artifacts
- git workflow, versioning, release steps, or tagging conventions

If a workflow change ships without a matching doc update, treat the task as incomplete.

## Start Here

- [workflows.md](/home/bockscar/Git/pentris/docs/codex/workflows.md): canonical run, test, and visual-check commands
- [pitfalls.md](/home/bockscar/Git/pentris/docs/codex/pitfalls.md): known repo-specific failure cases and recoveries

## Rules Of Use

- Prefer exact repo scripts over improvised command variants.
- Treat visual validation and headless test validation as different workflows.
- When a command here disagrees with memory, trust the repo-local doc and verify against the referenced script or source.
