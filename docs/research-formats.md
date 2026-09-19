# Formats and VTTs — what we build against, and why

Research done September 2026 for the encounter-map editor. The question was:
which digital formats do tabletop tools actually consume, which of those
carry hex grids and dynamic lighting, and what is safe to depend on for
internal commercial use.

## The landscape

Roll20 still has the largest total user base (15M+ accounts), but Foundry VTT
has the largest share of *active* D&D play — a 2026 survey put Foundry at
~64% install share among D&D players, and it was the biggest bloc at Gen Con
2026. Fantasy Grounds Unity holds the rules-automation crowd. Owlbear Rodeo
is the dominant free/lightweight option and has grown a real extension
ecosystem. Alchemy, Talespire and Demiplane exist but do not import
third-party map data in any standard way.

For hex play specifically, Foundry is the one to satisfy: it has native
hexagonal grids in four orientations, hex-aware measurement and templates,
and its wall/light model is the richest. Roll20 supports hex grids but its
dynamic-lighting import is square-grid shaped. Owlbear Rodeo's fog supports
hex grids; its importers accept UVTT and Foundry data.

## Interchange formats

### Universal VTT v1 (`.dd2vtt`, `.uvtt`, `.df2vtt`) — target

Introduced by Dungeondraft (Megasploot). A JSON file carrying a base64 PNG
of the map plus `resolution` (grid size and pixels-per-grid),
`line_of_sight` (wall polylines in grid units), `objects_line_of_sight`,
`portals` (doors: position, bounds, rotation, closed), `lights` (position,
range, intensity, ARGB colour, shadows) and `environment`.

Consumed by: Roll20 (native since 2025), Fantasy Grounds Unity (native),
Arkenforge (native), Foundry via the free *Universal Battlemap Importer*
module, Owlbear Rodeo via the *scene-importer* extension feeding *Dynamic
Fog*, EncounterPlus, MapTool. It is the lowest common denominator and the
one thing every VTT user knows how to import.

Limits: square grid only (no grid-type field), no wall semantics beyond
"blocks" and "door", no one-way or terrain walls, no elevation. We export
it with our hex-unit coordinates as the grid unit and an extra `hexmap_grid`
key that standard importers ignore.

### Universal VTT v2 — watch, do not target

A July 2026 proposal (`TheGeolama/uvtt-v2-specification`, Apache-2.0): a
zipped container with `manifest.json`, `geometry.json`, `entities.json` and
detached assets; hex and isometric grid types; walls with Z bounds and
material; one-way visibility by right-hand rule; AES-encrypted premium
packs. Not from Dungeondraft's author, zero adoption as of September 2026.
Our wall `z`, `one_way` and level `elevation_range` fields map onto it
directly if it takes off.

### Foundry VTT scene JSON — target

A Scene's *Import Data* accepts the document JSON that *Export Data*
produces. Relevant pieces, stable v12 → v14:

- `grid: {type, size, distance, units, style, thickness, color, alpha}`.
  `type` is `CONST.GRID_TYPES`: GRIDLESS 0, SQUARE 1, HEXODDR 2, HEXEVENR 3,
  HEXODDQ 4, HEXEVENQ 5. "R" types are row-based (pointy-topped hexes),
  "Q" column-based (flat-topped); odd/even says which rows/columns are
  shifted. `size` is the flat-to-flat width of a hex in pixels — the same
  measure our hex unit uses.
- `walls[]`: `c: [x0,y0,x1,y1]`, `move` (0 none / 20 normal), `sight`,
  `light`, `sound` (0 none / 10 limited / 20 normal / 30 proximity /
  40 distance), `dir` (0 both / 1 left / 2 right), `door` (0/1/2 = none /
  door / secret), `ds` (0 closed / 1 open / 2 locked), `threshold`, `flags`.
  In v14 the sense constants were renamed `EDGE_SENSE_TYPES` /
  `EDGE_DIRECTIONS` with the same values.
- `lights[]`: `x, y, elevation, rotation, walls, vision, config: {bright,
  dim, angle, color, alpha, luminosity, animation: {type, speed, intensity},
  darkness: {min, max}, …}`. Radii in scene distance units.
- Wall heights are not core; the *Wall Height* module reads
  `flags["wall-height"].{top,bottom}`, and *Levels* reads
  `flags.levels.sceneLevels`. Our exporter writes both.

Padding: Foundry offsets embedded documents by the scene padding, rounded to
grid multiples in a hex-specific way. We export `padding: 0` so coordinates
are exact; add padding in Foundry afterwards.

### Tiled (`.tmj` / `.tmx`) — target

