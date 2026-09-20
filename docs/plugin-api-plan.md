# Plugin API — the plan

How Hexmap grows from a map editor with a table into a game-agnostic VTT
whose rules come from sandboxed plugins. This is the long-duration plan:
the shape of the API, the order we build it in, what changes in the code
we have, and how every piece is tested. It is written against
`docs/plugin-api-desirements.md` (P1–P15 are the primitives named there,
items 1–37 the features, G1–G20 the growth list).

We are choosing the best path, not the shortest. Where the current design
is in the way, the plan says so and replaces it.

---

## 1. Goals, non-goals, principles

**Goals**

1. A ruleset is a plugin: a manifest, JSON schemas, data packs, and Lua.
   Nothing about any game lives in Hexmap.
2. Plugins run only on the Table. Player and Display clients render data
   and send intents; they never load plugin code.
3. Everything a plugin does is an event in the log: replayable, undoable,
   replicated, testable.
4. The API is complete enough that the three studied ruleset shapes —
   ordered initiative with modifiers, focus-holder with cards and a GM
   resource, degrees-of-success with valued conditions — are each
   expressible without a host change.
5. Every layer has a test harness before it has a second feature.

**Non-goals (this plan)**

- Shipping any licensed ruleset. The reference plugins are original,
  minimal rulesets built as fixtures.
- Internet play, relays, accounts. LAN stays the transport; the protocol
  is designed so a relay can be added without changing plugins.
- A visual plugin editor. Homebrew editors are generated from schemas;
  authoring a plugin is a text-editor task.

**Principles that survive from the current code**

- The map is never edited (`EncounterState.effective()`).
- One way to change state: `apply(event) → inverse`.
- Portability rule: `core/ render/ encounter/ net/ player/` (and the new
  `rules/`, `ui/`) never reference desktop-only classes
  (`tools/check_scripts.gd`).
- Versions: dev numbers roll freely; the app version does not roll without
  the user. File-format and protocol versions are separate integers and
  roll when the format changes.

---

## 2. The shape

