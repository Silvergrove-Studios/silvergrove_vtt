# Campaign first: the Table as a campaign the DM runs, not a file the DM opens

Written 2026-09-21. The Table today opens straight into an *encounter*
document; a campaign is a side pane you can attach to it. That is
backwards from how every group actually plays, and from how D&D Beyond,
Roll20, Foundry and Fantasy Grounds are organised: a DM keeps a
**campaign** — the players, their characters, the NPCs, the notes and
handouts, the maps — and *from* it runs sessions and launches fights.
This plan turns the Table around. The `.campaign` format, sessions,
banking, the journal and the rulesets' sheets already exist; what changes
is what the DM sees first and where things live.

## 1. How people use these tools

Three journeys, each written as what the person does, not what the app
has. Everything in §3 exists to serve one of them.

**The DM between sessions (prep).** Opens the campaign. Looks over the
party: who is hurt, who levelled, what Ana prepared, whether Ben's
inventory has the key. Fixes a sheet the player got wrong. Adds the two
NPCs the party will meet (from the compendium, or homebrew), writes the
notes for the next scene and a handout for the players to find. Sets
up the fight: the map, which creatures, roughly where, hidden. Marks on
the regional map where the party is and where that fight is. Closes the
campaign; everything is saved. Nothing here needs a session, a host, or
a phone connected.

**Session night.** Opens the campaign, presses *Start session*. The
table is hosting; the join code is on screen. Players join from their
phones and see their own sheets at once — the ones from last week,
hurt or rested as they were left. The DM shows the regional map, moves
the party marker, advances the clock, hands out the handout. At the
cave, the DM launches the prepared fight: the map appears with the
creatures placed, initiative is rolled, the round runs — everything the
plugin does today. The fight ends; the DM returns to the regional map;
the goblins are gone, the loot and the wounds stay. *End session*: the
recap, and the campaign is written back. Closing the window mid-session
loses nothing.

**A player between sessions.** Opens the Player app; their character
from the last session is on the device. They can read it. Editing it
needs the rules, which run on the Table — so between sessions the sheet
is read-only on the phone, and the DM's campaign window is where sheets
are managed. (Letting the phone run the rules against a saved copy is a
later step; it is noted, not planned here.)

## 2. What is wrong today, concretely

- **Entry.** Home → Table opens an empty encounter. A campaign is *New
  campaign…* in a File menu, then *Start session* in a side pane. A DM
  who does not know the format never finds it.
- **Sheets need a fight.** The plugin's sheets, rolls, rests and
  level-ups run through the kernel on the encounter; with no encounter
  loaded there is no kernel, so there is no way to look at or fix a
  character between sessions.
- **Two documents, one game.** The `.encounter` is the unit of work and
  the `.campaign` is banked into from it. A DM thinks the other way
  round: the campaign is the thing, a fight is an evening's scene in it.
- **No prepared fights.** A fight is built live: spawn creatures from
  the Compendium panel, place them, hide them, roll. Prep happens under
  time pressure at the table.
- **No regional map.** Scenes exist, but nothing links a place on one
  map to a fight on another; travel is the DM narrating and swapping
  scenes by hand.
- **Notes are a pane in the fight.** Rulings, handouts and notes live in
  the encounter's log and are journaled on banking; there is no place to
  write the next scene's notes before the session.

## 3. The shape after

**One document.** The campaign *is* the live document. Opening a
campaign loads it into a kernel (the same `EncounterState` and
`RulesKernel` the fight uses) with the campaign's actors, resources,
tracks, clock and state, so every sheet, roll, rest and edit works
between sessions exactly as it does during one, undoably. What used to be
the `.encounter` becomes the campaign's runtime state, autosaved; a
*session* is a span of it between *Start session* and *End session*,
with a checkpoint at each end and a recap. Fights are **scenes** of the
campaign, as they already are of an encounter. `Campaign.begin_session`
and `bank` stop being the way state moves and become the session
ritual: the session counter, the checkpoint, the journal stamp, the
recap. The `.campaign` file keeps its format; it gains the fields in §4.
Old `.encounter` files still open (as a campaign of one session) so
nothing is lost.

