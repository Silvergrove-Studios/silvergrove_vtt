# Exports

All exports render through the same `MapCanvas` the editor shows, so what
you see is what you get. Exports that render need a window (the GPU does the
drawing); `./run.sh export` opens a small one for the duration.

| Target | Menu | CLI | Carries |
|---|---|---|---|
| PNG | Export → PNG image | `png <out.png> [ppx] [grid\|nogrid] [gm]` | Terrain, props, optional grid and GM layers. Transparent outside the cells. |
| Universal VTT | Export → Universal VTT | `uvtt <out.dd2vtt> [ppx] [level]` | Image, sight-blocking walls, doors as portals, lights. |
| Foundry VTT | Export → Foundry VTT scene | `foundry <out.json> [ppx]` | Scene JSON per level + WebP background. Hex grid type, walls with full semantics and heights, lights, level range, notes in flags. |
| Tiled | Export → Tiled map | `tiled <out.tmj> [ppx] [level]` | Hex tile layer + tile images, objects for props/walls/lights/notes. |
| PDF | Export → Print PDF | `pdf <out.pdf> [key=value…]` | Raster at DPI + vector grid/overlays. Tiled sheets or fit-to-page. |
| Print bundle | Export → Print bundle | `bundle <dir> [dpi] [hex_in] [level]` | `map.png`, `overlay.svg`, `map.json`, `bundle.json`. |

Elements on hidden layers (Layers panel eye off) are left out of every
export, like hidden layers in an image editor. GM-only (`hidden: true`)
elements are a different thing: they are exported as GM data where the
target has such a notion and drawn into images only when GM layers are on.

A level's backdrop image (`docs/map-format.md`, *Backdrop*) is part of every raster: PNG, the PDF's sheets, the UVTT image and Foundry's background. Tiled gets tiles and objects only.

`ppx` is pixels per cell (flat-to-flat for a hex, the side for a square). VTTs are happy around 100–200;
Foundry uses it directly as `grid.size`.

## Universal VTT

- 1 grid unit = 1 hex unit, so wall and light positions are exact. The
  format is square-native: a square map imports as is. For a hex map the
  receiving VTT must be told the grid is hexagonal (and which orientation);
  the format has no field for it. `hexmap_grid` in the file says what to pick.
- `map_size` is in whole grid units, so the image is padded to the next
  whole hex on the right and bottom.
- Dropped: walls that block only movement (fences, windows, invisible), one
  way and limited flags (become plain walls), elevation, notes, hidden flags.
- Secret doors become closed portals.
- Light `color` is written ARGB with full alpha, as Dungeondraft does.

Importing: Roll20 → page settings → Import UVTT. Foundry → install
*Universal Battlemap Importer*, scene sidebar → Import. Owlbear Rodeo →
*scene-importer* extension (with *Dynamic Fog* for walls and lights).
Fantasy Grounds Unity → Import Image → choose the `.dd2vtt`.

## Foundry VTT

1. Copy `<name>.json` and `<name>.webp` into your world's `Data` folder
   (e.g. `Data/maps/`). If you put the image somewhere else, edit
   `background.src` in the JSON to match.
2. Create an empty scene, right-click it → *Import Data* → the JSON.
3. Multi-level maps produce one JSON + image per level, named
   `<name>_<level_id>`.

What maps where:

| Ours | Foundry |
|---|---|
| `shape: square` | `grid.type` 1 |
| orientation pointy/flat × offset odd/even | `grid.type` 2 / 3 / 4 / 5 |
| hex unit | `grid.size` (px), `grid.distance` + `grid.units` |
| wall `blocks.move/sight/light/sound` | `move`, `sight`, `light`, `sound` sense types |
| `sight_mode: limited / proximity` | sense 10 / 30 |
| `door: door / secret`, `state` | `door` 1 / 2, `ds` 0 / 1 / 2 |
| `one_way: left / right` | `dir` 1 / 2 |
| wall `z: [bottom, top]` | `flags["wall-height"]` in distance units (Wall Height module) |
| level `elevation_range` | `flags.levels.sceneLevels` (Levels module) |
| light `bright`/`dim` (hexes) | `config.bright`/`config.dim` (distance units) |
| light `animation` torch / flicker / pulse | `torch` / `flame` / `pulse` |
| light `z` | `elevation` |
| notes | `flags.hexmap.notes` (Foundry notes need journal entries) |
| props | baked into the background image |
| `hidden` | `hidden` on lights; walls are always present |

Padding is 0 so pixel coordinates need no offset. Hidden props are drawn
into the image only if you export with GM layers on — by default they are
left out, which is what you want for a player-facing scene.

## Tiled

`orientation: hexagonal` (or `orthogonal` for a square grid, with
`ppx`-square tiles and no stagger keys); `staggeraxis` is `y` for pointy,
`x` for flat; `staggerindex` is our offset. `tilewidth`/`tileheight`/
`hexsidelength` are derived from `ppx`. Terrain rotation is dropped (Tiled only flips). Props,
walls, lights and notes are object layers with typed properties; nothing
is lost there.

## PDF

Options (`PdfExport.DEFAULTS`):

| key | default | meaning |
|---|---|---|
| `mode` | `tiled` | `tiled`: real-size hexes across sheets; `fit`: whole map on one page |
| `paper` | `letter` | `letter`, `legal`, `tabloid`, `a4`, `a3`, `a2` |
| `landscape` | false | |
| `hex_size_in` | 1.0 | flat-to-flat, inches (tiled mode) |
| `margin_in` | 0.5 | printer margin |
| `overlap_in` | 0.25 | how much adjacent sheets repeat, for taping |
| `dpi` | 150 | raster density; 300 for a print shop |
| `jpeg_quality` | 0.9 | −1 for lossless Flate (large) |
| `grid` | true | vector hex grid over the raster |
| `gm_layers` | false | walls, light radii, notes as vectors |
| `crop_marks` | true | on multi-sheet prints |
| `labels` | true | sheet labels and an assembly page |
| `background` | `map` | `white` makes everything outside the hexes paper |

Multi-sheet prints get an assembly page first: a diagram of the sheets with
row,column labels, and each sheet's footer says where it goes. Trim on the
hairline, overlap, tape from the top-left.

## Print bundle

For pipelines that lay out books (the rulebook pipeline uses pdf-lib):

```
<name>/
  map.png       raster, no grid, transparent outside the hexes
  overlay.svg   grid + walls + lights + notes as vectors, same pixel size
  map.json      the map document
  bundle.json   pixels, pixels_per_hex, dpi, hex_size_in, size_hex, size_in, grid
```

Place `map.png` at `size_in` inches and the map prints with hexes of exactly
`hex_size_in`; draw `overlay.svg` over it for a crisp grid at any scale.
