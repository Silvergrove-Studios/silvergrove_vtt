# Architecture

## One application, three modes

Hexmap is one Godot project that runs as one of three modes. The **shell**
(`hexmap/shell/`) owns what they share — preferences, the pack library, the
theme, recent files, all in `App` — and shows one window at a time: the home
screen or a mode.

| mode | what | where it runs |
|---|---|---|
| **Editor** `hexmap/editor/` | author `.hexmap` maps and export them | desktop |
| **Table** `hexmap/table/` | a DM runs an `.encounter` on one or more maps | desktop |
| **Player** `hexmap/player/` | joins a table; sees the map through their tokens | desktop, iOS, Android, web |

Desktop builds ship all three; mobile builds ship the Player only
(`App.available_modes()`). Everything below the mode windows is shared:

```
shell/      App (prefs, packs, theme), home screen, mode switch
editor/     the Editor: panels, tools, Commands + History       desktop
table/      the Table: encounter panels and tools               desktop
player/     the Player: touch-first client                      portable
encounter/  Encounter, EncounterState, events, Vision, undo,    portable
            TurnSystem
net/        Session, LocalSession, NetSession, HostSession,     portable
            Protocol, Discovery
render/     MapCanvas, MapRenderer, CanvasView                  portable
core/       HexMap, HexGrid, LayerTree, Lighting, PackLibrary   portable
io/         exporters and the PDF writer                        desktop
ui/         theme, icons, fonts; dock panes for desktop modes
```

**Portable modules may not depend on a desk.** No `DockableContainer`,
`FileDialog`, `MenuBar`/`PopupMenu`, native menus, editor state, or shelling
out; input must work from a finger as well as a mouse (no hover-only
affordances, no right-click-only actions, no keyboard-only paths).
`tools/check_scripts.gd` (`./run.sh check`, run in CI) fails the build if
`core/`, `render/`, `encounter/`, `net/` or `player/` name one of those.
`packs/` is `.gdignore`d and so never inside a build: a Player gets its
assets from the Table it joins, into `user://packs/`.

## The editor

```
pack folders ──► PackLibrary ──┐
                               ├──► MapCanvas ──► editor view (Camera2D)
name.hexmap ──► HexMap ────────┤        │
                  ▲            │        └──► MapRenderer ──► Image ──► PNG / UVTT / Foundry / PDF / bundle
                  │            │
   Commands ──────┘  (undoable edits, History)
      ▲
   Tools (mouse/keys in hex units) ◄── MapView ◄── EditorWindow (menus, dialogs, files)
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

## Encounters: an overlay, driven by events

An **encounter** (`.encounter`, JSON like `.hexmap`) *references* maps by id
and never copies or edits them. What the DM changes at the table — a door
opened, a light put out, a prop revealed, fog lifted, tokens — is an
**overlay keyed by element id** on top of the base map. One map serves many
encounters, and re-exporting a map never loses a session.

Every change to an encounter is a **serializable event**
(`{"t": "token.set", "scene": "s_1", "id": "t_1", "changes": {"pos": [4, 2]}}`)
applied by `EncounterState.apply()`, which returns the inverse event. The
same event gives undo (`EncounterCommands` commits event and inverse to
`History`), autosave (the document is the state the log produced),
replication (hosts broadcast what `applied` announces), replay, and headless
tests. `validate()` says whether an event is well-formed against the current
state; `allowed()` whether a player may send it — a player may only move a
token they own. The Table is authoritative: players send events as
*requests*, the Table validates, applies and rebroadcasts.

`Vision` computes what tokens see from the *effective* level (overrides
merged, so an open door does not block) with `Lighting.visibility_polygon`
against sight-blocking walls; fog is the set of cells a player's tokens have
seen. `MapCanvas` takes the state as an optional input (`set_scene`) and a
*viewpoint* — the GM sees everything; a player sees what their tokens can,
fog for the rest, hidden tokens never. Editor and exports pass no state and
are untouched.

`CanvasView` is the shared canvas-under-a-camera with pan and zoom from
mouse, trackpad and two-finger touch; the Editor's `MapView` and the
Table's `TableView` add their context and hand a tool to it. Tools are
duck-typed objects (`press`/`drag`/`release`/`move`/`key`/`draw_overlay`).

## The Player and the Session

The Player (`hexmap/player/`) never touches an `EncounterState` directly:
it talks to a `Session` — the encounter as this player may see it, plus
`request(event)`, which the authority answers with "" or a reason. Today
the authority is `LocalSession`: an encounter file on this device, allowed
requests applied to its own copy, reloaded when the DM saves. Networking
is another `Session` behind the same interface; the Player UI does not
change. `PlayerWindow` is the first portable window: join screen, player
picker, then `CanvasView` with the player's viewpoint, one move tool, a
bar of the player's tokens, and the turn summary — no docking, dialogs or
menus, and nothing that needs a hover or a right-click.

## Over the network

`HostSession` (on the Table) is a WebSocket server; `NetSession` (on the
Player) is a `Session` over a WebSocket client; `Protocol` is the handful
of JSON message types between them, versioned. The Table is the authority:
a request is applied only if `allowed()` and `validate()` pass, through
the Table's own `EncounterCommands` (so the DM can undo a player's move
and it explores fog like any other), and every applied event — the DM's
or a player's — is broadcast to every client, which applies it to its own
copy. Maps and pack files stream on demand into `user://packs`, so a phone
with nothing installed draws the scene. `Discovery` multicasts (and
broadcasts, for phones that filter multicast) an announcement once a
second; the Player lists what it hears, or takes a typed address. LAN
only for now; a relay would sit between `NetSession` and `HostSession`
speaking the same protocol.