**The Table opens on the campaign.** Home → Table shows the campaign
picker (recent campaigns, New, Open); the window is the campaign, with
these panes (docked, as today's are):

| pane | what the DM does there | built from |
|---|---|---|
| **Party** | every player character: the plugin's sheet as the GM sees it, editable; roll, rest, level up, give an item, prepare spells; assign to a player; import a character file; retire | the rulesets' `sheet` views (already rendered on the Table for the GM), the plugin's actions |
| **NPCs** | the persistent NPCs and companions: add from the compendium (`spawn` without a scene), homebrew, notes on each; the same sheet | Compendium panel's entry actions, actors of kind `npc`/`companion` |
| **Notes** | notes and handouts written ahead of time, with audience and tags; *hand out* sends one to the players' phones now; rulings from play land here; search | the journal (`kind`, `audience`, `tags`), the `handout` log entry |
| **Maps** | the campaign's maps (battle and regional) and the **prepared encounters**: a map, a level, creatures with counts and cells, hidden by default, notes; *Launch* makes it a scene; a regional map's **places** link to encounters or other maps and to notes; the party marker | scenes, `spawn`, the map's notes, a new `encounters` list in the campaign |
| **Session** | Start / End session, the join code and address, who is connected, the clock and calendar, checkpoints, the recap | Players panel, Campaign pane, `HostSession` |
| **Rules** | the rulesets in play and their settings for this campaign, the packs added, attribution | Rules panel, `plugins` and `packs` in the campaign |

The fight's panes (Scenes, Tokens, Inspector, Turns, Compendium) stay
as they are and come forward when a scene is shown; the canvas shows
the active scene — a regional map most of the evening, a battle map
during a fight, nothing between sessions if the DM prefers.

**Players' phones.** Joining a campaign that is hosting shows the
sheet at once (it persists), the campaign's status view when no scene
is shown (a *hub*: the party, the clock, the notes handed out, the
turn order when there is one), and the scene the DM shows. Nothing in
the Player client's protocol changes; what the Table projects does.

## 4. Format changes (`.campaign` v1 → v2, all additive)

```json
"maps":       [ { "id": "m_reach", "path": "maps/reach.hexmap", "role": "regional" | "battle", "name": "…" } ],
"encounters": [ { "id": "enc_cave", "name": "The cave mouth", "map": "m_cave", "level": "ground",
                  "creatures": [ { "entry": "goblin-warrior", "count": 3, "cell": "7,8", "hidden": true, "name": "" } ],
                  "notes": "…", "played": [ 4 ] } ],
"places":     [ { "id": "pl_cave", "map": "m_reach", "cell": "12,5", "name": "Cave mouth", "encounter": "enc_cave" | "map": "m_x", "note": "j_12" } ],
"party":      { "map": "m_reach", "cell": "11,5" },
"notes":      [ …the journal, unchanged; a note written in prep is a journal entry with no session yet… ],
"sessions":   [ { "n": 4, "started": "…", "ended": "…", "recap": "…", "encounters": ["enc_cave"] } ],
"runtime":    "reach.encounter"     (the live state beside the campaign file; autosaved; absent = fresh)
```

`encounters` (prepared) replaces the old informational list of session
files, which moves to `sessions[].file` for old campaigns. A campaign
opened from a v1 file is upgraded in memory and written as v2 on save.

## 5. Steps

Each step ends with `check` and `test` green, the four workflows green
at the milestone commits, and the docs changed with it. The plugin's
session tools (`ruleset-dnd5e/tools/*.gd`) run against each step, and
grow a *campaign journey* script that plays §1 end to end.

| step | change | proven by |
|---|---|---|
| **C1 The campaign is the document** | `TableContext` opens a campaign into a live kernel (actors, resources, tracks, clock, state loaded as `begin_session` does today, but without a session); autosaves the runtime beside it; *Start/End session* become the ritual (counter, checkpoint, recap, journal stamp) and no longer move state; closing the window saves. `.encounter` files open as a one-session campaign. Format v2 reader/writer with upgrade. | `campaign.gd` tests: open → kernel has the actors with their resources; edit a sheet with no session → saved; start/end session → counter, checkpoint, recap; a v1 file upgrades; an old `.encounter` opens |
| **C2 Campaign-first shell** | Home → Table opens the campaign picker (recent, New, Open); the window's title, menus and panes reorganise as in §3; the Session pane absorbs Players and the old Campaign pane; the fight panes come forward with a scene. | `table.gd`: the picker, the panes present, an old encounter opens |
| **C3 Party and NPCs** | The Party pane: each PC's sheet (the GM's projection through `ViewRenderer`, intents dispatched as the GM), the plugin's actions as buttons (the sheet already has them), assign/unassign a player, import a `.character`, retire; the NPCs pane the same for `npc`/`companion`, plus *add from the compendium*. | `table.gd`: a sheet renders for each PC, an edit lands, a roll logs, a file imports; the 5e journey script does the DM's prep review |
| **C4 Notes and handouts** | The Notes pane: write (title, body, audience `gm`/`all`/`owner:<pl>`, tags) ahead of time; *Hand out* → the `handout` log entry every phone shows; search; rulings from play appear here. | `table.gd` + `net.gd`: a note written in prep is handed out and reaches a phone with the right audience |
| **C5 Prepared encounters** | The Maps pane: the campaign's maps; an encounter builder (map, level, creatures from the compendium with count and cell, hidden, notes; the ruleset's budget when it offers one); *Launch* → a scene is added, creatures spawned and placed, the scene shown, optionally initiative rolled; *Return* → back to the previous scene, encounter-local actors removed, the encounter marked played. | `table.gd`: launch places the creatures where the builder said; return leaves the PCs' wounds and takes the goblins; the 5e journey runs a prepared fight |
| **C6 Regional map and places** | A map with `role: regional`; *places* on it (a marker on a cell with a name) linking to an encounter, another map or a note; the party marker; clicking a place on the Table offers *Launch* / *Show* / *Read*; players see the marker and the places the DM reveals. | `table.gd`: a place launches its encounter; the party marker moves and reaches the phones |
| **C7 Session and players** | The Session pane: Start/End, the join code and the addresses large enough to read across a table, connected players with their characters, the clock with *advance* and the calendar day, checkpoints, the recap. | `net.gd`: a phone joining a hosting campaign gets its sheet with no fight running; the journey script |
| **C8 Player hub** | The status projection when no scene is shown: party, clock, handouts, order; the `srd5e` status view uses it; a phone that joins between fights sees the hub. | `rules_views.gd` and the 5e journey |
| **C9 Migration, docs, punch list** | `docs/campaign-format.md` v2, `docs/encounter-format.md` (runtime), the Home blurbs, `docs/ui-punch-list.md` entries for the new panes. | docs build; the whole suite; the four workflows |

Order: C1 and C2 first (everything else hangs on the campaign being the
live document and the first screen), then C3 (the thing the DM does
most), C5–C6 (the thing that makes sessions flow), C4, C7–C8, C9.

## 6. Decisions taken here

- **The campaign is loaded into a kernel at open, always.** The
  alternative — keeping the campaign as data and spinning a kernel up
  only for a session — is what we have, and it is why sheets cannot be
  touched between sessions. The cost is a runtime file beside the
  campaign; it is the autosave a DM expects anyway.
- **Fights are scenes, not files.** A prepared encounter is a recipe;
  launching it adds a scene. There is no `.encounter` to manage; the
  old files open as campaigns.
- **The GM edits sheets through the plugin's own views and actions**,
  dispatched as the GM. No second editor is built; a ruleset that gives
  its sheet an *Edit* tab (as `srd5e` does) gets the DM's editing for
  free, and audience rules still apply to what players see.
- **Prepared encounters are ruleset-neutral**: a map, creatures by
  compendium entry with counts and cells. The ruleset's `spawn` places
  them; a ruleset that offers a budget (`srd5e` does) shows it.
- **Between sessions the phone is read-only.** Running rules on the
  phone against a saved copy is a separate design (it changes who is
  authoritative) and is left out on purpose.
