# Visual Style Guide

This is the visual contract for `pentris`.

The target is hybrid neon retro presentation for landscape mobile play. The goal is not literal Tron or literal NES. The goal is a clean fusion: pixel-era framing and board composition, but with electric cyan, magenta, deep midnight blue, and hot neon accents that feel luminous and synthetic without sacrificing readability.

## Theme Direction

- Design for `phone_landscape` first. Treat `desktop_720p` as a secondary validation target, not the primary canvas.
- Keep the center well as the star of the screen. Side rails should support it, not compete with it.
- Favor retro game-board framing over generic app UI. Panels should still feel like game boxes, score boards, or option boards.
- Use a hybrid neon palette:
  - deep near-black blues for backgrounds
  - electric cyan for primary structure and borders
  - magenta for secondary emphasis and contrast
  - a hot green status color for success/action states
  - cool white-cyan for primary text
- Avoid drifting into generic cyber UI. The composition should still feel game-like and framed, not like a dashboard app.

## Layout Rules

- Preserve the three-zone composition:
  - left rail for title, menu entry, and scoreboard
  - center for the playfield
  - right rail for next-piece preview and related support UI
- Maintain visible breathing room between the well and the side rails. Side panels should not visually squeeze the play area.
- Text, buttons, and preview blocks must not touch panel borders. Solve cramped layouts with spacing and container sizing before shrinking text.
- Utility controls should stay compact. Primary actions can be larger, but they should not dominate the composition.
- Overlays such as the pause board should feel centered and balanced in relation to the well, not glued to an edge.
- When something feels crowded, reduce horizontal bulk before reducing legibility.

## UI Composition Rules

- Every HUD panel must reserve explicit zones for header, content, and optional footer or caption material.
- Decorative lines, dividers, and inset frames must live in their own lanes. They must never cross through text bounds.
- Buttons must occupy dedicated action rows with clear top and bottom breathing room. Do not stack actions into title or subtitle space.
- Centered text is only acceptable inside a reserved text rect. Do not visually center text against decoration if that lets the decoration overlap the glyph area.
- Featured cards such as `NEXT` must reserve separate rows for the panel title, the framed preview content, and any optional caption.
- If a panel feels empty, redistribute the zones first. Do not solve emptiness by floating text or decoration into another zone.

## Panel Composition Patterns

- Pause and overlay boards should use a lane-based stack:
  - title row
  - optional subtitle row
  - divider lane
  - action lane
- Rail panels should use a simpler stack:
  - rail title
  - framed content card
  - optional caption row only when it has dedicated space
- Ornament is subordinate to content. If there is a conflict, move or remove the ornament before shrinking or repositioning the text.

## Typography And Hierarchy

- Keep a clear hierarchy between labels and values:
  - headers are smaller and muted
  - values are larger and visually primary
- Primary actions such as `DROP` should read louder than utility controls such as `MENU`.
- Menu and pause-board text must remain comfortably legible on `phone_landscape`.
- Do not solve clipping by making text tiny. Rebalance padding, panel width, or label length first.
- Short words and compact labels are preferred when they preserve clarity and improve rhythm.

## Panels, Buttons, And Neon Framing

- Use framed rectangular panels with visible borders and restrained shadows.
- Borders should feel luminous, not bulky. Cyan is the default structural border; magenta is the stronger accent border.
- Primary action buttons should feel distinct from utility triggers through stronger border contrast and clearer emphasis.
- The pause/options board should read as an in-world retro board, not a generic popup or OS-style menu.
- Buttons should look intentional and game-like. Avoid visual noise, but also avoid controls that become so subtle they stop reading as interactive.
- If two controls have different importance, their size, contrast, and placement should make that obvious.

## Do Not Accept

- Dividers crossing subtitle or title text.
- Text centered onto decorative rules or borders.
- Captions added without a reserved row.
- Buttons pushed upward until they visually merge with title space.
- Empty space solved by shrinking type instead of rebalancing the panel zones.
- A panel that technically fits but does not preserve readable lanes between label, ornament, and action.
- Glow or post-processing that washes out text, borders, or board readability.

## Palette Guidance

Use the current gameplay HUD palette roles as the baseline:

- background: deep midnight blue / near-black blue
- panel fill: dark blue-violet or dark navy surfaces
- primary border: electric cyan
- secondary accent border or highlight: magenta
- primary text: bright cool white / cyan-tinted white
- muted text: cooler blue-cyan
- status emphasis: hot green
- pressed or inverted action state: dark text on bright status fill

New colors should map back to one of these roles. If a new UI element needs emphasis, prefer changing contrast, border treatment, or placement before inventing a new color family.

## Display Filter Guidance

- The global display treatment should feel like `Pixel + CRT Lite`.
- Prioritize crisp pixel stepping first; CRT character is secondary.
- Scanlines, tint, and vignette should stay subtle enough that text and touch targets remain clean on a phone.
- Avoid heavy blur, strong barrel distortion, heavy bloom, or any filter that makes HUD text feel soft.
- The display filter must be easy to reduce or disable if mobile performance or readability suffers.

## Visual Review Checklist

Use this before considering a visual task complete:

- No text clipping at `phone_landscape`.
- No text or controls touching panel borders.
- No text, dividers, or decorative accents overlapping each other.
- Left rail, well, and right rail feel visually balanced.
- Utility controls do not overpower scoreboard or playfield content.
- The pause/options board feels balanced when open and remains legible in both normal and stressed states.
- The next-piece panel, scoreboard, and bottom action dock still read clearly when the board is busy.
- The neon palette reads intentionally, not like random saturated recolors.
- The display filter adds character without harming readability.
- `desktop_720p` still looks coherent, but fixes should not come at the expense of the mobile-landscape composition.

Required validation for visual changes:

1. Run the headless suite.
2. Capture at least one deterministic visual scenario that matches the change.
3. If the change affects multiple actions or a broader HUD flow, run a scripted visual playtest.
4. Review the resulting artifacts specifically for spacing, hierarchy, clipping, panel composition, palette coherence, and filter readability.

For palette or display-filter work, review at minimum:

- default / menu closed
- menu open
- one stressed state such as `game_over`

Command details live in [workflows.md](/home/bockscar/Git/pentris/docs/codex/workflows.md).

## Incomplete Visual Work

Treat the task as incomplete if any of these are true:

- clipping was avoided mainly by shrinking text
- decoration overlaps text even if nothing clips
- utility controls visually compete with the main action or the playfield
- spacing feels desktop-first rather than tuned for landscape mobile
- the UI technically works but no deterministic visual artifact was reviewed
- a multi-step HUD/menu flow was checked with a single static snapshot only
- the filter makes text or borders visibly muddier on `phone_landscape`

## Current Source Anchors

The current HUD palette, panel styling, material colors, and layout proportions are centralized in [game_controller.gd](/home/bockscar/Git/pentris/scripts/game_controller.gd). Use that file as the implementation anchor when changing HUD presentation, and keep this guide aligned with its intended direction rather than letting style drift accumulate over time.
