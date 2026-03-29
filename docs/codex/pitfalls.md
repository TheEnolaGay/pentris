# Pitfalls

These are repo-specific problems Codex should avoid repeating.

## Do Not Use Headless Dummy Rendering For PNG Capture

Symptom:

- `root.get_texture()` is null during `visual_capture_runner.gd`
- capture fails under `godot4 --headless`

Root cause:

- headless dummy rendering is sufficient for tests, but not for this screenshot workflow

Correct workflow:

- use [scripts/capture_visual_state.sh](/home/bockscar/Git/pentris/scripts/capture_visual_state.sh), which runs Godot with `--display-driver x11 --rendering-driver opengl3 --audio-driver Dummy`

## Tests Passing Does Not Mean Visual Checks Are Done

Symptom:

- logic suite passes, but layout, camera framing, transparency, or shadow presentation is still wrong

Root cause:

- the headless suite validates behavior and some controller expectations, not final rendered composition

Correct workflow:

- run the test suite first, then capture the relevant visual scenarios

## Prefer The Wrapper Script Over Calling The Capture Harness Directly

Symptom:

- wrong argument shape or wrong renderer flags when invoking `visual_capture_runner.gd`

Root cause:

- the harness expects positional args after `--` and depends on a specific rendering setup

Correct workflow:

- use `./scripts/capture_visual_state.sh <scenario> [viewport_preset|output_path] [output_path]`

## Keep Scenario Docs In Sync With `prepare_visual_scenario()`

Symptom:

- Codex references stale scenario names or misses a useful validation scene

Root cause:

- scenario definitions live in code and can drift from local documentation

Correct workflow:

- whenever `prepare_visual_scenario()` changes, update `docs/codex/workflows.md` in the same task

## Web-On-Phone Testing Requires HTTP, Not A `file://` URL

Symptom:

- exported build loads incompletely or browser features do not behave correctly on the phone

Root cause:

- Godot Web exports are meant to be served over HTTP rather than opened directly from the filesystem

Correct workflow:

- run `./scripts/build_web.sh`
- then run `./scripts/serve_web.sh`
- open the printed LAN URL on the phone browser

## Debug Web Exports Exaggerate Mobile Load-Time Pain

Symptom:

- phone startup feels slower than expected
- load-time comparisons are based on a heavier debug build

Root cause:

- debug Web exports are useful for diagnosis, but they are not the best baseline for real mobile startup checks
- this repo now treats release export as the default `build_web.sh` behavior

Correct workflow:

- use `./scripts/build_web.sh` for normal phone testing
- use `./scripts/build_web.sh debug` only when actively debugging browser-side issues
- judge mobile load time primarily from the release build

## LAN HTTP On A Phone Is Not A Secure Context

Symptom:

- the phone can load the game, but the browser reports `Secure Context` failures or missing features

Root cause:

- `http://192.168.x.x:8060` is plain HTTP
- browsers generally reserve secure-context features for `https://` or the host machine's own `http://localhost`
- the phone is not the host machine, so `localhost` exceptions do not apply

Correct workflow:

- keep `./scripts/serve_web.sh` for quick LAN smoke tests
- use `./scripts/serve_web_https.sh` for secure-context mobile testing
- open the printed `https://...` URL on the phone

## Do Not Split Cloudflare Pages Between Two Deployment Systems

Symptom:

- Pages deploy behavior is ambiguous because both Cloudflare Git builds and a separate GitHub-side deploy path are configured

Root cause:

- this repo should have one authoritative deployment system
- mixing dashboard Git builds with a second upload pipeline makes failures harder to attribute and review

Correct workflow:

- use [scripts/build_pages.sh](/home/bockscar/Git/pentris/scripts/build_pages.sh) as the Cloudflare Pages build command
- keep the Pages project pointed at `build/web`
- if deployment behavior changes, update `README.md` and `docs/codex/workflows.md` in the same task

## Stock Godot Web Templates Are Too Large For Cloudflare Pages

Symptom:

- Cloudflare Pages finishes the Godot export, then rejects `index.wasm` because it exceeds the 25 MiB file-size limit

Root cause:

- the stock Godot 4.5 Web export template produces a larger `index.wasm` than Cloudflare Pages accepts for this project
- Pages can build the project, but asset validation fails after export

Correct workflow:

- keep the committed custom templates under [tools/godot-export-templates](/home/bockscar/Git/pentris/tools/godot-export-templates)
- keep [scripts/build_pages.sh](/home/bockscar/Git/pentris/scripts/build_pages.sh) pointed at the committed template directory
- if the custom template changes, regenerate the committed files and push them with the related script/doc updates
