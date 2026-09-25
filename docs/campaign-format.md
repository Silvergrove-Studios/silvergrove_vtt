# The `.campaign` format (v3)

A campaign is what a group keeps: the players, their characters, the
NPCs, the rulesets in play, the packs of content they have added, the
clock, the journal, the maps and the prepared encounters, and everything
a ruleset needs to remember (a resource that carries over, a faction's
standing). Since version 2 it is also the **live document**: the Table
opens a campaign into its rules kernel, so sheets, rolls and rests work
between sessions, and keeps the running state in the file's `runtime`
block (docs/campaign-plan.md). Fights are scenes of that runtime; a
session is a span of it between *Start session* and *End session*.

Same conventions as `.hexmap` and `.encounter`: one JSON document, plain
text, stable key order, no image data, meant to live in git next to the
adventure. `hexmap/encounter/campaign.gd` reads and writes it.

## Document

```json
{
  "format": "silvergrove.campaign",
  "version": 2,
  "id": "c_9b1e…",
  "name": "The Sunken Reach",
  "plugins": [ { "id": "sample.ordered", "version": "0.1.0", "settings": { "critical_on": 19 } },
               { "id": "sample.house" } ],
  "packs": [ { "id": "homebrew.reach", "path": "packs/reach", "version": "3" } ],
  "content": { "disabled": ["srd5e:classes/monk"],
               "imported": [ { "id": "some.supplement", "path": "packs/some.supplement", "plugin": "srd5e", "session": 3, "at": "…", "entries": 41 } ] },
  "package": { "id": "sunken-reach", "version": "1.2.0", "name": "The Sunken Reach", "tested_with": { … } },
  "rules_dir": "rules",
  "players": [ { "id": "pl_a1", "name": "Ana", "color": "#4f9cf6" } ],
  "actors": { "a_hero": { …actor, without derived… } },
  "resources": { "actor:a_hero": { "sample.ordered": { "hp": { "kind": "pool", "current": 6, "max": 10, "recharge": "rest" } } } },
  "state": { "ext": { "sample.ordered": { "luck": 2 } } },
  "clock": { "session": 4, "day": 12, "minute": 870 },
  "tracks": { "k_doom": { …progress track… } },
  "journal": [ { "id": "j_1", "kind": "ruling", "session": 3, "encounter": "The chapel", "text": "…", "rule": "cover", "tags": ["cover"], "audience": "gm" } ],
  "maps": [ { "id": "m_reach", "path": "maps/reach.hexmap", "role": "regional", "name": "The Reach" } ],
  "encounters": [ { "id": "enc_cave", "name": "The cave mouth", "map": "m_cave", "level": "ground",
                    "creatures": [ { "entry": "goblin-warrior", "count": 3, "cell": "7,8", "hidden": true } ], "notes": "…", "played": [4] } ],
  "places": [ { "id": "pl_cave", "map": "m_reach", "cell": "12,5", "name": "Cave mouth", "encounter": "enc_cave" } ],
  "party": { "map": "m_reach", "cell": "11,5" },
  "sessions": [ { "n": 4, "started": "…", "ended": "…", "recap": "# Session 4 …", "file": "" } ],
  "runtime": { …the live encounter document as of the last save… },
  "meta": { "author": "", "description": "", "created": "…", "modified": "…" },
  "ext": {}
}
```

Version 3 adds `content` (what the table turned off, what it imported)
and makes `packs` real: they load with the campaign. Version 2 added
`maps`, `encounters` (prepared, a recipe for a scene over
a map — version 1 listed the sessions' encounter files here; those move
to `sessions[].file` on upgrade), `places` (markers on a regional map
that link to an encounter, another map or a note), `party` (where the
party is), `sessions` and `runtime`. Every other field is as before.

- `plugins`: the rulesets this campaign runs, in order. The Table loads
  what it names first, in that order (a base always before what layers
  over it, whatever the list says), then the rest of the installed
  plugins; `settings` are paths into the plugin's declared settings,
  over its defaults: rules variants, automation levels.
- `packs`: content packs beyond what the plugins ship, by path relative
  to the campaign file, loaded when the campaign opens — after the
  plugins' own packs and the table's `user://content`, so a campaign's
  content wins by id. `ContentImport` adds to this list.
- `content.disabled`: entries this table does not use, as
  `"<plugin>:<collection>/<id>"`. Suppression, never deletion: the entry
  stays in its pack and still answers by id (a character built on it
  keeps working), but it is offered nowhere — no search, no picker, no
  wizard — until it is turned back on. The Compendium pane's *Use at
  this table* is the switch; *Show what is off* lists them.
- `content.imported`: what was brought in after the campaign started and
  when (`session`), so a campaign can explain itself later.
