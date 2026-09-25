# Changelog

## Unreleased

The team's notes on making a character in the third playtest
(`docs/playtest-3.md`, T1–T6), on the web screens and the plugin API.

- **A wizard that follows the answers.** A step or a field can depend on
  what was chosen before (`if`, and `{expr}` properties that see
  `@values` and `@chosen`, the record an answer picked: the class, with
  its skill choices and spell counts). *Next* waits until the step is
  right and says what is missing; a field can be `required` and carry
  `help`.
- **Picking from a list with descriptions** (`choose`): skills, spells,
  equipment packages: a counter that counts down, what is had already
  ticked and locked, nothing past the limit, a "?" for an entry's card.
- **Ability scores** (`scores`): a point buy with − / + that cannot go
  wrong and the points left in view, a fixed array or rolled numbers
  given once each, or typed; what each stat is for, the key ones marked,
  a suggestion, a background's increases, the final scores and their
  modifiers.
- **Rules settings** on the DM's screen: each ruleset's settings as a
  choice, a switch or a number (an enum's `enumNames` label its
  choices); a change reloads the rules and every screen follows.
- **Leaving and coming back** (a bug): a player whose connection drops —
  a phone in another app — stays on their screen and rejoins by itself
  (only a refused join goes back to the join screen); a reload returns
  to the same player and tab, and a wizard keeps its step and answers.
- **Rules text reads well**: the SRDs' tables are drawn as tables (web
  and the Table), with their captions. Cards can have a `title` (with
  room for an icon), labelled `facts` and `tags`.
- A picker's query can be worked out from the data (a class's spells up
  to the level it casts), with a line under each name (`sub`) and a "?"
  (`detail`).
- A `field` on a sheet shows its value when its tab opens and follows it
  as the table changes it (it showed nothing after a tab switch).

## 2.3.1 — 2026-09-25

After the DM's first notes in the third playtest (`docs/playtest-3.md`).

- **Maps without a grid.** *Show the grid* in Map settings: off for a map
  painted as a picture, a region say, where travel is not counted in
  cells (the DM of the third playtest: a regional map may be hex when
  travel is measured, but for a lot of campaigns it should have no grid
  at all). Its cells still place things, unseen; the editor, the Table,
  the web screens and the SVG and PDF exports draw none, and a token
  dropped on it stays where it was let go.
- The DM's next step names what the adventure says to read first by its
  own title (*Open “Introduction”*), not always *Start here*.
- The web screens' map opens showing the whole map: it could fit itself
  to a made-up size before the page had measured its own, and open small
  in the middle. It stays fitted when the window or a pane changes size,
  until someone pans or zooms.

## 2.3.0 — 2026-09-25

The web Table: the response to the second playtest (`docs/playtest-2.md`,
`docs/playtest-3.md`): Hexmap runs the game and serves the screens people
look at as web pages. The DM's screen opens in a browser on the computer
that runs the game; players open an address or scan a code on any phone
or computer, with nothing to install.

- **The DM's screen** (browser): the book on the left — the campaign's
  contents in the DM's own folders, and the rules — with cards that read
  well (a picture, boxed read-aloud text, the DM's notes, who is there)
  and pop out into a window of their own; the map the players see in the
  middle (drag to pan, wheel or pinch to zoom, tap a place for its card);
  the party, *Ask for a roll*, and the chat and rolls on the right. *Show
  the players* on a card. A fight: *Start the fight* on its place, a bar
  over the map (round, whose turn, *Next turn*, *End the fight*), the
  order, stat blocks, targets picked on the map with a banner that says
  so. A next-step note addressed to the DM, and the rules' questions to
  the DM. *Invite players*: a code to scan, the address, a player's
  screen on the same computer.
- **The players' screens** (browser, phone or computer): join by name or
  a tap; the map through their characters' eyes (following their token,
  or the party on the region); their character (or the character maker);
  the table (whose turn, questions for them, rolls to help); chat —
  everyone, the DM, some players, privately between players — and the
  Journal. What the DM shows comes up over everything.
- **The Hexmap window** while a game runs: that it runs, *Open the DM's
  screen*, where players join, who is here; the full Table a press away.
- **Chat** is kept in the campaign, with the rolls.
- **Home and Run a game** restyled: names in a display face (Fraunces),
  choices as cards, adventures with their covers. A campaign package may
  carry a cover.
- A launched fight brings the party's tokens onto its map.
- A map's backdrop picture travels with it into campaigns and packages.
- *End the fight* says loot is the DM's to give by hand.
- The host: an HTTP side door beside the WebSocket serving the web client
  (`webclient.zip`, built from `web/`), pack art and map files; joining by
  name; the DM's own screen by a token, from this computer only; scene
  snapshots filtered for each viewer.

## 2.2.0 — 2026-09-25

