# The `.encounter` format

An encounter is what a DM runs at the table: one or more maps, the tokens on
them, and everything that has changed since the map was drawn — doors
opened, lights put out, secret walls revealed, fog lifted, whose turn it is.
It is one JSON document with the same conventions as `.hexmap`
(`docs/map-format.md`): plain text, stable key order, no image data, meant
to live in git next to the adventure.

## The map is never edited

An encounter **references** maps by id and never copies or changes them.
Everything the table changes is an **overlay keyed by element id** on top
of the base map, so one map serves many encounters and re-exporting the map
from the editor never loses a session. Readers merge the overlay onto the map
when they draw or compute; the merge is `EncounterState.effective()`.

Tokens, like maps, carry no rules: no hit points, no speed, no stats. Names,
art, position, size, who owns it, what it can see, what light it carries.
Whatever system is being played keeps its numbers elsewhere.

## Document

```json
{
  "format": "silvergrove.encounter",
  "version": 1,
  "id": "3d5f…",
  "name": "Chapel ambush",
  "scenes": [ { …scene… } ],
  "active_scene": "s_1a2b",
  "turns": { "mode": "ordered", "system": "list", "order": ["t_7f", "t_02"], "turn": 0, "round": 1,
             "running": true, "active": [], "data": {} },
  "players": [ { "id": "pl_a1", "name": "Ana", "color": "#4f9cf6" } ],
  "notes": [ { "id": "n_01", "title": "If they flee…", "text": "…" } ],
  "meta": { "author": "", "description": "", "created": "…", "modified": "…" },
  "ext": {}
}
```

- `active_scene`: the scene the table is showing. Players see this one.
- `turns` is who may move, and in what order. `mode` is one of:
  - `free` — anyone may move any token they can see. Exploration, roleplay.
  - `dm` — the DM ticks tokens; `active` lists them, and only their owners
    may move them now.
  - `ordered` — a **turn system** orders the tokens: `order` is token ids,
    `turn` indexes it, `round` counts from 1, `running` says whether turns
    are being stepped. Only the owner of the token whose turn it is may
    move it. `system` names the turn system that built the order (`list`
    is the built-in "as the DM arranged it"); `data` is that system's own
    state — rolled values, phases, and `labels` (token id → text shown in
    the order) — stored and replicated as is, never interpreted by Hexmap.
    A client without the system installed still shows the order and its
    labels, because they are data.

  Tokens not in the order simply have no turn.
- `players`: who can join and what they own. `id` is stable across sessions;
  `color` tints their tokens' rings. The DM is not a player.
- `notes`: encounter-level DM notes (map notes stay on the map).

## Scene

A scene is one map level with its overlay, tokens and fog.

```json
{
  "id": "s_1a2b",
  "name": "Chapel, ground floor",
  "map": "d74c4e99-…",
  "map_path": "ruined_chapel.hexmap",
  "level": "ground",
  "overrides": {
    "walls:w_2bf8ecbc": { "state": "open" },
    "lights:l_e40f32d6": { "on": false },
    "props:p_3c1d": { "hidden": false }
  },
  "fog": { "enabled": true, "explored": ["4,3", "5,3", "5,2"] },
  "tokens": [ { …token… } ],
  "regions": { "fire_1": { "id": "fire_1", "cells": ["4,3", "5,3"], "tags": ["fire", "hazard"], "label": "Fire",
                           "color": "#ff4500", "audience": "all", "plugin": "sample.degrees",
                           "duration": { "kind": "rounds", "rounds": 2 } } },
  "cells": { "5,2": { "revealed": true, "note": "ash", "ext": { "sample.degrees": { "trap": true } } } },
  "highlight": { "cells": ["4,3", "5,3"], "color": "#ffd166", "label": "Close" },
  "triggers": [ { "id": "tr_door", "label": "The crypt opens", "on": "door", "ref": "walls:w_2bf8ecbc", "state": "open", "once": true, "fired": false,
                  "do": [ { "kind": "read", "title": "The crypt", "text": "Cold air…", "audience": "all" },
                          { "kind": "spawn", "tokens": [ { "name": "Ghoul", "at": "6,5", "actor": { "kind": "npc", "name": "Ghoul", "ext": { … } } } ] },
                          { "kind": "action", "plugin": "sample.degrees", "action": "fire_zone", "ctx": { "at": "6,5" } } ] } ]
}
```

