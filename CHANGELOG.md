# Changelog

## 2.0.0 — 2026-09-21

The Table becomes a campaign table with rules: a DM runs a campaign
whose characters, NPCs, notes and maps persist between sessions, and the
rules of the game come from a ruleset plugin — the first is the 5E
compatible `srd5e` ruleset, installed from a zip.

- **Rulesets.** Game rules are plugins in sandboxed Lua (Luau) that run
  on the Table only; players' devices receive data, never code. A
  ruleset defines actor schemas and derived sheets, actions with picks on
  the map, effects with roll-time hooks, resources and rests, turn
  systems, tracks and the clock, prompts to players and to the GM,
  content packs and homebrew editors, and declarative views (sheet,
  status, GM) the Table and the phones render. `docs/plugin-authoring.md`
  is the guide; `./run.sh plugintest <dir>` runs a plugin's own tests.
  *Install ruleset…* in the Rules pane unpacks a release zip under the
  Table's plugins folder and loads it.
- **The campaign is the document.** The Table opens on a campaign picker;
  a `.campaign` holds the players, their characters with sheets, NPCs,
  the journal, the maps and the live state, and a session is started and
  ended from the Session pane (the recap is kept per session). Panes:
  **Party** and **NPCs** (sheets as the ruleset draws them, editable by
  the DM, rolls issued from them — in secret when the DM wants), **Notes**
  (notes and handouts written ahead, handed to the phones when the moment
  comes), **Maps** (the map library with battle and regional maps;
  prepared encounters — creatures found by name, type and CR, with
  counts, cells and hidden flags — to Launch, or to Stage out of the
  players' sight and Go when arranged, and Return from; places on a
  regional map and the party marker). Old `.encounter` files open as a
  campaign. Maps are never edited from the Table.
- **Square grids** beside hexes through the whole stack (drawing, walls,
  lights, vision, movement with a diagonal rule), and **backdrop images**
  under the grid, fitted by dragging two corners or by detecting a
  printed grid.
- **The Player** shows the ruleset's sheet with its buttons, prompts and
  requested rolls, the table's status view and handouts, and a hub
  between fights; the compendium reaches phones under their audience.
- **Content packs and the compendium**: a versioned index with filters,
  ranges and facets, user packs and homebrew editors built from each
  collection's schema, character files.
- Three client roles (player, display, co-GM), checkpoints, rulings,
  bulk operations, a recap, and a plugin API audit with every finding
  recorded (`docs/plugin-api-plan.md`, `docs/plugin-api-audit.md`).

## 1.2.0 — 2026-09-20

Players find tables by themselves, across subnets, the way phones find
speakers; every build is tested on real desktops, an emulator and a
simulator; and it all fits on a phone.

- Discovery that works on a real home network: tables are Bonjour
  services (`_hexmap._tcp`) — the Table registers with the OS's mDNS
  responder — and on Android the Player asks the system's own service
  discovery (a small `NsdManager` plugin), which hears what routers
  reflect between subnets where an app's socket cannot. A table heard at
  several addresses is one entry whose addresses are ranked by evidence
  (answered a direct query, known, chosen before, packet source) and
  tried in turn on Join. Remembered tables are asked directly; the join
  screen shows its own address and a diagnostics line. The Player no
  longer opens encounter files: a player joins a table.
- One debug signing key for all Android builds, so they update in place;
  a build stamp (version, run, commit, time) on the home and join screens.
- `./run.sh table x.encounter --host --turns free` hosts from the command
  line; `./run.sh jointest host:port` joins a running table and plays a
  move; `tools/android_join_test.sh` does the same from a phone or an
  emulator (`tools/android_emulator.sh` gives one on a Mac).
- Linux and Windows builds no longer load every pack twice (res://packs
  and the folder beside the executable were the same directory).
- The Player fits phones: columns shrink to the screen and scroll when it
  is shorter than they are, the UI scale never
  leaves fewer than 360 points across, the notch and gesture bar are kept
  clear, and the token bar scrolls instead of pushing buttons off the edge.
- Testing: the suite runs inside builds (self-test mode), on real macOS,
  Windows and Linux runners (headless and in each OS's exported build), on
  an Android emulator and an iPhone simulator in CI, and includes an event-log fuzz test — which found that
  undoing a fog change reordered the explored cells; they are now kept
  sorted so identical sets are identical documents.
- UI size: the app now scales with the screen (2× on a Retina Mac, the OS
  scaling on Windows — it was drawn in device pixels, half size) and the
  window opens at its designed size in points. On top of that, a UI size
  preference from 75% to 200%: View → UI size (Ctrl/Cmd+= and −) in the
  editor and table, −/+ on the home screen, A−/A+ in the Player. The map
  canvas renders at the screen's real pixels whatever the scale.

## 1.1.0 — 2026-09-19

Hexmap grows from a map editor into a table: run encounters on your maps,
and let players join from their own devices on the same network.

- Hexmap is now one application with three modes — Editor, Table, Player —
  picked from a home screen or the command line (`./run.sh editor|table|
  player`, `--editor`/`--table`/`--player`). The editor is unchanged.
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
- `TurnSystem`: the interface game systems plug into. Rulesets will be
  sandboxed Lua plugins that run only on the Table.
- The Player: pick an encounter on this device and who you are, then the
  shown scene through your tokens — fog, vision, hidden things absent —
  with drag-to-move requests answered by the turn mode ("Not your turn")
  and the view refreshed when the DM saves. Finger-first: no menus, no
  dialogs, pinch and two-finger pan. `Session` / `LocalSession` are the
  seam the network version drops into. `tools/player_smoke.gd`.
- Networking on the LAN: the Table hosts (WebSocket, JSON), hands players
  the encounter and every event, applies their requests through its own
  commands, and streams maps and pack art to devices that lack them. The
  Player finds tables by asking the network (the Table answers directly,
  which gets past phones' multicast filters) or takes a typed address.
- A release workflow that builds an Android APK and desktop zips and
  publishes them (tags, or a `dev-build` prerelease on demand). Icons and
  fonts are now "keep" imports so exported builds carry them.
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
