# Writing a ruleset plugin

A plugin is a directory with a `manifest.json` and Lua files. It runs on
the Table only, inside a sandboxed VM, and everything it does becomes
events in the encounter's log. Players never run plugin code; they
render what the plugin's data and derived numbers say.

This is the API as of plugin API version 1 (Phases 2–5 of
`docs/plugin-api-plan.md`). Map queries arrive in Phase 6 and will be
added here.

## Layout

```
my.rules/
  manifest.json
  main.lua          the rules
  tests.lua         the plugin's own tests (optional, encouraged)
  packs/core/       content packs the ruleset ships (docs/content-format.md)
```

Run the tests with `./run.sh plugintest my.rules`. The reference plugin
is `tests/plugins/sample.ordered`: read it first.

## manifest.json

```json
{
  "id": "my.rules",              a stable id: letters, digits, dots, dashes
  "version": "0.1.0",
  "api": 1,                      the plugin API this was written against
  "name": "My rules",
  "description": "…",
  "license": "…", "attribution": "…",
  "files": ["main.lua", "tests.lua"],      loaded in order (default: main.lua)
  "packs": ["packs/core"],                 content packs to load, relative to the plugin
  "depends": ["other.plugin"],             must be loaded first; their hooks run first
  "capabilities": ["state", "prompts", "log", "actions", "effects", "resources", "dice", "content"],
  "policy": {"status": "best", "circumstance": "best"},
  "settings": {"schema": {…}, "defaults": {"critical_on": 20}},
  "tests": true
}
```

- **capabilities** gate what the plugin may do. Without `prompts` a yield
  is an error; without `state`, `ext.set` events are refused; without
  `log`, `hm.log` is; without `content`, `hm.comp.put/remove` are. The DM
  sees the list when installing.
- **policy** says how typed parts of the same type combine in this
  ruleset's numbers and rolls: `stack` (sum, the default), `best` (the
  largest bonus and the largest penalty of that type count) or
  `override` (last wins).
- **settings**: a JSON schema and defaults; campaigns override the
  defaults (Phase 7). Read them with `hm.settings.get(key, default)`.

## The sandbox

The VM has `base`, `coroutine`, `table`, `string`, `math` and `utf8` —
no `io`, `os`, `debug`, `require`, `load`, `getfenv`/`setfenv`. After
the files load, globals and the standard library are frozen. Each call
into the plugin runs in its own thread under an instruction and a memory
budget; a call that runs away is stopped and reported, and the Table
carries on. A Lua error inside a hook skips that handler; inside
`derive`, the plugin's block is left empty; inside an action, the action
fails with the message. All of it is logged against the plugin id.

`math.random` is the sandbox's own and is **not** the dice: use
`hm.dice.roll`, which draws from the encounter's recorded stream so a
replay reproduces every face.

## The `hexmap` library

`hexmap` (conventionally `local hm = hexmap`) is the whole API.

### Registration (at load time)

```lua
hm.schema.define("actor", { type = "object", required = {"level"}, properties = { … } })
```
A JSON schema (draft 2020-12 subset) for this plugin's actor data —
`actor.ext[hm.id]`. The kernel validates every `actor.add` and `actor.set`
against it; bad data is refused with a path.

