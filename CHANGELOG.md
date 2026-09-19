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