- `map` is the map's `id`; `map_path` is where it was last found, relative
  to the encounter file (or absolute). Readers load by path and check the
  id; a mismatch is a warning, not a failure.
- `level` is the level id within the map.
- `overrides`: `"<collection>:<id>"` → fields that replace the map's. Any
  field may be overridden but these are the ones the table sets:

  | element | field | meaning |
  |---|---|---|
  | walls | `state` | `open` / `closed` / `locked` — a door's state now |
  | walls, props, lights, notes | `hidden` | reveal a GM-only element (`false`) or hide one (`true`) |
  | lights | `on` | a light put out (`false`); overlay-only, default `true` |

  A key whose override is `null` is removed from the overlay.
- `fog.enabled`: whether players see fog on this scene. `fog.explored` are
  cell keys (`"q,r"`, as in terrain) the players have seen. What they see
  *now* is not stored: it is computed from their tokens' vision each time
  (`Vision`). Explored cells are drawn dimmed; unexplored ones are dark;
  what a token currently sees is clear.
- `regions` (version 2): named sets of cells a ruleset or the DM lays on
  the scene — zones of fire, difficult ground, an aura, a wall of force.
  `id`, `cells` (`"q,r"` keys), `tags` (what plugins test for), `label`
  and `color` (what the canvas draws), `audience` (`all` | `gm`),
  `plugin` (who owns it) and an optional `duration` with the same kinds
  as an effect's: the kernel removes the region when its trigger fires.
  Anything else in the record is the plugin's.
- `cells` (version 2): per-cell state that is not the map's — the map
  stays read-only. A record exists only while it has something in it:
  `revealed` (whether players may know the rest), any plain fields a
  plugin or the DM sets, and `ext.<plugin>` state set through `ext.set`
  with scope `cell`. Players receive a cell's record only once it is
  `revealed`.
- `turns.order` entries are token ids or `group:<id>`; `turns.data.groups`
  maps a group id to `{tokens, label}` (several tokens on one slot).
- `highlight` (version 2, optional): a template being shown —
  `{cells, color, label}` — set by a plugin through `scene.set` and
  cleared with `null`. Transient by nature; it is fine for it to be in
  the file.
