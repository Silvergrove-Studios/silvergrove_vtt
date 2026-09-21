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

| phase | status | delivered |
|---|---|---|
| 0 Decisions and spikes | done | Luau runtime + `LuaVm`, `JsonSchema`, `Expr`, suite split, format drafts, decisions |
| 1 Kernel core | done | v2 document and events, `EventLog`, `TypedNumber`, `HookBus`, `Dice`, `Effects`, `Resources`, `RulesKernel`, fixture ruleset, fuzz |
| 2 Runtime and plugin host | done | `PluginHost`, manifests, `hm.*` API, prompts as yields, actions, `hm.test`, `sample.ordered` in Lua, `plugintest` |
| 3 Turns, shared state, clock, prompts | done | `TurnRunner` (ordered + focus), tracks, clock, rests, prompts and open rolls as records, `sample.focus`, Table wiring |
| 4 Declarative UI, intents, protocol v2 | done | `ViewRenderer`, `Views` projection by audience, protocol v2 (roles, views, intents), Player panes, Display role, the Rules panel |
| 5 Compendium, packs, editors | done | `Compendium` index and packs, `hm.comp`, `SchemaForm`, the Compendium panel, character files, `sample.degrees` |
| 6 Map queries | done | `MapQuery` (distance/bands, templates, LoS/cover, light, sight), regions with durations and hooks, cell state, `hm.map`, the regions layer, audience-filtered map events |
| 7 Campaign, growth, hardening | done | `Campaign` and sessions, checkpoints in the document, `Recap`, `Triggers`, `Bulk`, `Improv`, rulings journal, co-GM role, plugin layering, perf budgets and the sandbox red-team in CI |
| 7b API completion and square grids | done | the host changes the 5e audit found (H1–H9), square grids beside hex through the whole stack |
| 8 Real rulesets | next | in their own repositories, licensing decided then |

Each phase ends with: its tests green in CI on all four platforms where
applicable; the reference plugins updated; the format docs updated; a dev
build. Phases are ordered so that every one delivers something a DM can
use, and so that the focus-holder shape and the phone are proven early —
those are where a D&D-shaped design would silently creep in.

### Phase 0 — Decisions and spikes — **done 2026-09-20**

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

### Phase 1 — Kernel core — **done 2026-09-20**

What was built, where, and what proves it (`tests/suites/rules_kernel.gd`,
175 checks, plus the existing suites on the new log):

| piece | file | what it does | proven by |
|---|---|---|---|
| Document v2 | `encounter/encounter.gd`, `encounter_state.gd` | `actors`, `effects`, `resources`, `state.ext`, `log`, `rng`; twelve new events with validators and inverses; v1 files upgrade | `test_encounter_v2_events`: refusals, apply/inverse round trip byte for byte, mirror equality, v1 upgrade |
| Path changes | `core/json_doc.gd` | `at_path`, `set_at_path` (prunes emptied parents), `merge_paths` — slash-path change sets with exact inverses | same |
| `EventLog` | `rules/event_log.gd` | a `History` that records events with seq/reason/audience, append-only (undo/redo/restore append compensating entries), batches all-or-nothing, checkpoints, `since()`, `replay()` | `test_event_log`: refusal, batch rollback, undo/redo entries, checkpoint restore as one step, replay reproduces |
| `EncounterCommands` on the log | `encounter/encounter_commands.gd`, `table/table_context.gd` | the Table's commands record through the log; `run_all` for batches | existing encounter/table/net suites unchanged |
| `TypedNumber` | `rules/typed_number.gd` | `{total, parts}` with stack / best / override policies per part type | `test_typed_numbers` |
| `HookBus` | `rules/hook_bus.gd` | ordered handlers, modify/veto, `Wait` to pause and `resume()`, failing handlers skipped and reported | `test_hook_bus` |
| `Dice` | `rules/dice.gd` | pure `face(seed, index, sides)` (splitmix64), expression grammar (kh/kl/dh/dl/rN/!/minN), named groups, typed parts under a policy, typed-in faces, `Pending` with contributions | `test_dice`: determinism, uniformity, every suffix, groups, typed-in, pending |
| `Effects` | `rules/effects.gd` | stacking on apply, `on()`, `remove()` with links, `expire()` per trigger kind, `apply_changes()` on typed and plain numbers | `test_effects` |
| `Resources` | `rules/resources.gd` | pools and slot tracks: spend/gain/mark/clear/cross/refill as `resource.set` events | `test_resources` |
| `RulesKernel` | `rules/kernel.gd` | rulesets registered with `derive`/`fields`/`policy`; `commit()` = batch + targeted re-derivation; `roll()` through `before_roll`/`after_roll` into the log and the dice stream; `actor_view()` with overlays, effects on linked tokens, resources | `test_kernel_end_to_end`, `test_kernel_derive_budget` (200 actors < 50 ms), `test_rules_fuzz` |
| Fixture ruleset | `tests/fixtures/sample_rules.gd` | `SampleRules`: derive, hooks, a `strike` action | the same tests |

Exit criterion met: the fixture creates actors, derives a typed defence,
an effect on a linked token lowers it with a named part, an overlay
changes derived numbers and reverts, a roll picks up the attack and
shaken parts through the hooks and is classified, a strike spends the
target's pool, expiry restores the defence; the log alone replays onto a
fresh state to the same bytes; undoing every step restores the start; the
fuzz drives 500 random batches with replay, undo-all and never-stale
derived holding.

Decisions taken while building:
- `derived` is not an event. It is recomputed after commits (only for the
  actors touched), after undo/redo/restore (everyone), and on replay.