```lua
hm.derive(function(view) return { defence = hm.num({…}), hp_max = 12, label = "…" } end)
```
The pure function from an actor's view to this plugin's derived block
(`actor.derived[hm.id]`). Called after anything about the actor changes;
must not commit, roll or prompt. The view has `id`, `kind`, `name`,
`owner`, `ext` (with overlays merged in), `effects` (on the actor and on
its tokens), `resources` (name → record, this plugin's), `tokens`, and
`state` (the encounter's plugin state). Effects' `changes` are applied
by the kernel to what derive returns, and typed numbers are re-totalled
under the policy.

```lua
hm.on("before_roll", function(p) … return p end)
```
A hook handler. It receives the payload, may change it, and returns it
(or nothing to leave it as is). Set `p.veto = "reason"` to stop the run.
Handlers of one plugin run in registration order; plugins run in load
order. A handler may `hm.prompt` (see below); the run pauses and resumes.

Hooks in API 1:

| hook | payload | what a handler does |
|---|---|---|
| `before_roll` | `{spec, ctx}` | add `spec.parts`, change `spec.expr`, veto |
| `after_roll` | `{spec, result, ctx}` | set `result.outcome` and anything else the log should show |
| `turn_start`, `turn_end` | `{ref, actor, events}` | the participant gaining / losing the turn *or the focus* |
| `round_start`, `round_end` | `{round, events}` | ordered shape only |
| `focus_changed` | `{from, to, by, events}` | asked *before* the focus moves: veto to refuse, add events for a cost |
| `rest` | `{kind, events}` | after refills and expiries |
| `session_start`, `scene_start` | `{session}` / `{scene}` | the second clock |
| `time_advanced` | `{from, to, minutes, day, events}` | minutes are absolute since day 1 |
| `track_done` | `{track, roll, events}` | a progress track completed |

Handlers of the turn, clock and rest hooks run synchronously and may not
prompt; they append events to `payload.events` and the kernel commits
them with the step — the whole step is one undo entry, and a veto or a
refused event undoes all of it.

```lua
hm.actions.register("strike", { label = "Strike", cost = { actions = 1 }, target = "actor",
  run = function(ctx) … return { … } end })
```
An action the Table (and, from Phase 4, a Player's intent) can dispatch
with a context. Everything but `run` is public data the UI reads.

```lua
hm.test("name", function(t) … end)
```
See *Tests* below.

### The compendium

```lua
hm.schema.define("creatures", { type = "object", required = {"id", "name", "level"}, properties = { … } })
local page = hm.comp.query("creatures", { filter = { kind = "humanoid", level = {1, 2, 3} }, text = "gob", sort = "-level", page = 1, per_page = 20, fields = {"name", "level"}, facets = {"kind"} })
page.total, page.pages, page.entries, page.facets.kind          -- a page, never the whole collection
hm.comp.get("creatures", "goblin")   hm.comp.count("creatures")   hm.comp.collections()
hm.comp.put("creatures", entry)      -- into this ruleset's homebrew pack, checked against the schema
hm.comp.remove("creatures", id)
hm.comp.versions()                    -- {pack id: pack_version}, to stamp on actors you make
hm.comp.outdated(actor_id)            -- packs that changed since the actor was made
```

A schema declared for a collection name does three things: it checks
homebrew entries, it generates the Table's editor form for them, and it
tells the browser what the fields mean. An action registered with
`target = "entry"` (and optionally `collection = "creatures"`) shows as
a button on an open entry in the Table's Compendium panel and is
dispatched with `ctx.entry`, `ctx.collection` and `ctx.scene` — the way
a creature becomes an actor on the map. Actors you make from entries
should carry `packs = hm.comp.versions()`.

### Views: what players see

```lua
hm.ui.register("sheet", {
  type = "column",
  children = {
    { type = "number", label = "Evade", bind = "/derived/evade" },
    { type = "track", label = "Hits", bind = "/resources/hp" },
    { type = "cards", bind = "/derived/hand",
      on_tap = { kind = "action", plugin = hm.id, action = "play", ctx = { actor = "$/actor/id", card = "$/card_id" } } },
    { type = "action_bar", actions = {
      { type = "button", label = "Act", cost = { actions = 1 },
        intent = { kind = "action", plugin = hm.id, action = "act", ctx = { actor = "$/actor/id" } } } } },
    { type = "effects", bind = "/effects" },
  },
})
hm.ui.register("status", { type = "text", expr = "'GM pool: ' .. (@state.pool ?? 0)", style = "header" })
hm.ui.register("gm", { … })
```

A view is data: what to show, bound to the data the Table projects for
the viewer, and which *intent* a tap sends. Clients never run plugin
code; a client that does not know a widget shows it as text. Three
kinds:

- **sheet** — rendered on the owner's phone (and for the GM) for each
  actor that carries this plugin's data. Its data: `me` (player id),
  `role`, `actor {id, name, owner, kind, mine}`, `ext` and `derived`
  (this plugin's blocks), `resources` (name → record), `effects`,
  `tokens`, `turns`, `clock`, `state` (this plugin's encounter state).
- **status** — the table-wide view every client sees. Data: `me`,
  `role`, `turns`, `clock`, `actors` (the ones this viewer may see, with
  this plugin's `derived` and `resources`), `tracks`, `prompts`, `rolls`,
  `log`, `state`.
- **gm** — a Table panel, with the status data for the GM audience.

Values: `text` (literal), `bind` (a JSON pointer, `"/derived/evade"`),
`expr` (an Expr over the data, `"'Level ' .. @ext.level"`). A node with
`if = "<expr>"` is hidden when it is false.

Widgets: `column`, `row`, `section {title}`, `tabs {tabs = {{title,
children}}}`, `text {style = header|dim|mono}`, `number` (a typed number
with its breakdown as tooltip), `pool {spend, gain}` (intents for the
− / + buttons), `track {on_mark, on_clear}`, `effects`, `list {bind,
item, empty}` (the item schema sees `@item` and `@index`), `cards
{on_tap}` (the tap sees `@card` and `@card_id`), `button {label,
intent, cost, enabled = "<expr>", accent}`, `action_bar {actions}`,
`tracker`, `prompt`, `form {fields, submit}`, `log {limit}`, `spacer`.

Intents are Dictionaries; string values that start with `$/` are
pointers into the data, filled in when the tap happens. What a client
may send: `{kind = "action", plugin, action, ctx}` (the Table checks
`ctx.actor` / `ctx.token` are the player's), `{kind = "answer", prompt,
answer}` (only the player a prompt is for), `{kind = "focus", ref}`
(one of their tokens or characters), `{kind = "contribute", roll, name,
expr}`. Displays may send none.

**Audience.** A player character's `ext` and `derived` are public except
the paths its `audience.fields` marks `owner` or `gm`; any other actor is
GM-only except the paths marked `all`, and is listed to players only when
`audience.visible` is `"all"`. Effects, tracks and log entries carry an
`audience` of `"all"`, `"gm"` or `"owner:<player>"`. This plugin's
encounter `state` is shown to everyone: keep secrets on GM-only actors
or in `gm`-audience records.

### Turns

```lua
hm.turns.register({ shape = "ordered", name = "Initiative", initiative = "initiative",   -- a derived path…
                    tie_break = "highest", budgets = { actions = 3, reactions = 1 } })
hm.turns.register({ shape = "focus", name = "Spotlight" })
```
`initiative` may also be a function `(view, token) -> number`, and `label
= function(view, init) -> string` names what the order shows. The DM
picks a strategy in the Turns panel; `hm.turns.start(scene, id)`,
`hm.turns.next()` and `hm.turns.stop()` do what its buttons do.

| call | |
|---|---|
| `hm.turns.current()` | the turns block: `strategy`, `running`, `order`, `turn`, `round`, `focus`, `counters`, `requests`, `history` |
| `hm.turns.focus()` / `hm.turns.holder_actor()` | the focus holder ref / the actor behind it |
| `hm.turns.set_focus(holder, by)` | move the focus (`"gm"`, `"token:id"`, `"actor:id"`); `focus_changed` may veto |
| `hm.turns.request(player, ref)` / `hm.turns.deny(ref)` | a Player's request for the focus |
| `hm.turns.counters(ref)` | this turn's budgets for a participant |
| `hm.turns.consume(ref, counter, n)` | a `turns.set` event spending from a budget, or nil when there is not enough |

### Tracks, the clock, rests

```lua
local doom = hm.tracks.make("Doom", 3, "countdown", { on = "roll_outcome", outcomes = { "failure_dark" }, amount = 1 }, "gm", "The gate opens.")
hm.commit(hm.tracks.add(doom), "Countdown")
hm.commit(hm.tracks.advance(doom.id, 1), "Tick")     -- links move too
hm.tracks.get(id)  hm.tracks.all()
```
Kinds: `countdown` (starts full, counts down), `clock` (starts empty,
counts up), `meter`. `advance.on`: `manual`, `roll`, `roll_outcome`,
`rest`, `long_rest`, `session`, `turn`. The kernel moves tracks after
rolls and rests and fires `track_done`.

`hm.clock.get()` → `{session, scene, day, minute, rests}`;
`hm.clock.advance(minutes)` (ends `time` effects, fires `time_advanced`);
`hm.clock.next_session()` (refills `session` resources, ends `session`
effects); `hm.clock.next_scene()`. `hm.rest(kind)` refills every
resource whose `recharge` is `kind`, ends effects of that duration,
moves `rest` tracks and fires `rest`.

### Rolls that wait

```lua
local id = hm.dice.open(spec, ctx, "Sneak", { "pl_1", "pl_2" }, 30)   -- who may contribute, deadline
hm.dice.contribute(id, "pl_2", "help", "1d6")
local entry = hm.dice.resolve(id)                                     -- named group "help" joins the roll
hm.dice.pending()
```

### Reading

| call | returns |
|---|---|
| `hm.actor(id)` | the actor's view (see derive), or nil |
| `hm.actors()` | actor ids |
| `hm.derived(id)` | this plugin's derived block for the actor |
| `hm.token(id)` / `hm.tokens(actor_id)` | a token / the tokens linked to an actor |
| `hm.state.get(scope [, id])` | this plugin's `ext` at `"encounter"`, `"scene"` or `"token"` scope |
| `hm.effects.on(ref [, key])` / `hm.effects.has(ref, key)` | effects on a ref (`"actor:a_1"`, `"token:t_1"`, `"encounter"`) |
| `hm.resources.get(ref, name)` | a pool or track record, or nil |
| `hm.settings.get(key [, default])` | a setting |
| `hm.value(n)` | a number's value whether typed or plain |

### Changing things

Nothing changes until it is committed. The helpers **return events**;
`hm.commit(events, label [, reason])` applies them as one undo step
(all or nothing) and refuses with a Lua error if any is invalid.

| helper | event(s) |
|---|---|
| `hm.effects.apply{ on=, key=, value=, label=, duration=, changes=, stack= }` | `effect.apply` or `effect.set` per the stacking rule, or nothing |
| `hm.effects.remove(id)` | `effect.remove` for it and anything linked to it |
| `hm.effects.expire{ kind=, of= }` | what a trigger ends (`turn_end`/`turn_start` of a token, `round`, `scene`, `rest`, `long_rest`, `session`) |
| `hm.effects.set(id, changes)` | `effect.set` |
| `hm.resources.set(ref, name, record)` | `resource.set` (records from `hm.resources.pool(current, max, recharge)` / `hm.resources.track(max, marked, extra, crossed, recharge)`) |
| `hm.resources.spend/gain(ref, name, n)` | a pool change, or nil when it cannot (overspend) |
| `hm.resources.mark/clear(ref, name, n)`, `hm.resources.cross(ref, name, slot [, crossed])` | track changes |
| `hm.resources.refill(kind)` | every pool and track of this plugin whose `recharge` is `kind` |
| `hm.state.set(scope, id, changes)` | `ext.set` (change keys may be `a/b/c` paths; `nil`… use JSON `null` semantics: a key set to a null-ish value is a removal only through the host, so prefer setting explicit values) |

Change keys that contain `/` are paths into the record
(`"ext/my.rules/stats/agi"`); plugin ids contain dots, so dots are
never separators.

`hm.log(text [, audience])` puts a note in the encounter log.

### Rolling

```lua
local entry = hm.dice.roll("1d20", { actor = id, kind = "attack", dc = 15 }, "Strike")
entry.result.total, entry.result.outcome, entry.result.dice, entry.result.groups.main.faces
```
The spec may be a table: `{ expr = "1d20", named = { hope = "1d12", fear = "1d12" },
parts = { {label=, type=, value=} }, kind = "attack", visibility = "gm" }`.
The roll goes through every plugin's `before_roll`, draws from the
stream, goes through `after_roll`, and lands in the log as a `roll`
entry. `ctx` is yours: whatever your hooks need (`actor`, `kind`, `dc`).
Expressions: `NdS`, `+`/`-`, `kh`/`kl`/`dh`/`dl` N, `rN` (reroll faces
≤ N once), `!` (explode), `minN`.

### Waiting on a Player

```lua
local answer = hm.prompt(player_id, { title = "Spend armour?", fields = { { key = "spend", type = "bool", label = "…" } } },
                         { default = { spend = false }, deadline = 30 })
```
The only way to wait. The action pauses; the Table records the prompt
in the encounter (`pending.prompts`, so a Player who reconnects still
sees it), shows the form to that Player (Phase 4), answers with the
default at the deadline, or lets the GM override; the call returns the
answer table. Needs the `prompts` capability. `derive` and the
turn/clock/rest hooks may never prompt.

### Typed numbers

`hm.num{ {label="base", type="base", value=10}, {label="agility", type="ability", value=3} }`
gives `{ total = 13, parts = {…} }`. Use them for anything a Player
should be able to see the reasons for; effects add their own parts.

## Tests

```lua
hm.test("a shaken attacker rolls at -2", function(t)
  local id = t.actor({ id = "a_1", ext = { [hm.id] = { level = 1, stats = {…} } } })
  t.dispatch("condition", { key = "shaken", target = "actor:" .. id })
  local r = t.roll_with_faces({ main = { 15 } }, "1d20", { actor = id, kind = "attack", dc = 16 })
  t.eq(r.result.total, 13, "15 - 2")
end)
```
Each test runs on a fresh scratch encounter with a fixed dice seed.
`t.ok(cond, msg)`, `t.eq(a, b, msg)`, `t.actor(data)` → id,
`t.roll_with_faces(faces, spec, ctx)` (typed-in faces, nothing drawn),
`t.commit(events, label)`, `t.dispatch(action, ctx, answers)` (answers
are given to the action's prompts in order). Tests may not prompt
themselves. The Hexmap self-test runs the shipped plugins' tests on every
platform that has the runtime.

## Conventions

- Ids: `a_…` actors, `t_…` tokens, `e_…` effects, `r_…` rolls; use
  your own prefixes for what you create.
- Keep meaning in data where you can (conditions as tables of `changes`,
  costs and recharge kinds as strings) and reach for Lua for pipelines.
- Never put numbers on tokens or rules in the map: actors, effects,
  resources and state are where they live.
