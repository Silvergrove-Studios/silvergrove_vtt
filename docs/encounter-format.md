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
  "tokens": [ { …token… } ]
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

## Version 2 (draft)

What the plugin API adds (`docs/plugin-api-plan.md`, Phase 1). Version 1
files keep loading: `_upgrade()` fills the new blocks empty. Nothing
below puts rules in the map or numbers on tokens; it puts them in
**actors**, **effects** and **state**, and points at them.

```json
{
  "format": "silvergrove.encounter", "version": 2,
  "campaign": { "id": "c_9b1e…", "path": "../reach.campaign" },
  "actors": { "a_gob1": { …actor, kind "npc"… } },
  "effects": { "e_01": { "id": "e_01", "on": "t_7f", "plugin": "sample.ordered", "key": "shaken", "value": 2,
                          "source": { "actor": "a_hero", "roll": 41 },
                          "duration": { "kind": "turn_end", "of": "t_7f", "turns": 1 },
                          "changes": [ { "path": "defence", "mode": "add", "value": -2 } ],
                          "stack": "highest", "audience": "all" } },
  "resources": { "t_7f": { "sample.ordered": { "hp": { "kind": "pool", "current": 5, "max": 9 } } } },
  "tracks": [ { "id": "k_1", "name": "Reinforcements", "kind": "countdown", "value": 3, "start": 4,
                "advance": "per_roll_failure", "audience": "gm", "on_zero": "The gate opens." } ],
  "state": { "ext": { "sample.ordered": { "gm_pool": 4 } } },
  "prompts": { "p_9": { "id": "p_9", "to": ["pl_a1"], "form": { … }, "deadline": 30, "default": {}, "hook": "damage:41" } },
  "log": [ { "seq": 41, "t": "roll", "kind": "attack", "spec": "1d20+3", "faces": { "d20": 15 }, "total": 18,
             "outcome": "success", "actor": "a_hero", "audience": "all", "seed": [1234, 17] } ],
  "checkpoints": [ { "id": "before_fight", "seq": 40, "when": "…" } ],
  "turns": { "mode": "ordered", "strategy": "ordered", "plugin": "sample.ordered",
             "order": ["t_7f", "t_02"], "turn": 0, "round": 1, "running": true,
             "focus": null, "counters": { "t_7f": { "actions": 2, "reactions": 1 } }, "history": [], "data": {} },
  …scenes, players (v1) or none (campaign), notes, meta, ext…
}
```

- **Tokens** gain `actor` (an actor id in the encounter or the campaign).
  A token without an actor is what it is today.
- **actors**: encounter-local instances (see `docs/campaign-format.md`
  for the record). A PC's actor stays in the campaign; the encounter may
  hold an overlay on it.
- **effects**: records keyed by id, attached to a token (`on`) or an
  actor. `value` is optional and numeric (rendered as a badge); `changes`
  are applied by the kernel to the plugin's derived numbers by path with
  `mode` add | multiply | override | upgrade; `duration.kind` is one of
  `rounds`, `turn_start`, `turn_end` (relative to `of`), `until_check`,
  `linked`, `until_cleared`, `scene`, `rest`, `long_rest`, `session`,
  `time` (with `until` on the clock); `stack` is `stack` | `highest` |
  `none`. Plugins register hook handlers by `key`; the record itself is
  rules-free.
- **resources**: pools `{kind: "pool", current, max, recharge}` and slot
  tracks `{kind: "track", max, marked, extra, crossed}` per entity per
  plugin. Changed only by `resource.set`.
- **tracks**: progress tracks (countdowns, clocks, subsystems) with an
  audience and an advance rule the kernel drives from roll-outcome and
  rest hooks.
- **state.ext**: encounter-scoped plugin state (a GM resource pool, a
  shared adversary pool). Changed by `ext.set` with `scope: "encounter"`.
- **prompts**: open questions to Players, kept so a reconnecting client
  gets them again. `hook` names the suspended hook the answer resumes.
- **log**: the events with a sequence number, a `reason` and an
  `audience`; `roll` events are informational and carry the seed and
  index they were drawn from, so a replay reads rather than re-rolls.
- **checkpoints**: named sequence numbers the GM can restore to.
- **turns** gains `strategy` (`ordered` | `focus`), `plugin`, `focus`
  (the holder in focus mode: a token id, an actor id or `"gm"`),
  `counters` (per-participant budgets the strategy maintains) and
  `history`. `mode` keeps its three values: it says who may move tokens;
  `strategy` says how turns are shaped.

Events added: `ext.set`, `actor.*`, `effect.apply/set/remove`,
`resource.set`, `track.*`, `roll`, `prompt.open/answer/close`,
`focus.set`, `clock.set`, `log.note`, `checkpoint.mark/restore`. Every
event may carry `reason` (`{by, hook, roll}`) and `audience`; `seq` is
assigned by the log.
