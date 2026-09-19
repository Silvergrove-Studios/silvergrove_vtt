# The `.hexmap` format

A map is one JSON document. It is the product; the editor is one reader of
it, exporters are others, and a Node script in a rulebook pipeline can be a
third. It is meant to live in git next to the content it illustrates, so it
is plain text, stable in key order, and never embeds image data.

## Two coordinate systems

**Canvas** — continuous, Cartesian, in *hex units*. One hex unit is the grid
size: the flat-to-flat width of a hex. The origin is the top-left corner of
the bounding box of the top-left cell, x right, y down. Props, walls, lights,
notes and everything an artist positions by hand live here. A position is a
pair of floats and is never tied to a cell.

**Cells** — discrete, axial `(q, r)`. Terrain lives here. `HexGrid`
converts between the two (`hexmap/core/hex_grid.gd`), and is the only code
that knows how.

`reference_ppx` is the pixel density the map was authored at (default 256
pixels per hex). It is a display convenience: the editor shows canvas
coordinates to artists as pixels at this density and nudges by one such pixel.
Nothing in the file depends on it — exporters render at whatever density they
are asked for.

Elevation and heights are also in hex units, so "one hex up" means the same
thing as "one hex across". Exporters multiply by `grid.distance` to get game
units.

## Document

```json
{
  "format": "silvergrove.hexmap",
  "version": 1,
  "id": "6f1c0e2a-…",
  "name": "Ruined Chapel",
  "grid": {
    "orientation": "pointy",
    "offset": "odd",
    "columns": 24,
    "rows": 16,
    "distance": 5,
    "units": "ft"
  },
  "reference_ppx": 256,
  "style": {
    "background": "#1c1a17",
    "grid_color": "#00000066",
    "grid_width": 0.012
  },
  "packs": { "woodland": "0.1.0", "dungeons_and_castles": "0.1.0" },
  "levels": [ { …level… } ],
  "meta": {
    "author": "",
    "description": "",
    "created": "2026-09-19T18:04:00Z",
    "modified": "2026-09-19T18:40:12Z"
  },
  "ext": {}
}
```

- `grid.orientation`: `pointy` (horizontal rows, alternate rows shifted
  right) or `flat` (vertical columns, alternate columns shifted down).
- `grid.offset`: `odd` or `even` — which rows/columns are the shifted ones.
  Together these are Foundry's HEXODDR / HEXEVENR / HEXODDQ / HEXEVENQ.
- `grid.distance`, `grid.units`: what one hex means in the game. Display and
  export only; the map holds no rules.
- `style.grid_width` is in hex units (0.012 hex ≈ 3 px at 256 ppx).
- `packs`: every content pack referenced, with the version it was authored
  against. A missing pack is a warning and a placeholder, never a failed load.
- `ext`: reserved for tools that need to stash something. Empty by default.

## Level

A level is a floor. Every map has at least one. Levels share the grid.

```json
{
  "id": "ground",
  "name": "Ground floor",
  "elevation_range": [0, 2],
  "terrain": { "0,0": { "t": "dungeons_and_castles:flagstone", "v": 2, "rot": 0, "z": 0 } },
  "props": [ … ],
  "walls": [ … ],
  "lights": [ … ],
  "notes": [ … ]
}
```

`elevation_range` is `[bottom, top]` in hex units; a level with several
storeys of headroom just has a taller range.

### Terrain

Keyed by `"q,r"` (axial). Missing cells are bare background.

| key | type | meaning |
|---|---|---|
| `t` | `pack:terrain` | terrain asset |
| `v` | int | variant index into the asset's texture list |
| `rot` | int 0–5 | rotation in sixths of a turn |
| `z` | number | elevation of this cell's floor, hex units (default 0) |

### Prop

```json
{ "id": "p_8f3a", "asset": "dungeons_and_castles:end_table",
  "pos": [3.71, 2.18], "rot": 15.0, "scale": 1.0, "flip": false,
  "z": 0, "height": 0.3, "layer": "objects", "tint": "#ffffff", "hidden": false }
```

- `pos` is the asset's anchor point on the canvas, in hex units. Floats.
- `rot` in degrees, `scale` is uniform, `flip` mirrors horizontally.
- `z` is the bottom of the prop above the level floor; `height` its extent.
- `layer` orders drawing: `ground` (rugs, stains) < `objects` < `overhead`
  (canopies, beams). Within a layer, list order is draw order.
- `hidden`: GM-only, exported as such where the target supports it.

### Wall

A wall is a polyline with per-segment behaviour. Semantics are stored, not
a style name, so exporters do not have to guess.

```json
{ "id": "w_1b2c", "points": [[4.0, 2.31], [5.0, 2.31], [5.5, 3.17]],
  "blocks": { "move": true, "sight": true, "light": true, "sound": true },
  "sight_mode": "normal",
  "door": "none", "state": "closed", "one_way": null,
  "z": [0, 1], "style": "dungeons_and_castles:stone_wall", "hidden": false }
```

- `blocks`: which things this wall stops.
- `sight_mode`: `normal` | `limited` (Foundry "terrain wall": see one past)
  | `proximity` — only meaningful when `blocks.sight` is true.
- `door`: `none` | `door` | `secret`. A door wall is a single segment.
- `state`: `closed` | `open` | `locked` (doors only).
- `one_way`: `null` | `left` | `right` — blocks only from one side, sides
  named by the right-hand rule walking from the first point.
- `z`: `[bottom, top]` in hex units. `[0, 1]` is a one-hex-high wall.
- `style`: optional wall asset for drawing; has no effect on export semantics.

Common presets the editor offers, in these terms: **wall** (blocks all),
**door**, **secret door**, **window** (blocks move + sound only), **fence**
(blocks move only), **terrain** (sight limited), **invisible** (blocks
move only, not drawn), **ethereal** (blocks sight only).

### Light

```json
{ "id": "l_9d0e", "pos": [7.5, 4.04], "z": 0.5,
  "bright": 2.0, "dim": 4.0, "color": "#ffb060", "intensity": 1.0,
  "angle": 360, "direction": 0, "shadows": true, "animation": "torch", "hidden": false }
```

`bright` / `dim` are radii in hex units. `angle` < 360 makes a cone facing
`direction` degrees. `animation` is a hint (`torch`, `pulse`, `flicker`,
`none`); targets that have it use it.

### Note

```json
{ "id": "n_44aa", "pos": [2.5, 2.0], "title": "Collapsed pew", "text": "…", "gm_only": true }
```

## What is not in the file

- Undo history. The editor keeps it in memory for the session and writes an
  autosave sidecar (`name.hexmap.autosave`) so a crash loses nothing.
- View state (camera, zoom, tool).
- Rules. Movement costs, cover, damage — none of it. Maps are reused across
  game systems; rules belong to the system, or to an encounter document.
- Tokens. An **encounter** (`.encounter`, not yet built) references a map and
  adds tokens, initiative, and notes. One map serves many encounters.
- Image data. A map that needs unique art is a **bundle**: a directory
  `name.hexmap/` holding `map.json`, `thumbnail.png` and `assets/`. Assets
  are referenced as `local:filename.png`.

## Versioning

`version` is the schema version. Readers must accept older versions and
upgrade in memory; the editor rewrites the current version on save.
