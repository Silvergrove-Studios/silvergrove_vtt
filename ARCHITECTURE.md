# Architecture

## The shape of it

```
pack folders ──► PackLibrary ──┐
                               ├──► MapCanvas ──► editor view (Camera2D)
name.hexmap ──► HexMap ────────┤        │
                  ▲            │        └──► MapRenderer ──► Image ──► PNG / UVTT / Foundry / PDF / bundle
                  │            │
   Commands ──────┘  (undoable edits, History)
      ▲
   Tools (mouse/keys in hex units) ◄── MapView ◄── Main (menus, dialogs, files)
```

- **HexGrid** (`hexmap/core/hex_grid.gd`) is the only code that knows hex
  geometry: axial ↔ canvas, offset coordinates, corners, snapping, bounds.
  The canvas unit is the hex (flat-to-flat = 1.0); pixels and points are a
  multiply away.
- **HexMap** is the document: a dictionary in the shape of
  `docs/map-format.md`, plus load/save and stable serialisation. It holds
  no logic beyond that; it emits `changed(what)`.
- **LayerTree** (`hexmap/core/layer_tree.gd`) is the per-level folder/leaf
  stack: draw order for props, visibility and locking for everything.
  Pure functions over the level dictionary; `ensure()` reconciles the tree
  with the collections so files can be hand-edited.
- **Lighting** (`hexmap/core/lighting.gd`) turns walls into light-blocking
  segments and computes the visibility polygon a light reaches (rays to
  segment endpoints plus a ring, one-way walls by right-hand rule). MapCanvas
  draws each light as its radial gradient mapped onto that polygon, so the
  preview is honest about shadows. VTTs recompute from the exported walls.
- **PackLibrary** finds packs, reads manifests, and rasterises textures per
  density bucket (32…2048 px per hex). SVGs are rasterised at the density
  they are drawn at, so zooming in stays sharp and print stays crisp.
- **MapCanvas** draws one level of a map in pixels at `ppx`. It is a stack
  of child layers (terrain, prop layers, darkness, additive lights, grid,
  walls, notes, tool overlay). The same node is used by the live view and by
  exports, which is what makes exports match the screen.
- **MapRenderer** renders a region of the map to an `Image` off screen by
  putting a MapCanvas in a SubViewport, tiling at 4096 px so any size works.
- **Commands** is the only writer of the document from the editor. Each
  method commits a redo/undo pair to **History**; brush strokes and moves are
  grouped so one gesture is one undo step.
- **Tools** (`hexmap/editor/tools.gd`) are small state machines fed events
  in hex units by **MapView**, which owns the camera, pan and zoom.
- **LayersPanel** is a `Tree` over the LayerTree with drag-and-drop; it
  edits only through Commands and syncs selection both ways.
- **Palette** and **Inspector** read and write through **EditorContext**,
  the one object holding "what is open, what is selected, what is picked".
  **PropertyForm** builds forms from schemas and is reused for dialogs.
- **Exporters** (`hexmap/io/export_*.gd`) are pure functions from a map to
  a dictionary or string, unit-tested without a renderer. **Exporter** is the
  facade that renders and writes files. **PdfWriter** is a self-contained
  PDF 1.5 writer.

## Two coordinate systems, one transform

Terrain is discrete (cells, axial `q,r`). Everything else is continuous
(canvas position in hex units). Props are never attached to cells; an end
table in the corner of a hex is just a position, nudged a pixel at a time.
`HexGrid` converts both ways, and snapping is a tool option, not a data
constraint.

## Semantics over style

Walls store what they block (`move`, `sight`, `light`, `sound`), sight mode,
door type/state, one-way side and Z range. "Window", "fence" and the rest
are editor presets over those fields. Exporters therefore never guess:
Foundry gets the full model, UVTT gets what it can hold.

## What is not here on purpose

Rules (movement cost, cover, damage) — maps are reused across systems.
Tokens — an encounter is a separate document that references a map. Freeform
blended terrain — per-cell tiles are hex-native and simple; the schema does
not preclude adding a blend layer later. A 3D view — Z is stored on
everything (cells, walls, props, lights, levels) and exported, but edited as
numbers.

## Rendering constraints

Exports use the GPU, so `--headless` cannot export; `./run.sh export` opens
a small window. SVG rasterisation (thorvg) is CPU-side, so pack contact
sheets and unit tests run headless. Godot's `.godot/` class cache is
gitignored and rebuilt by `run.sh` when stale.

## Testing

`tests/run_tests.gd`: geometry round trips for all four grid variants,
document serialisation stability, history grouping, PDF structure (xref
offsets, filters, encodings), each exporter's output fields, PDF page
layout, SVG overlay, pack loading and texture rasterisation, commands with
undo/redo, and every tool driven with synthetic events. `tools/export_cli.gd
… all` is the rendering smoke test; `tools/ui_smoke.gd` screenshots the UI.
PDFs are checked externally with Ghostscript (`gs -sDEVICE=nullpage`).
