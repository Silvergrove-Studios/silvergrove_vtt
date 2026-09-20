# The `.campaign` format (draft, v1)

A campaign is what a group keeps between sessions: the players, their
characters, the rulesets in play, the packs of content they have added,
the clock, the journal, and everything a ruleset needs to remember
across encounters (a resource that carries over, a faction's standing).
An encounter is one session's scenes over one or more maps; a campaign
is the thing those encounters belong to.

Same conventions as `.hexmap` and `.encounter`: one JSON document, plain
text, stable key order, no image data, meant to live in git next to the
adventure. Status: **draft** — Phase 1 of `docs/plugin-api-plan.md`
implements it; until then nothing reads it.

## Document

```json
{
  "format": "silvergrove.campaign",
  "version": 1,
  "id": "c_9b1e…",
  "name": "The Sunken Reach",
  "plugins": [ { "id": "sample.ordered", "version": "0.1.0", "settings": {} } ],
  "packs": [ { "id": "homebrew.reach", "path": "packs/reach", "version": "3" } ],
  "players": [ { "id": "pl_a1", "name": "Ana", "color": "#4f9cf6" } ],
  "actors": { "a_hero": { …actor… } },
  "state": { "ext": { "sample.ordered": { "party_luck": 2 } } },
  "clock": { "day": 12, "time": "14:30", "session": 4 },
  "tracks": [ { …progress track… } ],
  "journal": [ { "id": "j_1", "when": "…", "title": "…", "text": "…", "audience": "gm" } ],
  "encounters": [ "sessions/chapel_ambush.encounter" ],
  "meta": { "author": "", "description": "", "created": "…", "modified": "…" },
  "ext": {}
}
```

- `plugins`: the rulesets this campaign runs, in load order (later ones
  may override earlier ones' hooks). `settings` is what the plugin's
  declared settings schema allows: rules variants, automation levels.
- `packs`: content packs beyond what the plugins ship, by path relative
  to the campaign file. Layered over shipped packs by id.
- `players`: moved up from the encounter (v1 encounters keep theirs; a v2
  encounter references the campaign's).
- `actors`: the persistent ones — player characters, recurring NPCs,
  companions. Encounter-local actors (the goblins of one fight) live in
  the encounter.
- `state.ext.<plugin>`: campaign-scoped plugin state. Changed only by
  `ext.set` events with `scope: "campaign"`.
- `clock`: in-game date and time and the session counter, advanced by
  `clock.set` events. Plugins subscribe (`on_time_advanced`,
  `on_session_start`).
- `tracks`: progress tracks that outlive an encounter (a faction's goal,
  a long project). Same shape as encounter tracks.
- `journal`: notes and handouts with an audience.
- `encounters`: the sessions, by path. Informational; an encounter
  carries its own campaign reference.

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

Campaign-scoped events, applied by the same `apply → inverse` machinery:

| event | fields | inverse |
|---|---|---|
| `campaign.set` | `changes` | `campaign.set` |
| `player.add/remove/set` | as today | as today |
| `actor.add` | `actor` | `actor.remove` |
| `actor.remove` | `id` | `actor.add` |
| `actor.set` | `id`, `changes` (paths under `ext`, `name`, `owner`, `token`, `audience`) | `actor.set` |
| `actor.overlay.push` | `id`, `overlay` | `actor.overlay.pop` |
| `actor.overlay.pop` | `id`, `overlay_id` | `actor.overlay.push` at the old position |
| `ext.set` | `scope: "campaign"`, `plugin`, `changes` | `ext.set` |
| `clock.set` | `changes` | `clock.set` |
| `track.add/remove/set` | `track` / `id` / `id`, `changes` | the usual |
| `journal.add/remove/set` | likewise | likewise |

`derived` is never the target of an event; it is recomputed after any
event that touches its inputs, and the recomputation is itself broadcast
as `actor.set` with `reason: {derived: true}` so Players update without
running rules.