The Table as a DM's screen, after the first playtest: most of a session
is talk, exploring and looking things up, and the Table now leads with
that.

- **World, Fight and Prep.** A campaign opens in the World: the party on
  the left (the ruleset's party view — numbers, passives, conditions,
  *Ask for a roll*), the map in the middle, the Reference on the right.
  Launching a prepared encounter switches to the Fight (turns, tokens,
  the map tools, in ordered turns); *End the fight* comes back. Prep has
  every pane. Each mode keeps its own arrangement.
- **The session bar**: the campaign, the day, *Start / End session N*,
  the modes, every map of the campaign (shown or not), *End the fight*,
  who has joined, *How to join*; and a *Next* line that says what to do
  until the first session is under way.
- **The Reference**: one search over the campaign and the rules; the
  campaign's contents as a tree — notes for the DM, the party, places
  with their people, people, handouts, what was shown, pictures, maps,
  and the rules as a glossary. A person's and a place's card: picture,
  what the players may know, the DM's own notes, where they are, who is
  there. Selecting a marker or a character on the map opens its card.
- **Showing the players things**: *Show the players ▾* on a card — to
  everyone or to one player — puts its picture and text on the phones,
  full screen, and in their Journal; the card says who has seen it;
  *Stop showing it* takes it back. The DM's notes never go. Pictures come
  from art packs (a `pictures` collection) or from a file.
- **Home** leads with *Continue “…”*, *Run a game*, *Join a game* and
  *Draw maps*; the Table's first screen finds adventures in the library
  and in Downloads, and starting one is a single dialog that leads with
  the adventure's own description. *Join a game* on a phone: tap the
  table; the network's details behind *Trouble joining?*; a player with
  no character is taken to where one is made.
- Place names under their markers; a place can be just a place (a
  village, an inn) with its own card.
- Rulesets: a `party` view kind, form choices from the view's own data,
  and a view kind this Table does not know is kept, not refused.
- **Players' notes**: on the phone, the Journal is the player's own tree
  — their notes (in folders of their own, and on the things they were
  shown), what the DM has shown them, and what other players shared —
  with a search. A note is private until shared with the DM, some
  players or everyone; the Table keeps them in the campaign and never
  shows a private one.
- **The DM's own contents**: folders of your own in the Reference pane's
  contents, nested, named and renamed; sections renamed and reordered;
  things filed by dragging or from their card; rules pinned into a folder.
- A package never carries a group's play: players' notes, what was
  shown, what the sessions banked.
- Fixed: a package could be started over a campaign of the same name.
- Fixed: a Table that ended without closing (killed, crashed) left its
  Bonjour registration running, and phones listed a table that was not
  there; a watchdog now stops it.

## 2.1.0 — 2026-09-24

Campaigns you can download and hand on: a campaign package carries an
adventure whole — its maps, its content, the art its maps are drawn
with, and the rules it was tested with — and a DM starts one on a table
that has installed nothing. And a campaign's content is its own.

- **Campaign packages** (`.campaignpkg`, one zip). *New from a package…*
  checks every file against the SHA-256s it carries, shows what is
  inside and under which licences, then copies it into a campaign folder
  of your own (under `Documents/Hexmap/Campaigns`); the package is never
  written to. *Export as a package…* makes one from your campaign — the
  first export makes the campaign that package's working copy, later
  ones bump its version and keep a changelog — carrying the rulesets it
  plays and the art its maps use, and refusing art whose licence does
  not allow it to be passed on. A newer version of the package a
  campaign came from is offered with a report of what would change, and
  never applied by itself. *Duplicate this campaign…* copies one, or
  starts it fresh for another group.
- **A campaign parses its own content and nothing else**: the rulesets
  it names (a ruleset's packs may depend on the campaign's settings, so
  a 2024 5E campaign reads only SRD 5.2.1), their packs, its own packs
  and its own `art/`. Adding a map copies it and its art in. Homebrew
  and imports are written into the campaign.
- **Turning content off and importing it.** An entry can be turned off
  for a campaign — hidden from every search, picker and wizard, never
  deleted — and a pack or a file of entries imported at any time,
  checked against the ruleset's schemas. Form and wizard choices come
  from the compendium live, so what is off and what was imported show
  where characters are made.
- **The content contract**: a ruleset declares its `content_api` and a
  pack the one it was written for; `./run.sh schemas` publishes a
  ruleset's collection shapes as JSON Schema; fields that name other
  entries are checked on import.
- **Looking things up**: entries read as cards (a ruleset draws its own),
  in the Compendium pane, in *View → Look up…* (Ctrl/Cmd+L), and on a
  phone from a sheet's "?" buttons; rules text renders rich.
- Rulesets install from a zip in the Rules pane (*Install ruleset…*).
- Hexmap is open source under the MIT licence.
- Fixed: on Android a file copied from inside the app arrived empty.

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
