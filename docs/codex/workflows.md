# Workflows

This file records the canonical commands Codex should use in this repo.

## Run The Game

Goal: open the project for interactive local inspection.

Command:

```bash
godot4 --path .
```

Use when:

- checking runtime behavior interactively
- verifying feel, controls, or transitions that are hard to judge from static captures

Success signal:

- Godot opens the project without script errors

## Check Git Status

Goal: confirm which files are intentionally staged, ignored, modified, or untracked before commits and releases.

Command:

```bash
git status --short
```

Use when:

- preparing a commit
- verifying `.gitignore` coverage
- confirming release contents before tagging

Success signal:

- generated artifacts such as `.godot/`, `build/`, and `output/` stay out of the intended commit set

## Build The Web Test Target

Goal: create a browser build that can be opened on a phone for real touch testing.

Canonical command:

```bash
./scripts/build_web.sh
```

Release build:

```bash
./scripts/build_web.sh release
```

Use when:

- validating touch behavior on a real phone
- checking mobile layout in a browser
- sharing a quick test build on the local network

Expected artifact:

- `build/web/index.html` plus the exported Web assets

Source of truth:

- [export_presets.cfg](/home/bockscar/Git/pentris/export_presets.cfg)
- [build_web.sh](/home/bockscar/Git/pentris/scripts/build_web.sh)

## Serve The Web Build For Phone Testing

Goal: expose the Web export over LAN so it can be opened on a phone browser.

Canonical command:

```bash
./scripts/serve_web.sh
```

Custom path or port:

```bash
./scripts/serve_web.sh build/web 9000
```

Use when:

- testing the exported build on a phone connected to the same network
- doing quick layout or input smoke checks that do not require secure-context browser features

Expected result:

- a local HTTP server prints a URL such as `http://<host>:8060`

Source of truth:

- [serve_web.sh](/home/bockscar/Git/pentris/scripts/serve_web.sh)

## Serve The Web Build Over HTTPS

Goal: expose the Web export through an HTTPS URL so phone browsers treat it as a secure context.

Canonical command:

```bash
./scripts/serve_web_https.sh
```

Custom path or port:

```bash
./scripts/serve_web_https.sh build/web 9000
```

Use when:

- the phone build reports `Secure Context` or missing browser features
- touch testing depends on browser APIs gated behind HTTPS
- the LAN HTTP flow loads the game but browser capability checks still fail

Expected result:

- a local server binds to `127.0.0.1:<port>`
- a tunnel client prints a temporary `https://...` URL to open on the phone

Known prerequisites:

- one of these tunnel clients must be installed locally:
  - `cloudflared`
  - `ngrok`

Source of truth:

- [serve_web_https.sh](/home/bockscar/Git/pentris/scripts/serve_web_https.sh)

## Run Logic And Controller Tests

Goal: validate gameplay logic and controller behavior without full visual capture.

Command:

```bash
godot4 --headless --path . -s res://tests/test_runner.gd
```

Use when:

- changing gameplay rules
- changing controller input handling
- making rendering-adjacent changes that still have test coverage

Success signal:

- output ends with `All Pentris tests passed.`

Source of truth:

- [tests/test_runner.gd](/home/bockscar/Git/pentris/tests/test_runner.gd)

## Release A Version

Goal: cut a tracked milestone using the repo's versioning workflow.

Canonical steps:

```bash
git status --short
godot4 --headless --path . -s res://tests/test_runner.gd
git add .
git commit -m "chore: release v0.1.0"
git tag v0.1.0
```

Use when:

- shipping a milestone worth versioning
- updating `VERSION` and `CHANGELOG.md`

Required release artifacts:

- `VERSION` contains the current `MAJOR.MINOR.PATCH`
- `CHANGELOG.md` includes the released version entry
- the release commit is tagged as `vX.Y.Z`

Version semantics in this repo:

- `Proud Version` = major
- `Stable Version` = minor
- `Patch Number` = patch

Commit style:

- use Conventional Commits by default for normal history
- use `chore: release vX.Y.Z` for release commits unless a more specific release process replaces it later

## Capture Deterministic Visual Checks

Goal: render a scenario to PNG for UI and scene validation.

Canonical command:

```bash
./scripts/capture_visual_state.sh default
```

Custom preset or output path:

```bash
./scripts/capture_visual_state.sh ghost desktop_720p
./scripts/capture_visual_state.sh flipped_camera output/visual-checks/phone_landscape/flipped-restyled.png
```

Use when:

- changing HUD layout or styling
- changing camera framing or flipped-view presentation
- changing active-piece, landing-shadow, or board rendering
- preparing before/after artifacts for review

Expected artifact:

- PNG written under `output/visual-checks/<preset>/` unless a custom path is provided

Canonical script:

- [scripts/capture_visual_state.sh](/home/bockscar/Git/pentris/scripts/capture_visual_state.sh)

Underlying harness:

- [tools/visual_capture_runner.gd](/home/bockscar/Git/pentris/tools/visual_capture_runner.gd)

## Available Visual Scenarios

Source of truth:

- [scripts/game_controller.gd](/home/bockscar/Git/pentris/scripts/game_controller.gd#L244)

Scenarios:

- `default`: normal gameplay baseline
- `active_piece`: active-piece framing with an otherwise empty board
- `ghost`: landing-shadow readability against a partial stack
- `line_clear_pause`: line-clear freeze-frame and status behavior
- `flipped_camera`: flipped-view composition and wall visibility
- `game_over`: blocked-spawn and end-state HUD behavior

## Recommended Validation Pattern

Use this order unless the task clearly needs something else:

1. Run `godot4 --headless --path . -s res://tests/test_runner.gd`.
2. Capture at least `default` for broad layout checks.
3. Capture one scenario that matches the change:
   - `ghost` for landing-shadow or stack readability
   - `flipped_camera` for camera-side or transparency changes
   - `line_clear_pause` or `game_over` for status-state UI changes
4. If the change affects feel rather than static output, use `godot4 --path .` for manual inspection.
5. For real mobile touch validation, run `./scripts/build_web.sh`.
6. Use `./scripts/serve_web.sh` only for plain LAN smoke tests.
7. Use `./scripts/serve_web_https.sh` when the phone must satisfy secure-context browser checks.
8. Before milestone commits or tags, run `git status --short`, verify `VERSION`/`CHANGELOG.md`, and rerun the headless suite.