- `package`: the campaign package this campaign was started from, and
  what that package was tested with (`docs/campaign-packages.md`).
  Absent for a campaign made from nothing.
- `rules_dir`: a folder in the campaign that holds rulesets of its own
  (a package carries the rules it was tested with under `rules/`). They
  load for this campaign and win over an installed ruleset of the same
  id, so a campaign plays the rules it came with.
- `players`: the group. A session's encounter gets them on start and
  gives back any it added.
- `actors`: the persistent ones — player characters, companions,
  recurring NPCs (an actor marked `persistent: true`, as the NPC pane
  marks what it adds) — without their `derived` blocks (the kernel recomputes
  those in every session). Encounter-local actors (the goblins of one
  fight) live in the encounter. At the end of a session every actor the
  campaign already had, plus any of kind `pc` or `companion` new to it
  (a character a player brought), comes back.
- `resources`: the persistent actors' pools and tracks, `"actor:<id>"`
  → plugin → name → record, exactly as the encounter holds them: the
  hurt hero is still hurt next week.
- `state.ext.<plugin>`: campaign-scoped plugin state. During a session
  it lives in the encounter's `campaign.ext` and is changed by `ext.set`
  events with `scope: "campaign"`; banking copies it back.
- `clock`: the session counter and the in-game day and minute the last
  session ended on. Starting a session sets the encounter's clock to
  the next session with that day and minute; `session_start` fires.
- `tracks`: progress tracks that outlive an encounter (a faction's goal,
  a long project), by id, same shape as encounter tracks. They enter
  the encounter flagged `campaign: true`; any track so flagged, or one
  the campaign already had, comes back.
- `journal`: what the sessions left worth keeping — rulings, handouts,
  notes marked `journal: true` — each stamped with its `session` and the
  encounter's name; the Table searches it. A `handout` is something for
  the players: an author's prepared one has `audience: "gm"` until the DM
  shows it; one the DM showed has the `audience` it was shown to, the
  `ref` it was shown from (`place:<id>`, `actor:<id>`, `note:<id>`,
  `picture:<pack:asset>`), and may carry an `image`. The phones' Journal
  holds every handout its player may see; *Stop showing it* sets the
  audience back to `gm`.
- `maps`: the campaign's map library — places, drawn in the Editor —
  by path relative to the campaign file, with a `role` (`battle` or
  `regional`). Adding a map copies it into the campaign's `maps/` and
  records the original as `source`; the art packs it is drawn with are
  copied into the campaign's `art/`, which is the only art the Table
  draws this campaign with. A map is never changed from the Table;
  scenes are made over it.
- `encounters`: prepared encounters: a recipe for a scene — the map and
  level, creatures by compendium entry with a count, a cell and whether
  they start hidden, the DM's notes, the sessions it was `played` in.
- `places`: markers on a regional map (`map`, `cell`, `name`) of a
  `kind`: `place` (somewhere to be: a village, an inn — its card opens),
  or a link to an `encounter`, another `map`, or a journal `note`. A
  place has `text` (what the players are told: the description read out,
  shown to them with the picture), `notes` (the DM's alone), and `image`
  (a picture, `pack:asset`). They, and the party marker, are the
  campaign's record: a scene made over the map afresh (a package just
  started, a copy) shows them where they were.
- `party`: where the party is (a map and a cell), for the marker.
- `player_notes`: the players' own notes (`PlayerNotes`), written on
  their phones and kept here: `{id, owner, title, text, folder, about,
  share, created, updated}`. A note is private to its `owner` unless
  `share` names `"gm"`, players, or `"all"`; the Table never shows a
  private one, and only its owner changes it. `folder` is the player's own
  grouping; `about` is what it is a note on (the `ref` of something the DM
  showed). Never in a package or a fresh copy.
- `contents`: the DM's arrangement of the Reference pane's contents:
  `titles` (a section's name, by key: `notes`, `party`, `places`,
  `people`, `handouts`, `shown`, `from_players`, `pictures`, `maps`,
  `rules`), `folders` (`{id, title, parent}` — a parent is `""`, a
  `"section:<key>"` or a `"folder:<id>"`), `in` (a thing's ref → the
  folder it is filed in; a rules entry is pinned there and stays in the
  glossary) and `order` (the top level). A package carries it, so the
  DMs who start an adventure get its author's arrangement.
- `sessions`: the sessions played, `n` with `started`/`ended`, the
  `recap` kept at the end, and `file` for version-1 sessions that lived
  in their own encounter files.
- `runtime`: the live encounter document as of the last save.

## The live document and sessions

