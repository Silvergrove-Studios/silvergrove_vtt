# Changelog

## Unreleased

- Hexmap is now one application with three modes — Editor, Table, Player —
  picked from a home screen or the command line (`./run.sh editor|table|
  player`, `--editor`/`--table`/`--player`). The editor is unchanged; the
  Table and Player are placeholders for the encounter work that follows.
- Shared state (preferences, packs, theme, recent files) moved out of the
  editor window into `App` so every mode uses the same ones.
- `./run.sh check` also fails if a portable module uses a desktop-only class.
- `./run.sh shot` now takes the output first: `shot out.png [map]`.
- The `.encounter` document (`docs/encounter-format.md`): scenes over map
  levels, tokens, an overrides overlay (doors, lights, reveals) that never
  edits the map, fog as explored cells, initiative, players. `Encounter`,
  `EncounterState` with its event vocabulary (apply returns the inverse),
  validation and player permissions, `Vision` (what tokens see through
  walls and open doors), `EncounterCommands` (undoable table actions).
  Example `examples/chapel_ambush.encounter`, built through events.
- Packs may carry a `tokens` collection for token art.
- The Table: open an encounter, add map levels as scenes, place and move
  tokens (snapped or free), click doors open and closed and lights on and
  off, reveal GM-only things, brush fog or let tokens' vision explore it,
  "See as" a player (fog, vision, hidden tokens as they get them), turn
  modes — free, DM picks, ordered by a turn system (built-in: as listed) —
  players, autosave, undo throughout. `tools/table_smoke.gd` screenshots
  it in play.
- `MapCanvas` draws an encounter scene: effective doors and lights, tokens
  (discs or pack art, owner rings, carried lights), fog by viewpoint.
- `CanvasView`: the shared pan/zoom canvas with two-finger touch; the
  editor's `MapView` is built on it.
- `TurnSystem`: the interface game systems plug into; plugins will be data
  with a sandboxed expression, not scripts.
- Example maps: doors now sit in a gap in the wall instead of on top of it,
  so opening one opens the room.

## 1.0.0 — 2026-09-19

First tagged version of Hexmap, the hex-grid encounter map editor.

- Editor: paint terrain per hex (brush, fill, variants), place props in
  continuous pixel space with snapping, walls with stored semantics (what
  they block, doors, one-way, heights), lights with wall-aware shadow
  preview, GM notes, levels, unlimited undo, autosave with recovery.
- Layers panel: folders, visibility and locking with inheritance, drag to
  reorder or regroup, group selection, rename, jump-to.
- Dockable panels with title-bar drag handles, layout remembered per user;
  four themes (Slate, Forge, Studio, Parchment) from one token set; Lucide
  icons; Inter / JetBrains Mono.
- Formats: `.hexmap` JSON (v2, layer tree); content packs as plain folders
  with three placeholder packs (woodland, swamp, dungeons & castles).
- Exports: Universal VTT (.dd2vtt), Foundry VTT scene JSON, Tiled .tmj,
  PNG, print PDF (tiled sheets or fit-to-page, vector grid and GM
  overlays), print bundle for the pdf-lib pipeline.
- Tooling: `run.sh` launcher, headless CLI export, contact sheets, example
  generator, 3,700+ unit checks, CI.