Open-source map editor with a documented, stable format and readers in
every game engine. Hexagonal maps use `orientation: "hexagonal"`,
`staggeraxis` (`y` for pointy rows, `x` for flat columns), `staggerindex`
(`odd`/`even`) and `hexsidelength`. Terrain becomes a tile layer over an
image-collection tileset; everything else becomes objects with properties.
Tiled cannot express 60° tile rotation, only flips, so terrain `rot` is lost.

### Dungeondraft (`.dungeondraft_map`, `.dungeondraft_pack`) — not a target

Readable JSON, but proprietary and square-grid only; the asset pack format
is a Godot 3 PCK. Its ecosystem of asset packs is the model for how content
packs get organised (terrain / objects / walls / lights / paths), which
informed `docs/pack-format.md`, but we neither read nor write it.

### Others considered

- **Owlbear Rodeo** has no file format of its own for import; it takes UVTT
  and Foundry via extensions. Covered.
- **Roll20** exposes no scene export; it imports UVTT. Covered.
- **Fantasy Grounds Unity** imports `.dd2vtt` natively. Covered.
- **Hex Kit, Worldographer, Wonderdraft, Inkarnate, Campaign Cartographer**:
  proprietary formats, image export only, and regional rather than
  encounter scale. Not relevant to interchange.

## Print

PDF is the deliverable for physical play and for figures in the rulebooks.
Options in Godot: PDFium GDExtension (Apache-2.0, heavy, made for reading),
GodotHaru/libharu (zlib-style licence, a native build per platform), or a
small writer of our own. The PDF 1.5 subset we need — pages, Flate/JPEG
images with soft masks, paths, Helvetica text — is a few hundred lines of
GDScript with no native dependency and no per-platform build, so that is
what `hexmap/io/pdf_writer.gd` is. Output is validated with Ghostscript.

The rulebook pipeline in `ttrpg_work_test/pdf` uses pdf-lib (MIT, Node).
The *print bundle* export (PNG at a chosen DPI + SVG overlay + JSON) exists
so that pipeline can place maps in books without going through our PDF.

## Licences

Everything depended on is permissive: Godot (MIT, including its thorvg SVG
rasteriser), the PDF specification (ISO 32000, freely implementable), the
Tiled format (documented, CC-BY/BSD tooling), UVTT v1 (an open de facto
format with no licence claim), UVTT v2 spec (Apache-2.0). No Foundry code is
used or redistributed; we only write documents in its schema.

## Sources

- Roll20 UVTT support: https://help.roll20.net/hc/en-us/articles/41643201127831-Universal-Virtual-Tabletop-UVTT-Support
- UVTT explained (Arkenforge): https://arkenforge.com/universal-vtt-files/
- UVTT explained (Text to Tabletop): https://www.texttotabletop.com/blog/what-is-a-dd2vtt-file
- Dungeondraft UVTT export guide: https://dungeondraft-encyclopaedia.gitbook.io/guide/final-steps/exporting-your-map/universal-vtt
- Roll20 UniversalVTTImporter script: https://wiki.roll20.net/Script:UniversalVTTImporter
- MapTool Dungeondraft import: https://wiki.rptools.info/index.php/Import_Dungeondraft_Map
- UVTT v2 proposal: http://universalvtt.org/ and https://github.com/TheGeolama/uvtt-v2-specification
- Foundry GRID_TYPES (v11 docs): https://foundryvtt.com/api/v11/enums/foundry.CONST.GRID_TYPES.html
- Foundry HexagonalGrid (v12 docs): https://foundryvtt.com/api/v12/classes/foundry.grid.HexagonalGrid.html
- Foundry GridHex (v14 docs): https://foundryvtt.com/api/classes/foundry.grid.GridHex.html
- Foundry Scene document (v13 docs): https://foundryvtt.com/api/v13/classes/foundry.documents.Scene.html
- Foundry constants via foundry-vtt-types: https://github.com/League-of-Foundry-Developers/foundry-vtt-types
- Owlbear Rodeo scene-importer: https://github.com/Eppinguin/scene-importer
- Owlbear Rodeo Dynamic Fog: https://github.com/owlbear-rodeo/dynamic-fog and https://docs.owlbear.rodeo/extensions/reference/dynamic-fog/
- Tiled JSON map format: https://doc.mapeditor.org/en/stable/reference/json-map-format/
- Tiled TMX format: https://doc.mapeditor.org/en/stable/reference/tmx-map-format/
- VTT market 2026: https://www.enworld.org/threads/foundry-vtt-year-in-review-2026-most-popular-game-systems.719217/ , https://gmcrafttavern.com/foundry-vs-roll20-owlbear-2026/ , https://www.hipstersanddragons.com/best-virtual-tabletops/
- PDF in Godot: https://github.com/aliarcanakgun/pdfium-gde , https://godotengine.org/asset-library/asset/4838 (GodotHaru)