- `triggers` (version 2, optional; also on a region): prep that fires
  during play. `on` is `scene` (this scene shown to the players),
  `door` (the wall `ref` reaches `state`, default `open`), `reveal` (any
  of `cells` explored), `manual` (the DM's button) — or, on a region,
  `enter` / `leave` (a token crosses in or out). `once` (default true)
  and `fired` say whether it fires again. `do` is the list of steps:
  `read` (a handout in the log: `title`, `text`, `audience`), `note`,
  `spawn` (`tokens` with `at` as `"q,r"` or `[x, y]` and an optional
  inline `actor`), `actor`, `light` / `door` / `hide` (`ref`, then `on` /
  `state` / `hidden`), `reveal` (`cells`), `track`, `effect`, `region`,
  `event` (`ev`, any event) and `action` (`plugin`, `action`, `ctx` —
  the rules half, dispatched after the events, prompts and all). A
  trigger is one undo step after the step that set it off; a step that
  fails undoes the whole trigger. Players never receive triggers.

### Token

```json
{ "id": "t_7f", "name": "Goblin", "label": "G1",
  "art": "creatures:goblin", "color": "#c0392b",
  "pos": [3.5, 2.0], "size": 1, "rot": 0, "elevation": 0,
  "hidden": true,
  "vision": { "radius": 6 },
  "tags": [] }
```

- `pos` is canvas position in hex units (the token's centre), like a prop.
  `size` is its diameter in hexes. `rot` in degrees.
- `art`: `pack:token` from a pack's `tokens` collection, `local:file.png`
  from an encounter bundle, or `""` for a plain disc showing `label` in
  `color`. Missing art falls back to the disc.
- `owner`: a player id; absent (or `null`) for the DM's. A player may move
  only tokens they own, and sees the scene through them.
- `hidden`: not shown to players at all (a lurking monster). Distinct from
  fog: a visible token in an unexplored cell is still unseen.
- `vision.radius` in hex units: how far the token sees, walls permitting
  (`blocks.sight`, open doors don't block). `0` sees nothing on its own.
  `vision.dark_radius`: how far of that it sees unlit (darkvision);
  `vision.mode: "dark"` sees unlit everywhere. Clients lift the darkness
  in grey within an owned token's dark radius; `MapQuery.can_see` says
  `dark_sight` when that is how a target was seen.
  `light`: a light the token carries — same fields as a map light
  (`bright`, `dim`, `color`) — or absent. Readers treat a stored `null` as
  absent; writers leave the key out, because in an event `null` means
  "remove" (see Events) and a stored null could not be restored exactly.
- `tags`: free-form strings the DM puts on a token ("prone", "marked").
  Displayed, never interpreted.

## Events

The table never edits this document directly. Every change is an **event**:
a small JSON object with a type `t`, applied by `EncounterState.apply()`,
which returns the inverse event. The same event log drives undo (apply the
inverse), autosave, replication to players and replay.

| event | fields | inverse |
|---|---|---|
| `encounter.set` | `changes` | `encounter.set` with the old values |
| `scene.add` | `scene` [, `index`] | `scene.remove` |
| `scene.remove` | `id` | `scene.add` at the old index |
| `scene.set` | `id`, `changes` | `scene.set` |
| `scene.activate` | `id` | `scene.activate` the previous |
| `token.add` | `scene`, `token` [, `index`] | `token.remove` |
| `token.remove` | `scene`, `id` | `token.add` at the old index |
| `token.set` | `scene`, `id`, `changes` | `token.set` |
| `element.set` | `scene`, `ref`, `changes` | `element.set` with the old overlay values |
| `fog.set` | `scene`, `enabled` | `fog.set` |
| `fog.reveal` | `scene`, `cells` | `fog.hide` of the cells that were new |
| `fog.hide` | `scene`, `cells` | `fog.reveal` of the cells that were explored |
| `turns.set` | `changes` | `turns.set` |
| `player.add` | `player` | `player.remove` |
| `player.remove` | `id` | `player.add` |
| `player.set` | `id`, `changes` | `player.set` |

`changes` dictionaries merge: a value of `null` removes the key, so the
inverse of setting a new key is setting it to `null`. `scene`, `id` and
`ref` name things that must exist; `validate()` says why an event is bad
before `apply()` is asked.

**Who may send what.** The table (DM) may apply anything. A player's client
sends the same events as *requests*; `EncounterState.allowed(event,
player_id)` lets through only `token.set` with `pos`, `rot` or `elevation`,
and only on a token the turn mode lets that player move now
(`may_move`): in `free` mode any token they can see, in `dm` mode one of
theirs the DM has ticked, in `ordered` mode one of theirs whose turn it
is. The table validates, applies, and rebroadcasts what it applied.

## Bundles

An encounter that needs unique token art is a directory `name.encounter/`
holding `encounter.json` and `assets/`, referenced as `local:file.png` —
the same shape as a map bundle.

## What is not in the file

- The maps. They are found by `map_path`, checked by `map` id.
- Undo history and the event log itself: the document *is* the state the
  log produced. The table autosaves it.
- Current vision. Computed from tokens and walls whenever it is drawn.
- Rules of any kind.

## Version 2

What the plugin API adds (`docs/plugin-api-plan.md`, Phase 1). Version 1
files keep loading: `_upgrade()` fills the new blocks empty. Nothing
below puts rules in the map or numbers on tokens; it puts them in
**actors**, **effects**, **resources** and **state**, and points at them.

```json
{
  "format": "silvergrove.encounter", "version": 2,
  "actors": { "a_gob1": { …actor, kind "npc"… } },
  "effects": { "e_01": { "id": "e_01", "on": "token:t_7f", "plugin": "sample", "key": "shaken", "label": "Shaken",
                          "value": 2, "source": { "actor": "a_hero", "roll": 41 },
                          "duration": { "kind": "turn_end", "of": "t_7f", "turns": 1 },
                          "changes": [ { "path": "defence", "mode": "add", "value": -2, "type": "status" } ],
                          "stack": "highest", "audience": "all" } },
  "resources": { "actor:a_hero": { "sample": { "hp": { "kind": "pool", "current": 5, "max": 9, "recharge": "rest" },
                                                "stress": { "kind": "track", "max": 6, "marked": 2, "extra": 0, "crossed": [], "recharge": "rest" } } } },
  "state": { "ext": { "sample": { "gm_pool": 4 } } },
  "log": [ { "id": "r_1a2b", "kind": "roll", "label": "Strike", "actor": "a_hero", "audience": "all",
             "spec": { "expr": "1d20", "parts": [ … ] }, "draw": { "seed": 425830988, "index": 0, "count": 1 },
             "result": { "total": 18, "outcome": "success", "dice": [ … ], "groups": { … }, "parts": [ … ], "modifier": 3 } },
           { "id": "n_9", "kind": "note", "text": "…", "audience": "gm" } ],
  "rng": { "seed": 425830988, "index": 1 },
  "campaign": { "id": "c_9b1e…", "path": "reach.campaign", "ext": { "sample": { "luck": 2 } } },
  "checkpoints": [ { "id": "cp_1a2b", "name": "Session 3 start", "when": "2026-09-21T19:00:00", "seq": 12, "snapshot": { …the document without its checkpoints… } } ],
  …scenes, turns, players, notes, meta, ext…
}
```

- **Tokens** gain an optional `actor` (an actor id). A token without an
  actor is what it is today. **Refs** name the things effects and
  resources sit on: `token:<id>`, `actor:<id>` or `encounter`.
- **actors**: records by id (`docs/campaign-format.md` has the shape:
  `kind`, `name`, `owner`, `token` defaults, `ext.<plugin>` source data,
  `derived.<plugin>` written by the kernel, `overlays`, `audience`).
  `derived` is never set by an event: the kernel recomputes it after any
  event that touches the actor, and a replay recomputes it too.
- **effects**: records keyed by id, on a ref. `value` is optional and
  numeric (a badge); `changes` are applied by the kernel to the plugin's
  derived numbers by path with `mode` add | multiply | override |
  upgrade (a typed number gains a part naming the effect; a plain number
  is changed in place); `duration.kind` is one of `rounds`, `turn_start`,
  `turn_end` (relative to `of`, counting `turns`), `until_check`,
  `linked` (`to` another effect), `until_cleared`, `scene`, `rest`,
  `long_rest`, `session`, `time` (`until`); `stack` is `stack` | `highest`
  | `none`. What an effect *means* is the plugin's business (its `key`).
- **resources**: per ref, per plugin, by name: pools `{kind: "pool",
  current, max, recharge}` and slot tracks `{kind: "track", max, marked,
  extra, crossed, recharge}`. `recharge` names when it refills; the
  plugin decides what the names mean.
- **state.ext.<plugin>**: encounter-scoped plugin state (a GM resource
  pool, a shared pool). Scenes and tokens may carry `ext.<plugin>` too.
- **log**: informational entries in order — rolls and notes — each with
  an `audience`. A roll carries its `spec`, its full `result` and the
  `draw` it came from.
- **rng**: the dice stream. `Dice.face(seed, index, sides)` is a pure
  function, so a roll records `{seed, index, count}` and moving `index`
  past it is part of applying the `log.add`; a replay reads the recorded
  faces and lands on the same index.
- **turns** (version 2 fields, beside the version 1 ones): `strategy`
  is the *shape* — `ordered` (an order stepped with Next, rounds) or
  `focus` (a holder that moves; no order, no rounds); `plugin` names the
  ruleset whose strategy runs it (`""` for the DM's list); `focus` is
  the holder in the focus shape: `token:<id>`, `actor:<id>`, `gm` or
  `""`; `counters` is per-participant budgets for the current turn
  (`{"token:t_7f": {"actions": 2}}`); `requests` are Players asking for
  the focus (`[{player, ref}]`); `history` the last holders. `mode` keeps
  its three values: it says who may move tokens; `strategy` says how
  turns are shaped. Clients draw either shape from these fields alone.
- **tracks**: progress tracks by id — countdowns, clocks and meters:
  `{id, plugin, name, kind, value, max, direction, advance: {on, outcomes,
  amount, actor}, audience, on_done, done, linked}`. `advance.on` is
  `manual`, `roll`, `roll_outcome`, `rest`, `long_rest`, `session` or
  `turn`; the kernel moves them after rolls and rests.
- **pending**: what the Table is waiting on, so a reconnecting client is
  shown it again. `prompts` by id: `{id, to (player id or "gm"), form,
  default, deadline, by (plugin), title, opened (log seq), context}`;
  `rolls` by id: `{id, spec, ctx, label, by, open_to, contributions:
  [{by, name, expr}], deadline, opened}`. The continuation that resumes
  a paused action lives on the Table, not in the file: a Table that
  restarts closes its prompts with their defaults.
- **clock**: `{session, scene, day, minute, rests}` — the second clock,
  for durations longer than a fight.
- **campaign**: which campaign this session belongs to (`id`, `path`
  relative to the encounter file) and `ext.<plugin>`, the
  campaign-scoped plugin state brought in when the session starts and
  banked back when it ends (docs/campaign-format.md). Changed by
  `ext.set` with scope `campaign`.
- **checkpoints**: named snapshots the table can go back to, in this
  session or a later one from the file: `{id, name, when, seq,
  snapshot}`, the snapshot being the whole document but the checkpoints
  themselves (`format`, `version` and `id` are never restored either).
  Restoring is an event, so it is undoable and replicated; the recap
  reads the difference between the last `Session…` checkpoint and now.
- **log** entry kinds beyond `roll` and `note`: `handout` (`title`,
  `text`; read-aloud text a trigger or the DM pushed) and `ruling`
  (`text`, `rule`, `roll`, `tags`; GM audience by default). Rulings,
  handouts and notes marked `journal: true` are what a campaign's
  journal keeps.

Events added in version 2 (all invertible, all through `apply()`):

| event | fields | inverse |
|---|---|---|
| `actor.add` | `actor` | `actor.remove` |
| `actor.remove` | `id` | `actor.add` |
| `actor.set` | `id`, `changes` — keys may be paths (`ext/sample/stats/agi`; slash-separated, since plugin ids contain dots); `null` removes; a set that created dictionaries on the way inverts to a removal of the topmost one it created; `id`, `derived` and `overlays` are not settable | `actor.set` |
| `actor.overlay.push` | `id`, `overlay` [, `index`] | `actor.overlay.pop` |
| `actor.overlay.pop` | `id`, `overlay_id` | `actor.overlay.push` at the old index |
| `effect.apply` | `effect` (with `id`, `on`, `key`) | `effect.remove` |
| `effect.set` | `id`, `changes` (paths allowed) | `effect.set` |
| `effect.remove` | `id` | `effect.apply` |
| `resource.set` | `ref`, `plugin`, `name`, `record` (or `null` to remove) | `resource.set` with the old record |
| `ext.set` | `scope` (`campaign` \| `encounter` \| `scene` \| `token` \| `cell`), `id` / `scene`+`id` (a `"q,r"` key for a cell), `plugin`, `changes` | `ext.set` |
| `log.add` | `entry` (with `id`, `kind`) [, `index`] | `log.remove` |
| `log.remove` | `id` | `log.add` at the old index |
| `track.add` / `track.remove` / `track.set` | `track` / `id` / `id`, `changes` | the usual |
| `pending.open` | `kind` (`prompts` \| `rolls`), `record` | `pending.close` |
| `pending.close` | `kind`, `id` | `pending.open` |
| `pending.set` | `kind`, `id`, `changes` | `pending.set` |
| `clock.set` | `changes` (numbers for the clock's fields) | `clock.set` |
| `region.add` | `scene`, `region` (with `id`, `cells`) | `region.remove` |
| `region.remove` | `scene`, `id` | `region.add` |
| `region.set` | `scene`, `id`, `changes` (paths allowed; not `id`) | `region.set` |
| `cell.set` | `scene`, `id` (`"q,r"`), `changes` (plain fields; plugin state goes through `ext.set`); a record left empty is dropped | `cell.set` |
| `checkpoint.mark` | `checkpoint` (`id`, `name`, `when`; the snapshot is taken on apply unless given) [, `index`] | `checkpoint.drop` |
| `checkpoint.drop` | `id` | `checkpoint.mark` with the record and its snapshot |
| `checkpoint.restore` | `id`, or `snapshot` inline | `checkpoint.restore` with the previous document as its snapshot |
| `scene.set` | may set `triggers` (validated) and use paths (`triggers/0/fired`) | `scene.set` |

Every event may carry `reason` (`{by, hook, roll}`) and `audience`; the
EventLog assigns `seq` and keeps them beside the event.