- The document log holds only informational entries (rolls, notes); the
  EventLog is the full record and is not saved in the document yet
  (Phase 4 sends `since()` to reconnecting clients; saving it beside the
  encounter comes with checkpoints in Phase 7).
- A roll is a `log.add` whose entry carries its `draw`; applying it moves
  the dice stream, removing it moves it back, so the stream is part of
  the document and inverses are exact.
- `set_at_path(null)` prunes emptied parents; paths are slash-separated because plugin ids contain dots so forward + inverse leaves
  the document byte-identical.
- Closures on the undo stack and the log's `changed` subscriber hold the
  log/kernel weakly (no leaked instances at exit; the test run checks).

### Phase 2 — Runtime and plugin host — **done 2026-09-20**

| piece | file | what it does | proven by |
|---|---|---|---|
| `LuaPrelude` | `rules/lua_prelude.gd` | the `hexmap` library in Lua: registrations kept Lua-side (hooks, derive, actions, tests), host calls through a table of callables, `hm.prompt` = `coroutine.yield`, errors from the host re-raised in Lua | every plugin test |
| `PluginHost` | `rules/plugin_host.gd` | manifest schema and validation, dependencies, one `LuaVm` per plugin, capabilities, load → seal → register with the kernel; `_derive`, one `HookBus` handler per (plugin, hook) that turns a yield into a `Wait`; `dispatch()` → `PluginCall` (ok / pending / error, `resume()`); `run_tests()` on scratch kernels; `discover()`/`load_dir()`; a `Bridge` object holding the host weakly so the VM's callables never keep it alive; normalisation of empty Lua tables | `tests/suites/rules_plugins.gd` (61 checks) |
| Kernel validators | `rules/kernel.gd` | `hm.schema.define("actor", …)` becomes a validator run on every `actor.add`/`actor.set` before the batch applies; `policy()` merges rulesets' stacking policies for rolls | same |
| Slash paths | `core/json_doc.gd` | change keys are `a/b/c` (plugin ids contain dots) | kernel + plugin suites |
| `sample.ordered` | `tests/plugins/sample.ordered/` (manifest, `main.lua`, `tests.lua`) | the reference ruleset in Lua: schema, derive with typed numbers, conditions as data, `before_roll`/`after_roll`, actions `strike` (prompts the target's owner), `condition`, `rest`, `setup`; 7 tests of its own | `./run.sh plugintest`, the conformance test in the suite (also inside the app's self-test) |
| `plugintest` | `tools/plugin_test.gd`, `run.sh` | load a plugin dir into a scratch kernel and run its tests; exit code | CI |
| Authoring reference | `docs/plugin-authoring.md` | the API as a plugin writer sees it | — |

Exit criterion met: `sample.ordered` runs the Phase 1 scenario from Lua
(derive, effects on derived numbers, rolls through hooks, a strike that
prompts and spends); a plugin that tries `io`, loops forever, recurses
without end, edits the API table, commits an invalid event, yields
without the capability or errors in `derive`/a hook is contained with a
readable error against its id while the kernel and the other plugin
carry on; the plugin's own tests run in CI and in the self-test.

Decisions taken while building:
- Plugin registrations live on the Lua side; the host calls fixed entry
  points (`__derive`, `__run_hook`, `__run_action`, `__run_test`), so a
  hook handler that prompts is just a Lua coroutine yielding.
- A thread taken off the main stack must be pinned in the registry
  (`ref`) or the collector may take it before it runs.
- Host callables must return at once and take exactly the arguments the
  prelude passes; failures come back as `{__error}` and are raised in
  Lua, never from GDScript into the VM.
- The fixture plugin lives under `tests/plugins/`, exported only so the
  on-device self-test can load it; the app ships no ruleset.
- Every roll totals its parts under the merged policy of the loaded
  rulesets unless the spec names one.

### Phase 3 — Turns, shared state, clock, prompts — **done 2026-09-21**

| piece | file | what it does | proven by |
|---|---|---|---|
| Turns v2 fields | `encounter/encounter.gd`, `encounter_state.gd` | `strategy`, `plugin`, `focus`, `counters`, `requests`, `history`; `current_turn_token()` knows the focus shape; `turns.set` merges paths | `tests/suites/rules_turns.gd` (129 checks) |
| `TurnRunner` | `rules/turns.gd` | strategies registered per plugin (initiative from a derived path or a function, tie-break, budgets, labels) plus the DM's list; ordered: `start/next/previous/stop/reorder/consume` with `round_*`/`turn_*` hooks and effect expiry; focus: `set_focus/request_focus/deny_focus` with `focus_changed` asked *before* the move | `test_ordered_turns`, `test_focus_turns` |
| `Tracks` | `rules/tracks.gd` | countdowns/clocks/meters with advance rules on rolls, outcomes, rests, sessions; links summed into one move; `track_done` | `test_tracks_clock_and_rest` |
| `Clock` | `rules/clock.gd` | day/minute/session/scene; `advance` ends timed effects, `next_session` refills session pools, `next_scene` ends scene effects | same |
| `kernel.rest()` | `rules/kernel.gd` | refills, expiries, rest tracks, the `rest` hook | same |
| `kernel.ask/fire/transaction` | `rules/kernel.gd` | hooks with an `events` list the handlers fill; multi-commit steps that are one undo entry and roll back entirely on a veto | `test_ordered_turns` (vetoed step leaves nothing) |
| `Pending` | `rules/pending.gd` | prompts and open rolls as encounter records (`pending.prompts/rolls`) with continuations on the Table; `drive()` runs a `PluginCall` through its prompts; `answer` checks who may; deadlines via `tick`; `close_orphans`; `open_roll/contribute/resolve` | `test_pending_prompts_and_rolls` (a prompt survives save + load) |
| Lua API | `rules/lua_prelude.gd`, `plugin_host.gd` | `hm.turns.*`, `hm.tracks.*`, `hm.clock.*`, `hm.rest`, `hm.dice.open/contribute/resolve/pending` | both reference plugins |
| `sample.focus` | `tests/plugins/sample.focus/` | no initiative: a spotlight, two named dice with a four-way outcome, a GM pool the `focus_changed` hook charges, cards in a hand and a vault, hit points as a slot track, thresholds with an armour prompt, a countdown on dark outcomes; 8 tests | `plugintest`, conformance in the suite |
| Table wiring | `table/table_context.gd`, `turns_panel.gd`, `encounter_commands.gd` | the Table owns a kernel and a plugin host (plugins from `user://plugins`), turn commands go through the runner, the panel draws either shape from data (focus: a GM row, requests, "Give focus") | `test_table_turn_panel_both_shapes` |
| Exact path inverses | `core/json_doc.gd` | a change that created dictionaries inverts to a removal of the topmost one it created | document round-trip tests |