The campaign is not event-sourced; its runtime encounter is. **Open**
(`Campaign.runtime_encounter()`): the encounter kept in `runtime`, or —
for a fresh or version-1 campaign — one built from the summary fields
(players, actors with their resources, tracks, the clock as it stands,
the `campaign` reference and state). The Table runs its kernel on it;
everything that happens is an undoable, replicated event on it, session
or no session. **Save** (`Campaign.capture(encounter)`, then `save()`):
the summary fields are refreshed from the live state and the runtime is
stored, so the top of the file stays a readable summary and the runtime
restores exactly. The Table autosaves the same beside the file.

**Start session** (`begin_session(encounter, path)` → events, committed
by `RulesKernel.start_session()` as one step): on the campaign's own
runtime, the clock moves to the next session and the `campaign` block
is refreshed — nothing is re-added, so an edit made between sessions
stands. Then the rules hear `session_start` (session refills, expiries,
the hook) and a checkpoint named `Session N start` is marked, which is
what the recap measures from; `sessions` gains the entry. Into a
foreign encounter (an old encounter file that names a campaign), the
version-1 load happens instead: players, actors with resources and
tracks come in too.

**End session** (`end_session(encounter, recap)`): journal-worthy log
entries (rulings, handouts, notes marked `journal: true`) are stamped
with the session, the session entry gets its `ended` time and the recap,
and the state is captured. `bank(encounter, file)` is the version-1 end,
kept for old flows.

## Actor

The one record for anything with a sheet. Tokens point at actors by id;
an actor may have no token (an environment, a hazard, a PC who is
elsewhere).

```json
{
  "id": "a_hero",
  "kind": "pc",
  "name": "Ana's ranger",
  "owner": "pl_a1",
  "art": "creatures:ranger",
  "token": { "size": 1, "color": "#4f9cf6", "vision": { "radius": 6 } },
  "ext": { "sample.ordered": { "level": 3, "stats": { "agi": 2, "str": -1 } } },
  "derived": { "sample.ordered": { "defence": { "total": 13, "parts": [ … ] } } },
  "overlays": [ { "id": "o_bear", "source": "sample.ordered:shapeshift", "patch": { "sample.ordered": { "stats": { "str": 4 } } } } ],
  "audience": { "fields": { "ext.sample.ordered.secret": "gm" } },
  "packs": { "sample.ordered.core": "1" }
}
```

- `kind`: `pc` | `npc` | `companion` | `environment` | `hazard` | `custom`.
  Hexmap uses it only for defaults (who owns it, whether it gets a token).
- `owner`: a player id; absent for the GM's.
- `token`: defaults used when the actor is placed as a token.
- `ext.<plugin>`: the plugin's source data, validated against the schema
  it declared for `actor`. Changed by `actor.set` events.
- `derived.<plugin>`: written by the kernel from the plugin's `derive`
  after any change to `ext`, equipment, effects or overlays. Never edited
  by hand or by events; replicated to Players as data. Typed numbers are
  `{total, parts: [{label, type, value, source}]}`.
- `overlays`: stacked patches on `ext` (a transformation, a stance),
  pushed and popped by `actor.overlay.push` / `actor.overlay.pop`. The
  kernel derives from `ext` with the patches merged in order.
- `audience.fields`: per-field visibility the plugin declared or the GM
  set: `gm` | `owner` | `all`. Projection to a Player drops what they may
  not see.
- `packs`: the pack versions this actor's references were resolved
  against, so "update to latest" knows what changed.
- `persistent`: kept by the campaign though it is not a character (a
  recurring NPC); encounter-local actors are not.
- For a person of the world (the Reference pane's card): `place` (the
  place they are at), `image` (their picture), `public` (what the players
  may know of them, shown with the picture) and `notes` (the DM's alone).
  None of these reach a phone except what the DM shows.

## Audiences

Who may see a record: `"all"`, `"gm"`, `"owner:<player>"` (the player
who owns it) or `"players:<id>,<id>"` (the players named). The GM sees
everything; a display sees `all` only. Log entries, effects and tracks
carry one; so do the journal's handouts. What the DM shows the players is
a handout with the audience they chose (everyone, or one player — shown
to one and then another, it is theirs both).

## Character files

An actor on its own, for a player to carry (`G12` in the desirements):

```json
{ "format": "silvergrove.character", "version": 1,
  "plugin": { "id": "sample.ordered", "version": "0.1.0" },
  "actor": { …actor… } }
```

The Table validates it against the plugin on join and adopts it into the
campaign's `actors`; on leaving, the player's client is given the updated
record back.

## Events

There are none of its own: the campaign is data between sessions, and
the encounter's events (`actor.*`, `resource.set`, `track.*`,
`clock.set`, `ext.set` with scope `campaign`, `log.add`) are how it
changes while one is running — see docs/encounter-format.md.