### 2.1 Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ Clients: Table window · Player (phone) · Display (TV)                 │
│   render declarative UI from data; Table also hosts the kernel        │
├──────────────────────────────────────────────────────────────────────┤
│ Net: Protocol v2 — documents, events, views, prompts, intents,        │
│   audience filtering, pack/map streaming                              │
├──────────────────────────────────────────────────────────────────────┤
│ Kernel (hexmap/rules/, GDScript, portable):                           │
│   HookBus · Derivation · TypedNumber · Effects · Dice · Resources &   │
│   Tracks · SharedState · Clock · Prompts · Audience · Compendium      │
│   index · TurnStrategy · MapQuery · EventLog                          │
├──────────────────────────────────────────────────────────────────────┤
│ Runtime (hexmap/rules/lua/): one sandboxed Lua VM per plugin, the     │
│   `hexmap` API bound, budgets enforced, no fs/net/os                  │
├──────────────────────────────────────────────────────────────────────┤
│ Plugins: manifest.json · schemas/*.json · packs/*.json · *.lua ·      │
│   tests/*.lua                                                         │
├──────────────────────────────────────────────────────────────────────┤
│ Documents: .hexmap (unchanged) · .encounter v2 · .campaign v1 ·       │
│   .pack (compendium) · character files                                │
└──────────────────────────────────────────────────────────────────────┘
```

The kernel is GDScript and rules-free: it knows what an effect *is* (a
record with changes and a duration) but not what any effect *means*. The
plugin supplies meaning through hooks and data. The kernel is also what
tests exercise directly, so most of the API is proven before a line of Lua
runs.

### 2.2 Documents

**`.campaign` (new, v1).** The thing a group keeps for years (G11):

```
{ format: "silvergrove.campaign", version: 1, id, name,
  plugins: [{id, version, settings}],          // which rulesets, in order
  actors:  {id: Actor},                        // PCs, recurring NPCs
  players: [...],                              // moved up from encounter
  packs:   [pack refs],                        // user packs this campaign uses
  state:   {ext: {<plugin>: {...}}},           // campaign-scoped shared state
  clock:   {day, time, session},
  journal: [...], tracks: [...],
  encounters: [paths] }
```

**`.encounter` v2.** Stays a session over scenes, and references the
campaign. Adds: `actors` (encounter-local instances: monsters spawned here,
overlays on campaign actors), `effects`, `resources`, `tracks`, `state.ext`,
`prompts` (open prompts, so a reconnecting Player gets them), `log`
(events with reasons and audience), `checkpoints`. Tokens gain an
optional `actor` id; they still carry no numbers.

**Actor.** The one record type for anything with a sheet:

```
{ id, kind: "pc"|"npc"|"companion"|"environment"|"hazard"|"custom",
  name, owner, art, token_defaults,
  ext: {<plugin>: {...}},          // the plugin's source data, schema-validated
  derived: {<plugin>: {...}},      // written by the kernel from derive(), never by hand
  overlays: [{id, source, ext_patch}],
  audience: {fields: {path: "gm"|"owner"|"all"}} }
```

**Packs.** A compendium pack is a directory or zip: `pack.json` (id,
version, plugin, provenance, license, attribution), one JSON file per
collection, optional art. Shipped packs and user packs have the same shape;
user packs layer over shipped ones by id.

**Character file.** An actor plus the plugin id and pack versions it was
built against, for G12 (a character that lives on the player's phone).

### 2.3 Events

The event vocabulary grows from 15 types to families. Every event keeps the
existing shape (`t`, targets, `changes` with `null` = remove), gains
`reason` (free text or a structured `{by: plugin, hook, roll}`), `audience`
and `seq`. `apply()` still returns the inverse.

```
ext.set        {scope: campaign|encounter|scene|token|actor, id, plugin, changes}
actor.add / actor.remove / actor.set / actor.overlay.push / actor.overlay.pop
effect.apply / effect.set / effect.remove
resource.set / track.set
roll           {spec, result, outcome, visibility}          — informational, not undoable
prompt.open / prompt.answer / prompt.close
focus.set      {holder, by}                                  — focus-holder turns
turns.set      (unchanged; strategy data inside)
clock.set
log.note       {text, audience}                              — chat/whisper
checkpoint.mark / checkpoint.restore
```

`roll` is the one non-invertible event: it records what happened; the
state changes it caused are their own events with `reason.roll = seq`.

### 2.4 The kernel

`hexmap/rules/` — new, portable, rules-free.

| class | responsibility | primitive |
|---|---|---|
| `HookBus` | ordered handlers per hook name; `run(hook, payload) → payload` with modify/veto/extend; **resumable** via coroutine-style continuation ids | P1 |
| `Derivation` | tracks dependencies per actor (ext, equipment, effects, overlays), calls each plugin's `derive`, writes `derived`, emits `actor.set` with `reason.derived` | P2 |
| `TypedNumber` | `{total, parts:[{label,type,value,source}]}` with plugin-chosen stacking policies | P3 |
| `Effects` | records keyed by token/actor; duration kinds; expiry driven by `TurnStrategy` and `Clock`; auras via `MapQuery` | P4 |
| `Dice` | expression parser (keep/drop/reroll/min/explode), named and themed dice, roll types and visibility, seeded RNG per encounter, pending rolls with contributions, post-roll window, typed-in results | P5 |
| `TurnStrategy` | replaces `TurnSystem`; two built-in shapes (`ordered`, `focus`) with plugin-supplied policies; counters; history | P6 |
| `Resources` | pools and slot tracks on any entity; recharge kinds; refill on hooks | P7 |
| `SharedState` | encounter- and campaign-scoped `ext` with audience | P8 |
| `Prompts` | open prompts with ids, forms, audience, deadline, GM override; answers resume hooks | P9 |
| `Views` | declarative UI schemas registered by plugins; per-audience projection | P10 |
| `Compendium` | pack loading, id index, facet index, full-text index, paged queries, layering, provenance | P11 |
| `MapQuery` | distance/bands, templates, LoS/cover, light at point, regions, zones, hex state; over `EncounterState.effective_level()` and `Vision` | P12 |
| `Clock` | scene/rest/session/day/time; advance; subscribers | P13 |
| `EventLog` | seq, reasons, audience, checkpoints; the existing `History` becomes a view over it | P14 |
| `PluginHost` | manifests, capability grants, VM lifecycle, budgets, self-tests | P15 |

`EncounterCommands` remains the Table's undoable front door but grows thin:
most commands become "run this hook, apply what it emits".

### 2.5 The Lua API

One VM per plugin, no `io`, `os`, `debug`, `require`, `load`; a curated
`string`/`table`/`math` (with `math.random` replaced by the kernel's seeded
dice); instruction and memory budgets per call; every host call goes
through a capability check against the manifest.

```lua
-- manifest.json: {id:"sample.ordered", version:"0.1.0", api:1, name, attribution,
--   capabilities:["compendium","map","prompts"], depends:[], schemas:{...}, packs:[...]}

local hm = hexmap                       -- the only global besides std libs

hm.schema.define("actor", "sample.ordered", { -- JSON schema by reference
  ["$ref"] = "schemas/actor.json" })

hm.derive("actor", function(actor, ctx)   -- P2: pure, returns derived fields
  local str = actor.ext.stats.str
  return {
    defence = hm.num({ {label="base", value=10},
                       {label="agility", type="ability", value=actor.ext.stats.agi} }),
    initiative = hm.num({ {label="agility", value=actor.ext.stats.agi} }),
    hp_max = 8 + actor.ext.level * 4,
  }
end)

hm.on("before_roll", function(p)          -- P1: modify the payload
  if p.kind == "attack" and hm.effects.has(p.actor, "shaken") then
    p.modifiers[#p.modifiers+1] = {label="shaken", type="status", value=-2}
  end
  return p
end)

hm.on("after_roll", function(p)           -- P5: classify
  p.outcome = (p.total >= p.dc) and "success" or "failure"
  if p.dice.d20.face == 20 then p.outcome = "critical" end
  return p
end)

hm.actions.register("strike", {           -- an action Players may request
  label = "Strike", cost = {actions=1}, target = "token", range = "reach",
  run = function(ctx)                     -- may yield on prompts (P9)
    local roll = hm.dice.roll({ expr="1d20", kind="attack", actor=ctx.actor,
                                dc=hm.derived(ctx.target).defence.total })
    if roll.outcome ~= "failure" then
      local dmg = hm.dice.roll({ expr="1d8", kind="damage", actor=ctx.actor })
      local use_armour = hm.prompt(ctx.target_owner, {   -- yields; resumes with the answer
        id="armour?", form={ {key="yes", type="bool", label="Spend an armour slot?"} },
        deadline=30, default={yes=false} })
      hm.resources.mark(ctx.target, "hp", use_armour.yes and dmg.total-2 or dmg.total,
                        {reason={roll=roll.seq}})
    end
  end })

hm.turns.register({                       -- P6: a strategy
  shape = "ordered",
  initiative = function(actor) return hm.derived(actor).initiative end,
  tie_break = "highest_then_name",
  budgets = { actions = 3, reactions = 1 },
  on_turn_start = function(actor) hm.resources.refill(actor, "actions") end })

hm.ui.register("sheet", "sample.ordered", { ["$ref"]="ui/sheet.json" })   -- P10
hm.ui.register("panel.gm", "sample.ordered", { ["$ref"]="ui/gm_panel.json" })

hm.test("a shaken attacker takes -2", function(t)     -- P15: ships with the plugin
  local a = t.actor({ext={stats={agi=2}, level=1}})
  hm.effects.apply(a, {id="shaken", duration={kind="turns", n=1, of=a}})
  local r = t.roll_with_faces({d20=15}, {kind="attack", actor=a, dc=16})
  t.eq(r.total, 15, "15 + 2 - 2")
end)
```

Namespaces: `hm.schema`, `hm.derive`, `hm.on`, `hm.num`, `hm.dice`,
`hm.effects`, `hm.resources`, `hm.tracks`, `hm.state` (campaign/encounter
`ext`), `hm.comp` (paged queries only), `hm.ui`, `hm.prompt`, `hm.actions`,
`hm.turns`, `hm.map`, `hm.clock`, `hm.log`, `hm.test`. Everything the
plugin returns or emits is plain tables the kernel validates against the
plugin's schemas.

**Declarative-first.** Common things are data with expressions, not Lua
functions: an effect's `changes`, a condition registry entry, an action's
cost and range, a resource's recharge. Lua is for the long tail
(pipelines with decisions, unusual dice, strategies). The kernel evaluates
a small expression language (`"@actor.level * 2 + 1"`) inside schemas so
most homebrew never needs Lua at all.

### 2.6 Declarative UI

`hexmap/ui/views/`: a renderer for a JSON view schema, used on the Table,
the Player and the log. `PropertyForm` moves here (it is the seed of the
`form` widget) and gains the widget set from P10: `tabs`, `section`,
`field`, `repeater`, `computed`, `roll_button`, `action_bar` (cost glyphs,
enabled predicate), `picker` (compendium), `list_detail`, `card`,
`zones` (hand/loadout/vault), `slot_track`, `pool`, `tracker`, `wizard`,
`prompt`. Bindings are JSON-pointer paths into a view's data
(`actor.derived.sample.defence`), so the Player renders without knowing
the plugin. Unknown widget types render as labelled text.

The same schema family produces the **homebrew editors** (item 9) from the
record schemas: `hm.schema.define` plus optional `ui_hints` is enough to
generate a form.

### 2.7 Networking (Protocol v2)

Additions to `Protocol`: `campaign` and `packs` on welcome; `view` (a
projected data document for one audience: an actor's sheet, the table
status, a hand); `prompt` and `answer`; `intent` (replaces the raw
`request` for rules actions: `{action, actor, target, args}`); `log`
entries with audience; `role` on join (`player`, `display`, `cogm`).
Audience filtering happens on the host before send: a Player never
receives a GM-only field, a hidden token, or another player's prompt.
Existing `request {ev}` remains for host-owned events (token moves).

### 2.8 Clients

- **Table**: hosts the kernel and plugins; GM panels are plugin views;
  the log is a view; prompts appear as a queue with override.
- **Player**: renders views; sends intents and answers; keeps a local
  character file (G12); no scene is still a valid session (G8).
- **Display** (G1): a Player-role client with no controls and the
  "all" audience; full-screen map plus optional trackers; QR join.

---

## 3. What changes in the code we have

| now | becomes | why |
|---|---|---|
| `TurnSystem` (`hexmap/encounter/turn_system.gd`) with `build_order/next/previous` | `TurnStrategy` in `rules/` with `ordered` and `focus` shapes; plugin supplies policies; `turns.data` keeps its opaque contract | P6; the current class assumes a list |
| `EncounterState.EVENTS` (15 types) and `validate()` as one `match` | event families registered by the kernel with per-family validators; `apply()` dispatches by family | keeps `apply → inverse` while letting families grow |
| `EncounterState.allowed()` / `may_move()` | `Audience` + `Permissions`: host rules (token moves) plus plugin `allowed(intent)` | intents are richer than events |
| `History` (redo/undo closures) | a view over `EventLog` (seq, inverse, groups, checkpoints) | one log for undo, replication, replay, recap |
| `Encounter.players` | `Campaign.players`; encounter keeps a reference | players outlive sessions |
| `Encounter.DEFAULT_TURNS.system` | `turns.strategy` + `turns.plugin` | naming; multiple plugins may register strategies |
| `PropertyForm` (`editor/`) | `ui/views/` widget `form`; editor uses the same | Player must render forms; editor/ is not portable |
| `HostSession.apply_request` | `HostSession.intents` → `PluginHost.dispatch(intent, player)` | rules actions go through the kernel |
| `Protocol` v1 | v2 (additive: new `t`s; v1 clients refused with a clear error) | views, prompts, intents, roles |
| `EncounterCommands` (23 named commands) | keeps host-owned commands; gains `run_hook()` and `dispatch()` | plugins emit; commands stay undoable |
| `.encounter` v1 | v2 with `_upgrade()` path; v1 files keep loading | actors, effects, prompts, log |
| `tests/test_suite.gd` (2,855 lines, one file) | split into `tests/suites/*.gd` discovered by `TestSuite`; same `check/skip/say` API; self-test mode unchanged | the kernel adds several thousand lines of tests |

Nothing in `core/` or `render/` changes for rules; `MapQuery` is built on
top of `HexGrid`, `Lighting`, `Vision` and `effective_level()`.

---

## 4. The phases

Each phase ends with: its tests green in CI on all four platforms where
applicable; the reference plugins updated; the format docs updated; a dev
build. Phases are ordered so that every one delivers something a DM can
use, and so that the focus-holder shape and the phone are proven early —
those are where a D&D-shaped design would silently creep in.

### Phase 0 — Decisions and spikes

Deliverables:
- **Lua runtime spike.** Evaluate `gilzoide/lua-gdextension` (Lua 5.4,
  standalone `LuaState`, all platforms), `fernforestgames/luau-gdextension`
  (Luau, sandboxing designed in, gradual types) and
  `WeaselGames/godot_luaAPI`. Criteria: standalone sandboxed states;
  removing std libs; instruction/memory limits or a hook to enforce them;
  coroutines exposed to GDScript (prompts depend on `yield`); Godot 4.7
  build on macOS/Windows/Linux and in headless CI; binary size; license;
  maintenance cadence. Deliverable: `docs/lua-runtime.md` with the choice
  and a `tools/lua_spike.gd` that runs a script under a budget and yields
  from a host call. Leaning: Luau for sandboxing and determinism, unless
  the coroutine bridge or CI build is worse than Lua 5.4's.
- **Schema validator.** A JSON-Schema (draft 2020-12 subset) validator in
  GDScript, `core/json_schema.gd`, with its own test file of positive and
  negative cases. Used by every layer after this.
- **Expression language.** `core/expr.gd`: a tiny, total, side-effect-free
  expression evaluator over a data context (`@actor.level * 2 + max(1, @x)`).
  Fuzzed for termination.
- **Document decisions** written into `docs/campaign-format.md` and
  `docs/encounter-format.md` v2 (drafts): actors, effects, log, campaign.
- **Test-suite split** and a `tests/fixtures/` convention.

Exit: spike scripts pass in CI; formats reviewed.

### Phase 1 — Kernel core

`HookBus`, `EventLog` (absorbing `History`), event families (`ext.set`,
`actor.*`, `effect.*`, `resource.*`, `roll`), `TypedNumber`, `Derivation`,
`Effects`, `Dice`, `Resources`. All GDScript, all exercised by tests that
register GDScript handlers on the bus (no Lua yet).

Concrete changes: `EncounterState` event dispatch by family; `.encounter`
v2 `_upgrade()`; `EncounterCommands.run_hook()`; `Encounter` gains
`actors`, `effects`, `resources`, `log`.

Exit: a GDScript fixture ruleset (tests only) can create an actor, derive
a defence, apply an effect that changes a roll, roll with a seed, mark a
resource, undo it all, replay the log from empty and reach the same
document byte for byte.

### Phase 2 — Runtime and plugin host

`PluginHost`: manifest parsing, capability grants, one VM per plugin,
the `hm.*` bindings for everything Phase 1 built, budgets, error
isolation (a plugin error fails the hook, never the Table), the
`hm.test` harness and a `--plugin-test <dir>` CLI mode, plugin discovery
(`user://plugins`, `res://plugins`, beside the campaign).

First reference plugin: **`sample.ordered`** — an original, deliberately
small ruleset: six stats, a defence, initiative, a d20 with a simple
outcome, three conditions, hit points as a pool. Its tests are the
conformance suite's first fixture.

Exit: `sample.ordered` runs the Phase 1 scenario end to end from Lua; a
plugin that tries `io.open`, infinite loops, allocates without bound, or
throws inside a hook is contained with a readable error in the Table log;
the plugin's own tests run in CI and in the app's self-test.

### Phase 3 — Turns, shared state, clock, prompts

`TurnStrategy` (`ordered` and `focus`), `SharedState`, `Clock`, `Tracks`,
`Prompts` with resumable hooks (coroutines across host calls), pending
rolls with contributions.

Second reference plugin: **`sample.focus`** — no initiative; a spotlight
holder; a shared GM pool fed by a two-die roll with a four-way outcome;
abilities as cards with a hand and a vault; a countdown; hit points as a
slot track; a damage step that prompts the target's owner. Everything a
D&D-shaped design would get wrong, in one small original ruleset.

Exit: both strategies run under the Table's existing turn UI (which now
renders either shape from data); a prompt survives a Player reconnect;
the fuzz test drives both plugins with random intents and never breaks
the invariants (log replays, undo inverts, no plugin exception escapes).

### Phase 4 — Declarative UI, intents, Protocol v2, three clients

`ui/views/` renderer and widget set; `Views` projection by audience;
Protocol v2 (`view`, `prompt`, `answer`, `intent`, `role`); `HostSession`
dispatch through `PluginHost`; Player client renders sheet/hand/status/log
and answers prompts; Display role; QR join; theatre-of-the-mind (no scene).

Exit: on a phone (emulator in CI, device by hand) a Player sees the
`sample.focus` sheet the Table derived, taps a card, spends from a pool,
answers a damage prompt and helps another Player's pending roll; a v1
Player client is refused with a message; a version-N Player renders a
plugin using an unknown widget as text.

### Phase 5 — Compendium, packs, editors

Pack format; `Compendium` index with paged/faceted/full-text queries served
to Lua lazily; layering; provenance; `hm.comp`; homebrew editors generated
from schemas; pack import/export; character file import/export (G12);
"update instance to latest".

Third reference plugin: **`sample.degrees`** — four degrees of success on
every check with a ±10 rule; valued conditions that decrement on a
schedule; a three-point action budget with glyphs; a compendium of 5,000
generated entries to test scale.

Exit: a 5,000-entry pack answers a faceted query under 20 ms on the Table
without loading into Lua; a homebrew entry created in a generated editor
behaves identically to a shipped one; a character file round-trips
through a phone.

### Phase 6 — Map queries

`MapQuery`: distance with size/reach/diagonal rule and plugin band tables;
templates with plugin-chosen origin rules; LoS and cover classification;
light at a point; per-token vision profiles and attached lights from
effects; regions with tags and enter/leave hooks; persistent zones with
durations; child/attached tokens; hex adjacency and per-hex plugin state
with GM/revealed layers. Player rendering of templates, bands, zones and
trackers from geometry.

Exit: each reference plugin uses the map (reach for `sample.ordered`,
bands for `sample.focus`, templates + cover for `sample.degrees`); the
render tests screenshot templates and zones on all platforms.

### Phase 7 — Campaign, growth, hardening

`.campaign` document and the Table's campaign screen; checkpoints and
restore (G5); recap export from the log (G6); prep triggers on regions and
scenes (G3); bulk operations (G13); improvisation panel driven by plugin
benchmark tables (G4); rulings journal (G18); co-GM role (G17); plugin
layering and override order (G10); performance budgets enforced in CI;
sandbox red-team pass.

Exit: a two-session campaign runs end to end on the reference plugins
with a recap generated between sessions.

### Phase 8 — Real rulesets

Only now, and in their own repositories, the studied rulesets are written
against the API — with the licensing decisions taken then. The API is
declared 1.0 when the first of them ships without a host change it could
not have made through the plugin.

---

## 5. Testing

The rules pipeline is where regressions hurt most, so the test plan is
layered and most of it is deterministic.

### 5.1 Layers

| layer | what | where |
|---|---|---|
| **Unit** | every kernel class; JSON-schema and expression evaluators with negative cases | `tests/suites/rules_*.gd`, run by `./run.sh test` headless and in the app self-test |
| **Golden logs** | recorded event logs replayed from an empty document must reproduce the saved document byte for byte (`JsonDoc` stable serialisation); every inverse applied in reverse must reach the starting document | `tests/golden/*.log.json` |
| **Fuzz** | extend `test_event_log_fuzz` to drive intents through the plugins with a seeded RNG; invariants: no exception escapes, replay equals state, undo inverts, derived fields never stale, audience never leaks (a GM-only field never appears in a Player projection) | same suite, long-run variant nightly |
| **Plugin conformance** | a Lua suite every plugin must pass (`hm.test`): manifests, schemas validate, `derive` is pure, hooks return well-formed payloads, no forbidden globals, tests deterministic under a fixed seed | `plugins/conformance/`, `--plugin-test` |
| **Reference plugins** | the three `sample.*` plugins' own tests, run in CI and inside the app's self-test on every platform | `plugins/sample.*/tests/` |
| **Sandbox** | a red-team suite: escape attempts (`io`, `os`, `debug`, metatables on host objects, `string.dump`), infinite loops, deep recursion, allocation bombs, long strings across the bridge, malformed returns; each must be contained within budget with a readable error | `tests/suites/rules_sandbox.gd` |
| **Protocol** | v1 client refused; v2 message schemas validated both ways; audience filtering table-driven; reconnect restores open prompts | `tests/suites/net_*.gd` |
| **End-to-end** | the existing `jointest` grows: Table hosts `sample.focus`, a Player joins, sheet arrives, card played, prompt answered, help contributed, Display role sees no controls; runs headless on desktop CI, on the Android emulator and the iOS simulator through the current self-test hooks | `tools/*_join_test.sh`, workflows |
| **UI snapshots** | view schemas rendered to PNG at phone and desktop sizes on all four platforms (existing screenshot path), diffed against checked-in images with a tolerance | `tests/snapshots/` |
| **Performance** | budgets asserted in tests: derive 200 actors < 50 ms; effect expiry over 500 effects < 10 ms; 5,000-entry faceted query < 20 ms; a hook round-trip into Lua < 0.2 ms median; a full Player view projection < 5 ms | `tests/suites/perf_*.gd` (skip on emulators) |
| **Compatibility** | a Player of protocol N renders a plugin with an unknown widget; a v1 `.encounter` upgrades and re-saves identically; a pack updated under a character resolves | fixtures under `tests/compat/` |

### 5.2 Determinism

- Every roll takes its randomness from the encounter's seeded RNG stream;
  the seed and the sequence index are in the `roll` event. Replays do not
  re-roll; they read.
- `derive()` is pure: the kernel calls it twice in debug builds and fails
  the test if the results differ.
- Hook handler order is by plugin order then registration order, recorded
  in the manifest set of the campaign; the fuzz test shuffles registration
  to prove order is honoured, not accidental.
- Clock and time never come from `Time.*` inside the kernel; tests inject.

### 5.3 CI

`ci` (Linux headless): script check, unit, golden, fuzz-short, plugin
conformance, reference plugin tests, sandbox, protocol, snapshot diff.
`desktop-test`, `android-test`, `ios-test`: the app self-test now includes
the reference plugin tests and the e2e join with `sample.focus`. A nightly
job runs the long fuzz and the performance suite on a fixed runner class.

### 5.4 Writing plugins with tests from day one

`hm.test` ships with the runtime, `--plugin-test` runs it, and the reference
plugins show the pattern. A plugin without tests is a red flag in review;
the conformance suite fails a plugin whose manifest declares no tests.

---

## 6. Risks and how the plan meets them

| risk | mitigation |
|---|---|
| The Lua bridge cannot yield across a host call (prompts) | Phase 0 spike tests exactly this; fallback is explicit continuation ids (`hm.prompt` returns a token; the handler is re-entered with the answer) — uglier for authors, same semantics |
| A D&D-shaped assumption creeps into the kernel | `sample.focus` is built in Phase 3, before the UI and protocol; the desirements doc names the traps |
| Compendium scale in a Lua VM | queries are host-side and paged; Lua receives pages; Phase 5 exit criterion |
| Plugin errors take down a session | one VM per plugin, budgets, hook failure isolation, Table log; sandbox suite |
| Protocol churn breaks phones in the field | protocol version handshake with a clear refusal; additive changes within a version; compat fixtures |
| The declarative UI cannot express what a ruleset needs | the widget set is derived from the three studies; escape hatch is *more widgets*, never plugin code on the client |
| Document migrations | `_upgrade()` paths with round-trip tests from the first v1 fixture onward; formats are versioned independently of the app |
| Long plan, no visible progress | every phase ends in a dev build a DM can run with a reference plugin; the Table's existing features never regress (the current suite keeps running) |

---

## 7. Decisions taken at Phase 0 (2026-09-20)

1. **Runtime: Luau** (`docs/lua-runtime.md`). The spike ran both; Lua 5.4
   remains the fallback behind `LuaVm`.
2. **`derive` does not read the compendium.** It reads the actor and the
   references the kernel resolved beforehand; pure and fast.
3. **Prompts always have a default and a deadline**; the GM can override
   at any time. A plugin cannot block a session on a Player.
4. **Players receive views plus the scene**, not the whole encounter.
   Stricter audience, lighter phones, and the Display role is just a
   Player with the "all" audience and no controls. The v1 Player keeps
   the whole document until Phase 4 replaces it.
5. **An encounter references its campaign by id and relative path**
   (`campaign: {id, path}`), the same way scenes reference maps.

---

## 8. Versioning during this work

- App version stays at 1.2.0 until the user decides otherwise; dev numbers
  roll with CI as now.
- New format versions: `.encounter` 2, `.campaign` 1, `.pack` 1, protocol 2,
  plugin API 1 (in the manifest as `api`). Each has an upgrade path and a
  compat fixture from the day it changes.
- Plugin API breaking changes before 1.0 are allowed but must update all
  three reference plugins and the conformance suite in the same commit.