Exit criterion met: both strategies run under the Table's existing turn
UI, which draws either shape from data; a prompt is an encounter record
that survives a save and a load; a fuzz drives both reference plugins
with random actions, turns in whichever shape is running, rests, the
clock and tracks — replay reproduces, undo restores, derived never goes
stale, no prompt is left dangling.

Decisions taken while building:
- The `focus_changed` hook is *asked* before the focus moves so a plugin
  can veto (no pool to spend) or charge for it; every other turn hook
  runs after its moment and contributes events.
- Turn, clock and rest steps are transactions: many commits, one undo
  entry, all undone on a veto or a refused event.
- Effect durations `turn_end`/`turn_start` are relative to a
  participant ref, so they work in both shapes (the focus leaving a
  holder ends its turn).
- Linked tracks are summed before events are made, so a track reached
  twice in one moment moves once by the total.
- Prompt continuations are memory on the Table; the records are in the
  document. A restarted Table answers its orphans with their defaults.

### Phase 4 — Declarative UI, intents, Protocol v2, three clients — **done 2026-09-21**

| piece | file | what it does | proven by |
|---|---|---|---|
| `ViewRenderer` | `ui/views/view_renderer.gd` | JSON view schemas over data: column/row/section/tabs, text (literal, `bind` pointer, `expr`), number with breakdown, pool, slot track, effects, list, cards, button/action bar with cost and `enabled`, tracker, prompt (form + Answer), form, log; intents with `$/pointer` substitution; unknown widgets as text; `if` | `tests/suites/ui_views.gd` (27 checks) |
| `PropertyForm` moved | `ui/property_form.gd` | the form widget the Player can render | ui suite |
| `hm.ui.register` | `rules/lua_prelude.gd`, `plugin_host.gd` | `sheet`, `status`, `gm` view kinds per plugin | reference plugins |
| `Views` | `rules/views.gd` | the projection for an audience: actors (mine / public PCs / opened NPCs, per-field `audience.fields`), sheets with their data, status views, tracks, prompts, open rolls, log by audience, public action specs; GM audience sees all | `test_projection_audience` |
| Protocol v2 | `net/protocol.gd` | `join {player, role}`, `view`, `intent`, `refused {intent}`; `client_document()` strips the rules blocks; scene events vs views; v1 refused with the reason in the error and the close frame | `test_wire_views_intents_and_roles` |
| Host | `net/host_session.gd` | roles (`player`, `display`), a view per joined client re-sent once per poll after rules changes, intents resolved through the kernel (ownership of actor/token, prompt addressee, focus refs), scene requests from players only | same |
| Client | `net/session.gd`, `net_session.gd` | `role`, `view`, `view_changed`, `intent()`, `my_actors()` | same |
| Player | `player/player_window.gd` | a pane beside (wide) or instead of (phone) the map: **Sheet** (plugin sheets or a default one) and **Table** (turns/focus with "Ask for the focus", prompts for me, open rolls with Help, status views, tracks, log); a new prompt brings the pane up; intents from taps; `--display [address]` joins as a display (no controls, everyone's audience) | same |
| Table | `table/rules_panel.gd`, `table_window.gd`, `layout_store.gd` | the Rules panel: plugins loaded, the selected actor's actions with a target picker (dispatched and driven through prompts), prompts waiting on players with Default / answer-for-them, plugins' GM views; the host gets the kernel | same, `test_table_window` |
| Reference plugins | `tests/plugins/*/main.lua` | sheets, a status view and a GM view for both | plugin tests, wire test |

Exit criterion met: over a real socket, Ana joins from a Player window,
sees the `sample.focus` sheet the Table derived, taps a card (an effect
appears on the Table and in her next view), acts, is refused when she
tries to act with Ben's character, answers a damage prompt from her
phone (the Table's action resumes and takes effect), helps another
roll, asks for the focus; a display joins straight into play, sees the
status and no sheets or prompts, and is refused when it sends an intent;
a protocol-1 client is refused with a message; an unknown widget renders
as text; the client holds no rules blocks.

Decisions taken while building:
- A sheet applies to the actors that carry that plugin's data
  (`ext[plugin]`), not to every actor.
- Views are resent whole, once per poll, after any rules change; scene
  events still replicate as events. Diffs can come later without
  changing plugins.
- Player characters are public by default, everything else GM-only;
  `audience.fields` and `audience.visible` open or close paths. A
  plugin's encounter state is visible to all.
- GDScript lambdas capture strings by value: box them (tests).

### Phase 5 — Compendium, packs, editors — **done 2026-09-21**

| piece | file | what it does | proven by |
|---|---|---|---|
| `Compendium` | `rules/compendium.gd` | content packs (directory or single file) indexed on load: facets over scalar/list fields, words over strings; layering by id with unload re-resolving; queries filter/text/sort/page/fields/facets, whole-collection sort cached; user packs (`put` validated by schema, `remove`, `save_user_pack`, `export_pack`, `load_user_packs`); pack versions and `outdated()` | `tests/suites/rules_content.gd` (74 checks) |
| Scale | same | 5,000 generated entries: index ~120 ms, faceted filter ~1.5 ms, text ~14 ms, first page of everything ~85 ms cold then cached | `test_compendium_scale` |
| `hm.comp` | `rules/lua_prelude.gd`, `plugin_host.gd` | query/get/count/collections host-side; put/remove into `<plugin>.homebrew` (capability `content`); versions/outdated; a plugin's manifest `packs` load with it and reload per scratch test kernel | `sample.degrees` tests |
| `SchemaForm` | `ui/views/schema_form.gd` | an editor generated from a JSON Schema: sections, spin boxes with bounds, enums, booleans, comma lists, repeaters for arrays of objects, descriptions as tooltips; `validate()` shows problems by path | `test_schema_form` |
| `CompendiumPanel` | `table/compendium_panel.gd` | collection, search, facet buttons, pages, an entry in its schema form (or JSON), Copy to homebrew / Save / Delete / Export pack, plugin actions with `target = "entry"` | `test_compendium_panel` |
| `CharacterFile` | `encounter/character_file.gd` | the player-owned character document; make/from_view/to_actor/check/save/load/list | `test_character_files_round_trip` |
| Bring and keep | `net/host_session.gd`, `player/player_window.gd` | the `character` intent (adopted as the player's, schema-checked, updated if already theirs); the Sheet pane's Bring / Keep buttons; `outdated` shown | same (over the wire) |
| `sample.degrees` | `tests/plugins/sample.degrees/` | four degrees with the natural 20/1 step, valued conditions ticking at turn end, a three-action budget with a mounting attack penalty, schemas for `creatures` and `feats`, a shipped pack, `spawn` from an entry; 5 tests | `plugintest`, conformance |
| Table | `table/table_context.gd`, `layout_store.gd` | user packs under `user://content` load with the plugins; the Compendium pane is docked with Turns and Rules | table suite |

Exit criterion met: a 5,000-entry pack answers a faceted query in
~1.5 ms on the Table without loading into Lua; a homebrew creature
made through the schema form (and one put by the plugin) spawns with
the same derived numbers as a shipped one; a character file brought
from a Player is adopted, derived, shown on the phone with its sheet,
updated when brought again, and kept back to the device with the
table's version.

Decisions taken while building:
- Collections are named by their schema: `hm.schema.define("creatures",
  …)` is both the validator and the editor form.
- Each plugin has one homebrew pack (`<plugin>.homebrew`); a table
  without plugins writes `table.homebrew`.
- A plugin's shipped packs are reloaded for every one of its scratch
  test kernels, so tests see the content and never write into the real
  compendium.
- Words are indexed only from string fields; list fields are facets.

### Phase 6 — Map queries — **done 2026-09-21**

| piece | file | what it does | proven by |
|---|---|---|---|
| `MapQuery` | `rules/map_query.gd` | the kernel's geometry over the scene's effective level: `distance` (centre, edge with token sizes off, axial cells, the plugin's band), `within`, `template` (circle / cone / line / band; origin at centre or edge; optionally cut by walls) → cells + tokens, `line_of_sight` (rays to the target's centre and corners against walls and, optionally, tokens → clear / partial / total cover), `light_at` (map lights and token lights, shadows), `can_see` (vision radius + sight + light or dark vision), `neighbors` / `cells_within` / `cells_between`, `cell` with the map's terrain | `tests/suites/rules_map.gd` (55 checks) |
| Bands | same | `register_bands(plugin, [{name, max}])` in edge-distance hex units; per-plugin tables, dropped on unregister, copied into scratch test kernels | `sample.focus` |
| Regions and cells | `encounter/encounter_state.gd`, `encounter.gd` | scene `regions` (id, cells, tags, label, color, audience, plugin, duration) and `cells` (plain fields + `ext.<plugin>`; empty records pruned); events `region.add/remove/set`, `cell.set`, `ext.set` scope `cell`; `fill_scene` on load and `scene.add` so hand-built and loaded scenes agree | `rules_map`, the replay tests |
| Moves | `rules/kernel.gd`, `encounter_commands.gd`, `table_window.gd` | `MapQuery.move` (attached tokens follow) → `RulesKernel.move_token` as one transaction: `token_moved` asked first (veto, extra events), then `region_left` / `region_entered` per zone; the Table and Player moves both go through it; `kernel.expire` ends regions with effects | `test_map_regions_cells_and_moves`, `sample.degrees` |
| `hm.map` | `rules/lua_prelude.gd`, `plugin_host.gd` | the whole query surface plus region/cell/highlight event builders; `t.scene(map, tokens)` for plugin tests | the three plugins' map tests |
| Drawing | `render/map_canvas.gd` | a regions layer between the grid and the walls (GM-audience regions only in the GM view), the scene's `highlight` | `test_map_events_over_the_wire_and_drawing` |
| Wire | `net/protocol.gd`, `host_session.gd` | `AUDIENCE_EVENTS`: GM regions and unrevealed cells are stripped from the client document; a region's audience change becomes add/remove for players; a cell's record and plugin state are sent only once revealed | same, via `_audience_events` |
| Reference plugins | `tests/plugins/` | `sample.ordered` strikes only within reach; `sample.focus` registers bands, throws within Close and highlights the reach; `sample.degrees` takes cover from LoS, bursts, lays a fire zone that burns for two rounds and damages whoever walks in, vetoes moves into a wall of force | `plugintest` |

Exit criterion met: each reference plugin uses the map (reach, bands,
templates + cover + zones); a closed door blocks sight and opening it
through an override restores it; a Player never receives a GM-audience
region or an unrevealed cell's state; the fuzzed and end-to-end replays
still reproduce the document byte for byte with scenes carrying the new
blocks. Screenshots of templates and zones are covered by the canvas
smoke test rather than per-platform images — the render tests in
`desktop-test` exercise the layer on all three desktops.

Decisions taken while building:
- Distances are in hex units, and bands are measured **edge to edge**
  so adjacent tokens are at 0 regardless of size; a plugin's band
  maxima are therefore `n + 0.5` for "n hexes apart".
- The map stays read-only: regions and per-cell state live on the
  scene in the encounter, and the ruleset owns their meaning via tags.
- `token_moved` is asked *before* the move applies, so a veto costs
  nothing to undo; `region_*` fire after, each as its own step inside
  the move's transaction.
- The scene's `highlight` is transient data in the document rather than
  a side channel: it replays, undoes and reaches Players like anything
  else.

### Phase 7 — Campaign, growth, hardening — **done 2026-09-21**

| piece | file | what it does | proven by |
|---|---|---|---|
| `Campaign` | `encounter/campaign.gd` | the `.campaign` document (docs/campaign-format.md): players, persistent actors and their resources, plugin order and settings, tracks, clock, campaign-scoped state, the journal, the sessions; `begin_session()` → events, `bank()` ← the encounter; `search_journal`; `for_encounter()` finds it beside the file | `tests/suites/rules_campaign.gd` (136 checks), `test_campaign_two_sessions_with_a_recap` |
| Sessions | `rules/kernel.gd` | `start_session(campaign)`: one step that brings the campaign in, runs session refills/expiries and `session_start`, and marks the `Session N start` checkpoint; `ext.set` scope `campaign` on the encounter's `campaign.ext` | same |
| Checkpoints (G5) | `encounter/encounter.gd`, `encounter_state.gd`, `rules/kernel.gd` | snapshots in the document: `checkpoint.mark/drop/restore` events (a restore is one undoable step that re-derives everyone and closes orphaned prompts), `Encounter.snapshot/restore_snapshot`; the host re-welcomes every client on a restore | `test_checkpoints_in_the_document` (replay reproduces a document with checkpoints, restore from a reloaded file is exact) |
| `Recap` (G6) | `rules/recap.gd` | `summary()` and `markdown()` from the log and the diff against the session-start checkpoint: who was there, where, read-aloud, what changed (actors, tokens, pools, tracks, effects, clock, state), dice per actor, rulings; a players' version leaves GM matter out; `diff()` is the "what happened since" beside any checkpoint | same, the recap dialog on the Table |
| `Triggers` (G3) | `rules/triggers.gd`, kernel | prep as data on scenes and regions: `enter`/`leave`/`scene`/`door`/`reveal`/`manual`; steps `read`, `note`, `spawn`, `actor`, `light`, `door`, `hide`, `reveal`, `track`, `effect`, `region`, `event`, `action` (the rules half, dispatched with prompts); `Triggers.due()` after every commit and after moves, fired after the step that set them off as their own undo steps; `once`/`fired`; a failing step undoes the trigger | `test_prep_triggers` |
| `Bulk` (G13) | `rules/bulk.gd`, `hm.bulk` | one op over many refs as one step: effect, resource (floors at zero), set/move/remove, roll-per-target with ops per outcome, action, each; capability per op kind from Lua | `test_bulk_operations`, `sample.degrees` `burst` (a save per target) |
| `Improv` (G4) | `rules/improv.gd`, `hm.improv`, the Improvise dialog | plugin benchmarks (`params` schema + `make`) → an actor with a token where the DM points; number-only actors under the `table` pseudo-plugin whose numbers are pools; a seeded name generator | `test_improvisation_without_plugins`, `sample.degrees` `creature` |
| Rulings (G18) | `hm.ruling`, log kind `ruling`, `Campaign.journal`, the Campaign pane | "we ruled that", with the rule and the roll; GM audience; banked into the campaign's journal with the session; searched from the pane | `test_campaign_two_sessions_with_a_recap`, `test_table_campaign_panel_and_dialogs` |
| Co-GM (G17) | `net/protocol.gd`, `host_session.gd`, `net_session.gd`, `player_window.gd` | role `cogm`, joined with the four-digit code the Players pane shows: the GM projection, the whole scene (GM regions, cells, triggers), scene requests for any token through the Table's commands, actions for any actor, answers for anyone, and the `gm` intent (next/previous turn, checkpoint, restore, trigger, bulk) | `test_cogm_role` (a player is refused the GM verbs and never sees GM regions) |
| Layering (G10) | `rules/hook_bus.gd`, `plugin_host.gd` | manifest `overrides` (must depend on what it overrides): the base's handlers for those hooks do not run; `load_all()` loads dependencies first in the campaign's order, `settings_overrides` from the campaign over the defaults; scratch test kernels carry a plugin's dependencies | `test_plugin_layering_and_campaign_order`, `sample.house` |
| Budgets | `tests/suites/rules_perf.gd` | expiry over 500 effects < 10 ms (was 80: link index made it linear), a Player projection < 5 ms, a checkpoint < 30 ms, a bulk op over 100 < 120 ms, a restore < 150 ms, a Lua hook round-trip < 0.5 ms median; ×3 on CI, skipped on phones | CI |
| Red team | `tests/suites/rules_sandbox.gd` | escapes, tampering, cross-plugin reach, capabilities, cyclic/deep/function-bearing data (now refused at the bridge by `plain()`), bad events, runaway loops, commit and roll storms (a wall-clock budget per call, `PluginHost.call_ms_budget`) | CI |
| Table | `table/campaign_panel.gd`, `table_window.gd`, `players_panel.gd` | the Campaign pane (session start/bank/recap, checkpoints, prep on the scene, journal + rulings), File › New/Open/Save campaign and Export recap, Edit › Checkpoint / Bulk on selected tokens / Improvise a creature, the co-GM code | `test_table_campaign_panel_and_dialogs` |
| Reference plugins | `tests/plugins/` | `sample.house` (house rules over `sample.ordered`); `sample.degrees` gained a benchmark, a ruling action and a bulk-save burst; `sample.ordered` keeps campaign-scoped luck; every plugin's tests now run in the suite and on every platform | `test_every_reference_plugin_passes_its_own_tests` |

Exit criterion met: a two-session campaign runs end to end on the
reference rules — session one starts from the campaign, is played,
banked with its journal, and session two picks up the hurt hero, the
luck, the ticked doom track and the day; a recap is generated between
them for the GM and for the players.

Decisions taken while building:
- A checkpoint is a snapshot in the document, not a position in the
  event log: it survives a reload and a restore is one event, so the
  log stays append-only, undo works and clients are simply re-welcomed.
- The campaign is not event-sourced. It is read at the start and
  written at the end of a session; everything in between is encounter
  events. Persistent actors travel without `derived`.
- Triggers fire *after* the step that set them off, as their own undo
  steps, so the DM can undo a trigger's effects without undoing the
  move or the door.
- The wall-clock budget per plugin call bounds what a plugin may cost
  the table through host calls; the instruction budget alone did not
  (a loop of cheap commits could run for seconds).
- A co-GM is a Player-window client with the GM audience and the GM's
  powers, not a second Table: the Table stays the one authority, and a
  phone or tablet is enough for the second screen. A networked Table
  window is not in scope.
- Everything crossing the Lua bridge is copied as plain data with a
  depth limit; a self-referencing table is an error, not a stack
  overflow in the extension.

### Phase 7b — API completion and square grids — **done 2026-09-21**

The 5e desirements audit (`ruleset-dnd5e/API-AUDIT.md`) checked all 33
items against API 1. Every Must item is reachable on the Table today; the
gaps are on the phone and in a few kernel corners, numbered H1–H12
there. Rather than meet them one at a time inside a ruleset, this phase
adds H1–H9 first, with the docs fix (H12) folded in, and one thing the
audit filed under "product": **square grids**. 5e, most published
battle maps and every other VTT default to squares; a "hex-only" VTT
would be one nobody moves a campaign to. H10 (transient cues, sound and
VFX assets) and H11 stay out: H10 is a large presentation feature for a
Could item, H11 is a label.

Order: the grid first, because everything after it (targets picked on
the map, templates, vision) must be tested on both shapes; then the
kernel-only changes (small, fast, no client work); then the client and
protocol work. Every step ends with `check` and `test` green locally
and the four workflows green at the milestone commits; each step is its
own commit; the reference plugins and the docs change with the step
that affects them. Formats stay at their versions: every change to a
document is additive with a default (`grid.shape` absent = hex).

| step | change | files | proven by |
|---|---|---|---|
| **S1 Square grids** | `HexGrid` gains `shape: "hex" \| "square"` (the class name stays; it is *the* grid). Square cells are addressed `col,row` in the same `q,r` keys, centre at `(col + ½, row + ½)`, four corners, four orthogonal neighbours (`neighbors(cell, diagonals := false)`), Chebyshev cell distance with the diagonal count reported so a ruleset can price diagonals (5-10-5, 5-5, Euclidean), `spiral`/`line`/`all_cells`/`map_size`/`in_bounds` per shape. The static geometry helpers become instance methods (`grid.distance`, `grid.spiral`, `grid.line`) and every call site is updated. Renderer draws N-gons (terrain UVs: `fit: square` is 1:1 on squares, hex-fit art is mapped to the cell's box), grid lines, fog, regions, highlights per shape. Editor: Shape in New map and Map settings (orientation/offset hidden for squares), brushes and walls work on squares. Exporters: Foundry `SQUARE` (1), Tiled `orthogonal`, UVTT as is, PDF/SVG/PNG generic. `MapQuery`: `distance` adds `diagonals`; templates, `within`, `cells_within/between`, `neighbors`, vision and light on both shapes. A square example map from `make_examples`. | `core/hex_grid.gd`, `core/hex_map.gd`, `render/map_canvas.gd`, `editor/tools.gd`, `editor/editor_window.gd`, `table/table_tools.gd`, `io/*`, `rules/map_query.gd`, `encounter/vision.gd`, `tools/make_examples.gd`, `docs/map-format.md`, `docs/exports.md` | `tests/suites/hex_grid.gd` → both shapes (centres, rounding, corners, neighbours, distance, spiral, line, bounds, offsets); `rules_map.gd` on a square scene (bands, templates, LoS, light, move); `exporters.gd` square fixtures; `document.gd` a v-current file without `shape` loads as hex; table/player smoke on a square map |
| **S2 Sender on the context (H1b)** | `HostSession` stamps `ctx.player` (the sender's id, `""` for the GM/co-GM) and `ctx.gm` on every dispatched action; the Table's own dispatch stamps `gm = true`. | `net/host_session.gd`, `table/rules_panel.gd`, `plugin_host.gd`, docs | `net.gd`: a plugin action sees who sent it and a spoofed `ctx.player` is overwritten |
| **S3 Targets picked on the map (H1)** | Action specs may declare `target = "token" \| "cell" \| "area"` (with `area = {shape, radius/length/angle/width}`). The Table's Rules panel and a sheet `button` with such an action enter a *pick*: the next tap on the map (Table tools, Player tools) supplies `ctx.target` (`token:<id>`, `"q,r"`, or `{at, direction}` for an area, previewed as a highlight while picking) and the intent is sent. The host accepts a token target only if that viewer's projection lists it (visible, not hidden, seen), a cell only if in bounds. The `gm` intent gains `pick` for co-GMs. | `rules/plugin_host.gd` (action schema), `table/table_tools.gd`, `table/rules_panel.gd`, `player/player_tools.gd`, `player/player_window.gd`, `ui/views/view_renderer.gd` (`button.pick`), `net/host_session.gd`, `net/protocol.gd` (docs only), `docs/plugin-authoring.md` | `rules_views.gd` / `table.gd`: a pick fills the ctx; `net.gd`: a hidden token as a target is refused, a visible one accepted, a cell out of bounds refused; `sample.ordered` gains a `throw` action with an area target and tests it with `t.dispatch` |
| **S4 Prompts without waiting (H2)** | `hm.prompt_open(to, form, opts) → id` (no yield) and a `prompt_answered` hook `{prompt, answer, by, context, timed_out}`; `hm.prompt_all(players, form, opts)` yields once and resumes with `{player → answer}` when all answered or the deadline passed (defaults fill the rest). `Pending` keeps a continuation per group. The GM can still override any of them. | `rules/pending.gd`, `plugin_host.gd`, `lua_prelude.gd`, docs | `rules_turns.gd`/`rules_lua.gd`: three players asked at once, two answer, one times out; `sample.degrees` `burst` asks every target's owner in parallel |
| **S5 Plugin-defined hooks (H5)** | `hm.hooks.run(name, payload) → payload`: runs `<plugin>.<name>` through every loaded plugin's handlers in load order, with `overrides` honoured; may prompt when called from an action (the run is driven like the action). `hm.on` accepts dotted names. | `rules/hook_bus.gd`, `plugin_host.gd`, `lua_prelude.gd`, docs | `rules_plugins.gd`: `sample.house` handles `sample.ordered.after_damage`; a veto from the layered plugin stops the base |
| **S6 Turn groups and helpers (H7)** | `hm.turns.reorder(order)`, `insert(ref, index)`, `remove(ref)`; order entries may be `group:<id>` with `turns.data.groups[id] = [token ids]`: one slot in the order, `turn_start`/`turn_end` for each member, budgets per member; Players see the group's label. `hm.turns.group(id, tokens, label)`. | `rules/turns.gd`, `plugin_host.gd`, `lua_prelude.gd`, `rules/views.gd`, `table/turns_panel.gd`, docs | `rules_turns.gd`: three goblins as one slot, hooks fire per member, undo restores the order |
| **S7 Compendium filters (H9)** | `filter` values may be `{min, max}` ranges, `{not = …}`, and keys may be paths (`stats/level`); facets over paths. | `rules/compendium.gd`, docs | `rules_content.gd` |
| **S8 Dark radius (H8)** | `vision.dark_radius`: how far the token sees unlit space. `MapQuery.can_see` sees an unlit target within it; `light_at` unchanged; `Vision` (fog reveal) unchanged (radius bounds it); the renderer lifts the darkness within an owned token's dark radius on the Player and the Table. | `rules/map_query.gd`, `render/map_canvas.gd`, `encounter/vision.gd`, `docs/encounter-format.md` | `rules_map.gd`: a target in the dark at 5 is seen with `dark_radius = 6`, not at 8 |
| **S9 Pausable move hook (H6)** | After a move is applied and its triggers ran, `after_move` runs as a driven hook: handlers may prompt (an opportunity attack offered to the other side's owner) and commit; a veto here does not undo the move (it already happened). | `rules/kernel.gd`, `plugin_host.gd`, `table/table_context.gd`, `net/host_session.gd`, docs | `rules_map.gd`/`rules_lua.gd`: a move past a token prompts its owner and the answer lands as events after the move |
| **S10 Compendium to clients (H3)** | Protocol `need {kind: comp, plugin, collection, id \| query}` → `comp {plugin, collection, entries \| entry, total}`; served by the host from `Compendium.query/get_entry` under the viewer's audience (entries public unless the pack or entry says `audience: gm`); `NetSession.comp(...)` with a callback; the Player's view renderer resolves `picker` collections through it. | `net/protocol.gd`, `host_session.gd`, `net_session.gd`, `rules/compendium.gd`, docs | `net.gd`: a player queries spells by level and gets a page; a `gm`-audience collection is refused |
| **S11 View widgets (H4)** | `picker` (search over a bound list or a collection; single/multi; `on_pick` intent with the chosen ids), `wizard` (steps with back/next; the submit intent carries every step's values), `repeater` in `form` (an array of sub-forms), `image` (pack art by ref), `field` (one bound value edited in place; `on_change` intent). Unknown widgets still degrade to text. | `ui/views/view_renderer.gd`, `ui/property_form.gd`, docs | `ui_views.gd`: each widget renders, fills its intent, degrades; `sample.degrees` sheet uses a `picker` for feats |
| **S12 Docs and closing** | `hm.map.token` accepts `token:<id>`; `view.ext` keyed by plugin id said plainly; `docs/plugin-authoring.md` covers every addition; `plugin-api-audit.md` §7 and `ruleset-dnd5e/API-AUDIT.md` §4 updated to "done"; perf budgets extended (square-grid templates, pickers over 1,000 entries, a compendium page to a client); all four workflows green on the closing commit. | docs, `rules_perf.gd` | CI |

Exit criterion: `sample.ordered` on a square map — a Player picks a
target by tapping it, throws at an area, three Players answer a save at
once, a house-rules plugin hooks the base's own `after_damage`, a goblin
pack acts as one slot, a darkvision token sees in the dark, a move past
a guard prompts the guard's owner, and the phone picks a feat from a
searchable list served by the Table — all green on desktop, Android and
iOS.

Delivered, step by step (one commit each, `51d20bf` … the closing
commit): the grid's `shape` with the cellar example and both shapes
under every test that touches geometry; `ctx.player`/`ctx.gm`;
`target = token | cell | area` with `MapQuery.pick_target`,
`PluginHost.check_target`, the Table's `PickTool` and the phone's pick;
`hm.prompt_all` and `hm.prompt_open` + `prompt_answered`;
`hm.hooks.run`; groups and `hm.turns.reorder/insert/remove/group/
ungroup`; range/not/path filters; `vision.dark_radius`; `after_move`;
`need {kind: comp}` and `Session.comp`; the `picker`, `wizard`, `image`
and `field` widgets and the `list` repeater. The reference plugins
gained `shove`, `throw_oil`, `volley`, `dare`, the opportunity strike,
`sign`, `learn` and the house rules' `after_damage`; the test count
went from 10,716 to 10,880. On the closing commit `8d79d5d` all four
workflows were green: `ci` 10,882 checks, `desktop-test` 10,876 on each
OS, `android-test` 10,494 in the phone build and 7 in the join test,
`ios-test` 10,494.

Decisions taken while building:
- The grid class keeps its name. `HexGrid` with `shape = "square"` is
  the grid; renaming it would have churned thirty files for a word.
- A square cell's key is `col,row` in the same `q,r` slot, so nothing
  that stores cells (terrain, fog, regions, cell state) knows the shape.
- A picked target is checked by the host, not the plugin: a Player's
  phone can only name what it can see, so an action may trust
  `ctx.target` the way it trusts `ctx.player`.
- Prompts nothing waits on are not orphans: they survive a restore and
  their answers arrive as a hook, so a question can outlive the action
  that asked it.
- A ruleset's own hooks are synchronous, like the kernel's step hooks;
  a base ruleset that wants to ask someone inside one uses
  `hm.prompt_open`.
- `after_move` is the one move hook that may pause, and it runs after
  the move is a fact: an opportunity attack cannot un-move anyone.
- The compendium goes to clients a page at a time, never whole, and
  only what the viewer's audience allows; GM secrets are a pack (or an
  entry) marked `audience: gm`.

### Phase 8 — Real rulesets — **in progress 2026-09-21**

Only now, and in their own repositories, the studied rulesets are written
against the API — with the licensing decisions taken then. The API is
declared 1.0 when the first of them ships without a host change it could
not have made through the plugin.

**The first ruleset: `srd5e`** (`Silvergrove-Studios/ruleset-dnd5e`,
`plugin/`), the 5E-compatible rules on SRD 5.2.1 and 5.1 (CC-BY-4.0),
built 2026-09-21 through the eleven milestones of its `PLAN.md`: packs
from Open5e (4,141 entries), a character sheet with tabs on the phone,
D20 Tests with advantage from conditions, the fifteen conditions,
concentration, damage and death, rests, a spellbook and casting with
areas, initiative with budgets, stat blocks onto the map, the attack
workflow with cover and opportunity attacks, class features, weapon
mastery, character creation and level-up, homebrew editors from the
collection schemas; 670 plugin checks plus an end-to-end session check
over the wire. Its `GAPS.md` is the record of what the API lacked. No
desirement was blocked; the host changes it produced are small:

| found by | change | commit |
|---|---|---|
| timing packs at SRD volume | `plugintest` prints the load time, entry count and test time | `82c538e` |
| the sheet's `versatile ? … : …` | `Expr.truthy` no longer compares a String to `false` | `8b8b6bc` |
| a requested-roll prompt on the phone | `PropertyForm.set_values` reads a null bool as unchecked | `db14401` |
| a 25 s plugin test run | `run_tests` indexes the plugin's packs once and shares them across tests (rebuilt after a test writes to a user pack): 28.7 s → 4.1 s for srd5e | this commit |
| H11 | the Rules panel shows each plugin's manifest `attribution` | `499ffc4` |
| a Roll initiative button on the GM panel (G3) | `hm.scene()` and `scene` in the status/gm view data | `3b69f73` |
| half cover from a creature vs a wall (G7) | `hm.map.los` counts the rays a wall stopped (`walls`) beside the tokens in the way | `0699165` |
| the 2014 paths untestable (G15) | `t.setting(key, value)` in the test harness, restored after each test | `0699165` |
| a monster's opportunity attack (G11) | `hm.prompt("gm", …)` already worked; documented | `0699165` |
| the sheet's Features tab (G16, G17) | Expr continues a path after a computed index (`@pools["hp_" .. @id].max`); a button's `if` inside an `action_bar` hides it | `98fed5b` |

Still open from `GAPS.md`, all small and none blocking: per-setting
packs (G5), a `picker` field inside forms and wizard steps (G9), one
rule for numeric-string Dictionary keys across the bridge (G13). H10
(cues) stays out.

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
