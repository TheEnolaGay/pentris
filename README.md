# pentris

Mobile-first 3D falling-block prototype built in Godot 4.

Current version: `0.1.0`

Repo-local Codex workflow docs live in `docs/codex/`. Update them whenever scripts, scenarios, controls, or validation workflows change.

## Current Scope

- Fixed orthographic corner camera over a volumetric well
- Pentomino-only gameplay in a 10 x 20 x 10 well
- Row clears across either horizontal axis, with only vertically aligned blocks falling afterward
- Queue preview, landing shadow, and drop
- Hybrid mobile-oriented controls with swipe rotation, double-tap view swap, and a simple drop action

## Run

When Godot 4 is available:

```bash
godot4 --path .
```

To run the lightweight logic checks:

```bash
godot4 --headless --path . -s res://tests/test_runner.gd
```

To render a deterministic visual scenario to PNG:

```bash
./scripts/capture_visual_state.sh default
```

The visual harness defaults to the `phone_landscape` mobile baseline (`844x390`). You can also request another preset, such as:

```bash
./scripts/capture_visual_state.sh default desktop_720p
```

To test on a phone browser using the Web export:

```bash
./scripts/build_web.sh
./scripts/serve_web.sh
```

Then open the shown LAN URL on a phone connected to the same network.

For browser features that require a secure context on the phone, use HTTPS instead:

```bash
./scripts/build_web.sh
./scripts/serve_web_https.sh
```

Open the printed `https://...` tunnel URL on the phone. Plain LAN URLs such as `http://192.168.x.x:8060` are useful for basic layout/input smoke testing, but they do not satisfy secure-context checks.

## Cloudflare Pages Deployment

This repo is prepared for Cloudflare Pages deployment through Cloudflare's Git integration. The deployable site is the Godot Web export in `build/web/`, so the Pages project should build the export inside the Pages build environment and then serve that generated folder.

One-time setup:

1. Create a Cloudflare Pages project in the dashboard.
2. Connect this GitHub repo.
3. Use these Pages build settings:
   - Production branch: `main`
   - Build command: `bash scripts/build_pages.sh`
   - Build output directory: `build/web`
   - Root directory: repo root
4. Save the project and let Pages build on each push to `main`.

The Pages build script downloads Godot 4.5 and export templates automatically when the build environment does not already provide `godot4`. It then runs the repo's headless test suite before exporting the Web build.

For a local preflight that mirrors the Pages build logic:

```bash
./scripts/build_pages.sh
```

## Git Workflow

- Use Conventional Commits by default: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Commit after a coherent change plus validation, not after every tiny edit.
- `VERSION` is the repo source of truth for the current release number.
- Record released milestones in `CHANGELOG.md` and tag them as `vX.Y.Z`.
- This repo uses `MAJOR.MINOR.PATCH`, mapped as `Proud Version.Stable Version.Patch Number`.