## Turns and game systems

Who may move is the encounter's `turns.mode`: **free** (any visible
token), **dm** (the DM ticks who is up), **ordered** (a turn system orders
the tokens and the Table steps through them). `EncounterState.may_move()`
is the one place that rule lives, and `allowed()` uses it for players'
requests.

Ordering is where game rules enter, so it is pluggable and Hexmap ships
only "as listed". `TurnSystem` is the internal interface (`build_order`,
`next`, `previous`); a system keeps its own state in `turns.data`, which
Hexmap stores and replicates without reading.

Whole rulesets — D&D, Vampire, whatever is being played — will be
**plugins in sandboxed Lua** (embedded through a GDExtension; the plugin
sees only the capabilities the host exposes: read state, emit events,
register stat schemas, sheets, actions and hooks, roll dice — never files,
network or the engine). Not GDScript, which would hand a plugin
everything. A plugin runs only on the Table; everything it does lands in
the encounter as events and data (`ext.<plugin_id>` on tokens and the
encounter, `turns.data` for a turn system), and its UI is declarative
schemas, so a Player client renders it without running any of it.
`TurnSystem` is one thing a ruleset registers. None of this exists yet; it
is the shape Player mode and networking are built to leave room for.

The JSON conventions both document types share — stable key order, ids,
merge-with-null-removes — live in `JsonDoc`.

Networking, when it comes, is the Table hosting directly (LAN or a forwarded
port; join by code or QR) over `WebSocketPeer` with JSON messages — the one
transport that works on every platform including web. The protocol is
client ↔ session, so a relay can be put in front of it later without
changing clients. Tokens' art comes from packs (a `tokens` collection) plus
a built-in generic set, and streams from the Table to players.

## What is not here on purpose

Rules (movement cost, cover, damage) — maps are reused across systems, and
tokens carry no stats for the same reason. Tokens in maps — they live in
encounters. Freeform blended terrain — per-cell tiles are hex-native and
simple; the schema does not preclude adding a blend layer later. A 3D view —
Z is stored on everything (cells, walls, props, lights, levels) and
exported, but edited as numbers.

## Rendering constraints

Exports use the GPU, so `--headless` cannot export; `./run.sh export` opens
a small window. SVG rasterisation (thorvg) is CPU-side, so pack contact
sheets and unit tests run headless. Godot's `.godot/` class cache is
gitignored and rebuilt by `run.sh` when stale.

## Testing

`tests/test_suite.gd` is the suite: geometry round trips for all four grid
variants, document serialisation, history grouping, PDF structure, each
exporter, packs, commands with undo/redo, every editor and table tool
driven with synthetic events, the encounter model (every event and its
inverse, validation, permissions by turn mode, vision through doors), the
windows built headless, touch on the canvas, the network host and clients
over loopback, and a fuzz test that applies hundreds of random valid
events, replicates them to a second state and undoes them all.

It runs three ways. `./run.sh test [filter]` drives it headless
(`tests/run_tests.gd`). **Self-test mode** runs the same suite inside a
build — `Hexmap -- --selftest`, or a `user://selftest` marker file — and
writes `user://selftest.txt`, on-device screenshots and `selftest.done`;
that is how an exported app, a phone or an emulator is tested. The
`android-test` workflow builds an x86_64 APK, boots an emulator, pushes the
packs, the marker and the examples with `tools/android_selftest.sh`, and
pulls the results. The `ios-test` workflow does the same on an iPhone
simulator: exports the Xcode project, builds it for the simulator with
signing off (x86_64 — Godot's simulator library has no arm64 slice, and
an Apple-silicon simulator runs it under Rosetta), and drives the
self-test through `xcrun simctl` (`tools/ios_selftest.sh`; `user://` on
iOS is the app's Documents folder). The `desktop-test` workflow runs the
headless suite on real macOS, Windows and Linux runners, then exports
each OS's own build natively and launches it with `--selftest`
(`tools/desktop_selftest.sh`: xvfb + Mesa on Linux, ANGLE on Windows) —
the binaries users download, on the OSes they run. All by hand; Android
and desktop also weekly. `ci.yml` on every push is Linux, headless.

**The join test** is the one that crosses a real network: `join_remote`
in the suite connects a `NetSession` to a Table that is actually running
somewhere, takes the welcome, maps and packs, joins, plays a move and
sees it echo. `./run.sh jointest host:port` runs it from this machine;
`tools/android_join_test.sh <apk> <host:port|--usb> <out>` runs it on a
phone (USB, via `adb reverse`, or over the wifi) or an emulator; the
`android-test` workflow hosts a Table on the runner and has the emulator
join it at `10.0.2.2`. Same script on the desk and in CI:
`tools/android_emulator.sh setup|start|stop` gives a headless emulator on
a Mac (Homebrew JDK and command-line tools, no sudo), and then
`tools/android_join_test.sh out/Hexmap.apk 10.0.2.2:47777 out/join`
joins a Table running on the same machine. A phone on USB takes `--usb`
(adb reverse) or the laptop's wifi address.

`tools/ui_smoke.gd`, `table_smoke.gd` and `player_smoke.gd` drive the
three modes and screenshot them; `tools/export_cli.gd … all` is the
rendering smoke test; `tools/check_export.gd` checks an exported pack.
PDFs are checked externally with Ghostscript (`gs -sDEVICE=nullpage`).
