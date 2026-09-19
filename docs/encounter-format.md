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
  "initiative": { "order": ["t_7f", "t_02"], "round": 1, "turn": 0, "running": false },
  "players": [ { "id": "pl_a1", "name": "Ana", "color": "#4f9cf6" } ],
  "notes": [ { "id": "n_01", "title": "If they flee…", "text": "…" } ],
  "meta": { "author": "", "description": "", "created": "…", "modified": "…" },
  "ext": {}
}
```

- `active_scene`: the scene the table is showing. Players see this one.
- `initiative.order` is token ids, in order; `turn` indexes it, `round`
  counts from 1. `running` is whether the tracker is in use. Tokens not in
  the order simply have no turn.
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
| `initiative.set` | `changes` | `initiative.set` |
| `player.add` | `player` | `player.remove` |
| `player.remove` | `id` | `player.add` |
| `player.set` | `id`, `changes` | `player.set` |

`changes` dictionaries merge: a value of `null` removes the key, so the
inverse of setting a new key is setting it to `null`. `scene`, `id` and
`ref` name things that must exist; `validate()` says why an event is bad
before `apply()` is asked.

**Who may send what.** The table (DM) may apply anything. A player's client
sends the same events as *requests*; `EncounterState.allowed(event,
player_id)` lets through only `token.set` on a token that player owns, and
only its `pos`, `rot` and `elevation`. The table validates, applies, and
rebroadcasts what it applied.

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
