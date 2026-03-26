# Repository Guidelines

## Project Structure & Module Organization

`scenes/` contains Godot scenes, with `main.tscn` as the runtime entrypoint. `scripts/` holds gameplay and controller code; core rules and state live under `scripts/core/`, while UI-specific helpers live under `scripts/ui/`. `tests/` contains the custom GDScript test harness and suites such as `controller_input_suite.gd` and `ghost_drop_suite.gd`. `tools/` contains developer utilities like the visual capture runner. Runtime assets belong in `assets/`, and generated screenshots belong under `output/visual-checks/`.

## Build, Test, and Development Commands

- `godot4 --path .`: open the project for interactive development.
- `godot4 --headless --path . -s res://tests/test_runner.gd`: run the lightweight logic and controller test suites.
- `./scripts/capture_visual_state.sh default`: generate a deterministic visual baseline PNG.
- `./scripts/capture_visual_state.sh ghost desktop_720p`: capture a specific scenario and preset for UI review.
- `./scripts/build_web.sh`: export the phone-testable Web build to `build/web/`.
- `./scripts/serve_web_https.sh`: expose the Web build through HTTPS for phone browsers that require a secure context.
- `git status --short`: verify the worktree before staging or releasing.
- `godot4 --headless --path . -s res://tests/test_runner.gd`: run before milestone commits or tags.

Prefer the wrapper capture script over calling `tools/visual_capture_runner.gd` directly; it supplies the renderer and display flags this repo expects.
For mobile browser validation, plain `./scripts/serve_web.sh` is only for quick LAN smoke testing; use `./scripts/serve_web_https.sh` when browser features are gated behind HTTPS.

## Coding Style & Naming Conventions

Use GDScript with tabs for indentation, matching the existing files. Keep `class_name` types and script constants in `PascalCase` and `SCREAMING_SNAKE_CASE` respectively; functions and variables should stay `snake_case`. Favor small helper methods and explicit typed locals where the code already does so, for example `var board: RefCounted` or `func reset() -> void`.

## Testing Guidelines

Tests use the in-repo harness in `tests/test_harness.gd`; add new cases to the relevant suite and register them from `tests/test_runner.gd`. Name test helpers descriptively, e.g. `_test_camera_swap_transition`. For rendering or HUD changes, run the headless suite first, then capture at least `default` plus a scenario that matches the change such as `ghost` or `flipped_camera`.

## Commit & Pull Request Guidelines

Use Conventional Commits by default (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`). Keep subjects concise and action-oriented. `VERSION` is the canonical repo version, `CHANGELOG.md` tracks released milestones, and release tags use the `vX.Y.Z` form. Pull requests should summarize gameplay or UI impact, list validation commands run, and include updated screenshots for any visual change. If scripts, scenarios, controls, or validation workflows change, update `docs/codex/` in the same PR.
