# Writing a ruleset plugin

A plugin is a directory with a `manifest.json` and Lua files. It runs on
the Table only, inside a sandboxed VM, and everything it does becomes
events in the encounter's log. Players never run plugin code; they
render what the plugin's data and derived numbers say.

This is the API as of plugin API version 1 (Phases 2–7b of
`docs/plugin-api-plan.md`).

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
  "overrides": {"other.plugin": ["after_roll"]},   layering: replace that plugin's handlers for these hooks ("*": all)
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
- **settings**: a JSON schema and defaults; a campaign's `plugins`
  list overrides the defaults per plugin. Read them with
  `hm.settings.get(key, default)`.
- **depends** and **overrides** are how rulesets layer: a house-rules
  plugin depends on its base, runs after it (its hooks see what the
  base's did to the payload), and may declare that for some hooks the
  base's handlers are not to run at all. The base's `derive` and
  actions stay; the overriding plugin adds its own. A campaign's
  `plugins` list fixes the order among what it names (a base always
  precedes what layers over it); the rest follow in load order.

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

What crosses to the host — every argument to an `hm.*` call, everything
a hook, `derive`, an action or a benchmark returns — is copied as plain
data: no functions, no table keys, no cycles, at most 32 levels deep. A
value that breaks the rule is a Lua error naming it. Besides the
instruction and memory budgets, one call into the plugin (an action from
start to finish, a hook, a derive) has a wall-clock budget (2 s on the
Table): a loop of commits or rolls that outlives it fails with "ran out
of time"; what it committed before that stands, undoably.

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
`owner`, `ext` (the actor's whole `ext`, keyed by plugin id — this
plugin's data is `view.ext[hm.id]` — with overlays merged in),
`effects` (on the actor and on its tokens), `resources` (name → record,
this plugin's), `tokens`, and `state` (the encounter's plugin state). Effects' `changes` are applied
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
| `turn_start`, `turn_end` | `{ref, actor, group, events}` | the participant gaining / losing the turn *or the focus*; `group` names the slot when it is a group's member |
| `round_start`, `round_end` | `{round, events}` | ordered shape only |
| `focus_changed` | `{from, to, by, events}` | asked *before* the focus moves: veto to refuse, add events for a cost |
| `rest` | `{kind, events}` | after refills and expiries |
| `session_start`, `scene_start` | `{session}` / `{scene}` | the second clock; `session_start` also fires when a session starts from a campaign, with campaign state already in |
| `time_advanced` | `{from, to, minutes, day, events}` | minutes are absolute since day 1 |
| `track_done` | `{track, roll, events}` | a progress track completed |
| `token_moved` | `{scene, token, actor, from, to, cells, entered, left, by, events}` | asked *before* a move applies: veto (a wall of force), add events (a cost); synchronous |
| `region_entered`, `region_left` | `{scene, token, actor, region, record, events}` | after a move, once per region crossed |
| `after_move` | `{scene, token, actor, from, to, cells, entered, left, by, events}` | once a move is done and its prep has fired. The one move hook that **may prompt** (an opportunity attack offered to the other side's owner): the move stands whatever happens, a veto changes nothing, and `events` land as their own step once the last handler is through |
| `prompt_answered` | `{prompt, answer, by, timed_out, plugin, context, events}` | a prompt opened with `hm.prompt_open` was answered (or timed out: the default, `timed_out = true`); `plugin` is whose prompt it was, `context` what it was opened with |

Handlers of the turn, clock and rest hooks run synchronously and may not
prompt; they append events to `payload.events` and the kernel commits
them with the step — the whole step is one undo entry, and a veto or a
refused event undoes all of it.

**A ruleset's own hooks.** Besides the kernel's, a plugin can publish
hook points of its own, so a house-rules plugin layered over it has
somewhere to stand inside the base's pipelines:

```lua
-- in the base ruleset's strike action, after the damage landed:
local p = hm.hooks.run("after_damage", { actor = ctx.actor, target = ctx.target, amount = amount })
if p.veto then error("after_damage: " .. p.veto) end
if #p.events > 0 then hm.commit(p.events, "After damage") end
-- in the layered plugin:
hm.on("sample.ordered.after_damage", function(p) if p.amount >= 6 then p.note = "hard hit" end return p end)
```

`hm.hooks.run(name, payload)` runs `<this plugin>.<name>` through every
loaded plugin's handlers in load order (the plugin's own included),
honouring `overrides`, and returns the payload with `veto` set if a
handler refused and `events` holding what they added — the caller
commits those, so a base ruleset decides where in its own step they
land. These hooks are synchronous: a handler that prompts is a veto.
Use `hm.prompt_open` there instead.

```lua
hm.actions.register("strike", { label = "Strike", cost = { actions = 1 }, target = "actor",
  run = function(ctx) … return { … } end })
```
An action the Table (and, from Phase 4, a Player's intent) can dispatch
with a context. Everything but `run` is public data the UI reads. The
host stamps two keys on every context before `run` sees it: `ctx.player`
(the id of the Player who sent the intent, `""` when the Table or a
co-GM did) and `ctx.gm` (`true` for the Table and its co-GMs). They come
from the connection, never from the wire, so an action may trust them —
for a target the sender does not own, check `ctx.gm` or that
`ctx.player` owns the acting actor.

**Targets.** `target` says what the action aims at and how the target is
chosen: `"actor"` / `"ref"` (from a list of the actors on the scene),
`"entry"` (a compendium entry, see below), or one *picked on the map* —
`"token"`, `"cell"` or `"area"`. For those the Table's Rules panel and a
phone's sheet button wait for a tap on the map, and `ctx.target` arrives
as `"token:<id>"`, a `"q,r"` cell key, or (for an area) a template spec
ready for `hm.map.template`: the action's `area = {shape, radius |
length, angle, width}` with `at` (the tapped cell for a circle, the
acting token for a cone or line), `direction` (degrees from the acting
token to the tap) and `from` filled in. `ctx.scene` is set too. The host
has already checked the target: a token on that scene the sender may
see (hidden tokens are the GM's alone), a cell in bounds, an area whose
origin is one of those. A sheet button asks for a pick by putting `pick
= "token" | "cell" | "area"` (and `area = {…}`) on its intent:

```lua
{ type = "button", label = "Shove", intent = { kind = "action", plugin = hm.id, action = "shove",
  ctx = { actor = "$/actor/id" }, pick = "token", label = "Shove" } }
```

`sample.ordered`'s `shove` and `throw_oil` are the reference.

```lua
hm.improv.register("creature", { label = "Creature by level",
  params = { level = { type = "integer", minimum = 0, maximum = 20, default = 1 }, role = { type = "string", enum = { "brute", "skirmisher" } } },
  make = function(p) return { name = "", kind = "npc", ext = { level = p.level, … }, token = { color = "#a83232", size = 1 },
                              resources = { [hm.id] = { hp = { kind = "pool", current = 20, max = 20, recharge = "rest" } } } } end })
```
An improvisation benchmark: "a level-4 brute, now". `params` is a
JSON-schema `properties` table the Table's Improvise dialog renders;
`make` returns an actor's data (`ext` is this ruleset's block, or a
whole `ext` keyed by plugin), token defaults and starting resources. A
blank `name` gets an invented one. Benchmarks may not prompt.

```lua
hm.test("name", function(t) … end)
```
See *Tests* below.

### The compendium

```lua
hm.schema.define("creatures", { type = "object", required = {"id", "name", "level"}, properties = { … } })
local page = hm.comp.query("creatures", { filter = { kind = "humanoid", level = {1, 2, 3} }, text = "gob", sort = "-level", page = 1, per_page = 20, fields = {"name", "level"}, facets = {"kind"} })
-- filter values: a value, a list (any of), { min = 1, max = 3 } (a range, either end
-- optional), { ["not"] = value | list }; keys may be paths into an entry's objects
-- ("stats/level"), and so may sort and facets
page.total, page.pages, page.entries, page.facets.kind          -- a page, never the whole collection
hm.comp.get("creatures", "goblin")   hm.comp.count("creatures")   hm.comp.collections()
hm.comp.put("creatures", entry)      -- into this ruleset's homebrew pack, checked against the schema
hm.comp.remove("creatures", id)
hm.comp.versions()                    -- {pack id: pack_version}, to stamp on actors you make
hm.comp.outdated(actor_id)            -- packs that changed since the actor was made
```

A schema declared for a collection name does three things: it checks
homebrew entries, it generates the Table's editor form for them, and it
tells the browser what the fields mean. Players' devices can read the
compendium too (a page or an entry at a time, asked of the Table, under
their audience: packs and entries marked `audience: "gm"` never reach
them), which is what the `picker` widget draws on. An action registered with
`target = "entry"` (and optionally `collection = "creatures"`) shows as
a button on an open entry in the Table's Compendium panel and is
dispatched with `ctx.entry`, `ctx.collection` and `ctx.scene` — the way
a creature becomes an actor on the map. The Table's encounter builder
(the Maps pane) searches that collection through the same action: give
it `fields = {"cr", "type"}` to show beside each name (and sort by the
first) — a field may also be `{key = "cr", label = "CR", values = {["0.25"] = "1/4"}}`
to name it and say how its raw values read —, `facets = {"type", "cr"}` for the filters it offers (a dropdown
of the values, or a range when they are all numbers), and
`query = {filter = {...}}` for a filter that always applies (the
campaign's rules version). Actors you make from entries should carry
`packs = hm.comp.versions()`.

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
`tracker`, `prompt`, `form {fields, submit}` (a field of type `list`
with its own `fields` is a repeater: an array of records, one sub-form
each), `log {limit}`, `spacer`, and:

- `picker {label, bind | collection, query, fields, per_page, search,
  multi, on_pick}` — a searchable list to choose from: a bound list of
  strings or `{id, name}` records, or a compendium collection the
  client fetches from the Table a page at a time (under its audience).
  A choice sends `on_pick` with `@pick` (the record) and `@pick_id`; with
  `multi`, a Done button sends `@picks` (the ids). This is how a Player
  picks a feat, prepares spells, or an encounter builder lists monsters.
- `wizard {label, steps = {{title, text, fields}}, submit}` — one step
  at a time with Back and Next; the last step's Submit sends `submit`
  with `"$values"` replaced by every step's values merged.
- `image {bind | src, height}` — pack art by ref (`pack:asset`).
- `field {label, bind, kind, on_change, options, min, max}` — one value
  edited in place (`kind` is a form field type); a change sends
  `on_change` with `"$value"` replaced. Sheets edited on the phone are
  fields and forms whose intents are actions that commit `actor.set`.

`"$values"` and `"$value"` are replaced wherever they sit in the intent.

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
| `hm.turns.reorder(order)`, `hm.turns.insert(entry [, index])`, `hm.turns.remove(entry)` | the ordered shape's order itself: a delay, a ready action, a late arrival, a departure. Entries are token ids or `group:<id>`; the participant whose turn it is stays current |
| `hm.turns.group(id, tokens, label)`, `hm.turns.ungroup(id)` | several tokens on one slot: the order holds `group:<id>`, `turns.data.groups[id]` holds the members, and each member gets its own `turn_start` / `turn_end` (payload `group = id`), budgets and expiries when the slot comes round. A group survives a restart |

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
| `hm.token(id)` / `hm.tokens(actor_id)` | a token (a bare id or `token:<id>`) / the tokens linked to an actor — each with the `scene` it is on |
| `hm.state.get(scope [, id])` | this plugin's `ext` at `"campaign"` (carried between sessions), `"encounter"`, `"scene"`, `"token"` or `"cell"` scope |
| `hm.campaign()` | `{id, session}` — which campaign this session belongs to |
| `hm.scene()` | the scene the Table shows (`""` when the encounter has none): where an action started from a panel rather than a pick on the map should act. The `status` and `gm` views' data carries it as `scene` too |
| `hm.checkpoint.list()` | the named snapshots in the encounter (needs `state`) |
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
`hm.ruling(text, { rule=, roll=, tags=, audience= })` records a ruling
("we ruled that…", with the rule it rests on and the roll that prompted
it): GM audience unless said otherwise, kept in the campaign's journal
between sessions, searchable from the Table's Campaign pane.
`hm.checkpoint.mark(name)` → id and `hm.checkpoint.restore(id)` are the
named snapshots of the whole encounter (needs `state`); a restore is
one undoable step.

### Bulk

One thing done to many refs as one undo step (a refusal on any target
undoes all of it):

```lua
hm.bulk.roll(targets, "1d20", { kind = "save", dc = 12 }, {
  failure = { { kind = "resource", plugin = hm.id, name = "hp", delta = -8 } },
  success = { { kind = "resource", plugin = hm.id, name = "hp", delta = -4 } },
}, "Fireball")
```
`hm.bulk.run(targets, op [, label])` takes an op: `{kind="effect",
effect}`, `{kind="resource", plugin, name, delta}` (spent below zero
floors at zero), `{kind="set", changes}` / `{kind="move", delta={dx,dy}}`
/ `{kind="remove"}` on tokens, `{kind="roll", spec, ctx, per={outcome={op…}}}`
(one roll per target with `ctx.actor` set; the ops under its outcome, or
`""` for any, follow), `{kind="action", plugin, action, ctx}`,
`{kind="each", ops={…}}`. `hm.bulk.effect`, `.resource` and `.roll` are
shorthands. Each kind needs the capability its single form would. The
result is a list of `{ref, …}` per target (`outcome`, `total` for rolls).

### The map

The map is read-only and the kernel does the geometry; a ruleset asks
questions and gets answers in **hex units** (one cell across = 1, on a
hex grid or a square one — the map says which, and the answers are in
the same terms either way). A *place* is `"token:<id>"`, a `"q,r"` cell
key (column, row on squares), or `{x, y}` / `{x, y}` as a two-element
list in hex units. Every call takes the scene id first.

```lua
hm.map.bands({ { name = "melee", max = 0.5 }, { name = "close", max = 5.5 }, { name = "far", max = 1e9 } })
```
Registers this ruleset's range bands, ascending, in *edge* distance
(token sizes taken off, so two adjacent medium tokens are at 0). The
last band is what lies beyond the rest. Bands are pure data: nothing
in Hexmap knows what "close" means.

| call | returns |
|---|---|
| `hm.map.distance(scene, a, b)` | `{units, edge, cells, diagonals, band}` — centre to centre, edge to edge, cell steps (hex steps, or Chebyshev on squares with `diagonals` saying how many of them were diagonal, so a ruleset can charge 5-10-5 or whatever it likes), and this ruleset's band |
| `hm.map.band(scene, a, b)` | just the band name |
| `hm.map.within(scene, origin, r)` | token ids whose edge is within `r` of the origin |
| `hm.map.template(scene, spec)` | `{cells, tokens, origin}` for `{shape="circle", at, radius}`, `{shape="cone", at, direction, length, angle}`, `{shape="line", at, direction, length, width}` or `{shape="band", at, band}`; `origin="edge"` starts cones and lines at the token's edge, `blocked_by_walls=true` drops what the origin cannot see |
| `hm.map.los(scene, a, b [, tokens_block])` | `{clear, cover="none" \| "partial" \| "total", blocked_by, walls, seen, of}` — rays to the target's centre and corners against walls (doors as they stand) and, by default, other tokens; `blocked_by` lists the tokens in the way and `walls` how many rays a wall stopped, so cover from walls and from creatures can be priced apart |
| `hm.map.light_at(scene, p)` | `{level="bright" \| "dim" \| "dark", sources}` |
| `hm.map.can_see(scene, viewer, target)` | within vision, sight clear, target lit — or within the viewer's `vision.dark_radius` (darkvision with a range; `dark_sight = true` in the answer) or the viewer's `vision.mode` is `"dark"`. A ruleset sets those with `token.set` from the sheet's senses |
| `hm.map.neighbors(scene, cell)`, `hm.map.cells_within(scene, cell, r)`, `hm.map.cells_between(scene, a, b)` | cell keys (six neighbours and a hex of hexes, or four and a square block) |
| `hm.map.cell(scene, key)` | the cell's record (`revealed`, plain fields, `ext`) with the map's `terrain` for it |
| `hm.map.regions_at(scene, cell)` / `hm.map.tags_at(scene, cell)` | the regions covering a cell / the union of their tags |
| `hm.map.token(scene, id)` / `hm.map.tokens(scene)` | a token (a bare id or `token:<id>`) / all of them |
| `hm.map.move(scene, token, to)` | `{events, entered, left, from, to, cells}` — nothing applied; the Table's own moves go through the kernel and the `token_moved` hooks |

What a ruleset may put on the map, as events for `hm.commit`:

| helper | event |
|---|---|
| `hm.map.region(id, cells, tags [, extra])` | a region record (`label`, `color`, `audience`, `duration` as for effects) — then `hm.map.region_add(scene, region)`, `hm.map.region_set(scene, id, changes)`, `hm.map.region_remove(scene, id)` |
| `hm.map.cell_set(scene, key, changes)` | plain fields on a cell (`revealed`, a note…) |
| `hm.map.cell_state(scene, key, changes)` | this ruleset's `ext` on a cell (a trap, a marker); Players receive it only once the cell is `revealed` |
| `hm.map.highlight(scene, cells [, color, label])` | show a template on the table; `hm.map.highlight(scene, nil)` clears it |

Regions with a `duration` expire with the same triggers as effects; a
token entering or leaving one fires `region_entered` / `region_left`.

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
The only way to wait. `to` is a player id, or `"gm"` for a question the
Table answers (a monster's reaction, a ruling). The action pauses; the Table records the prompt
in the encounter (`pending.prompts`, so a Player who reconnects still
sees it), shows the form to that Player (Phase 4), answers with the
default at the deadline, or lets the GM override; the call returns the
answer table. Needs the `prompts` capability. `derive` and the
turn/clock/rest hooks may never prompt.

Two more shapes of asking:

```lua
local answers = hm.prompt_all({ "pl_1", "pl_2" }, form, { default = { dodge = false }, deadline = 20 })
-- answers.pl_1, answers.pl_2 — one prompt per player, open at the same time; the
-- action resumes once when the last has answered or timed out
local id = hm.prompt_open("pl_1", form, { default = {…}, deadline = 60, context = { actor = "a_1" } })
-- nothing waits: the action goes on; the answer arrives as the
-- `prompt_answered` hook with `context` as given (a synchronous hook:
-- append events to `p.events`)
```

A group is how a save is asked of three Players at once with each
pressing their own button; an unattended prompt is how a question can
stay open across the rest of the action, or the session.

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
`t.commit(events, label)`, `t.setting(key, value)` (a campaign setting
for this test; the defaults come back for the next), `t.dispatch(action, ctx, answers)` (answers
are given to the action's prompts in order), `t.scene([map_path,
tokens])` → a scene id over a real map (the examples' chapel by default)
with `tokens = { { id=, actor=, x=, y= }, … }` placed by offset cell, for
map tests, `t.improvise(benchmark, params, scene, "q,r")` → the actor id
of a creature from one of this plugin's benchmarks placed on the scene.
Tests may not prompt themselves. A layered plugin's tests run with its
dependencies loaded. The Hexmap self-test runs the shipped plugins' tests on every
platform that has the runtime.

## Conventions

- Ids: `a_…` actors, `t_…` tokens, `e_…` effects, `r_…` rolls; use
  your own prefixes for what you create.
- Keep meaning in data where you can (conditions as tables of `changes`,
  costs and recharge kinds as strings) and reach for Lua for pipelines.
- Never put numbers on tokens or rules in the map: actors, effects,
  resources and state are where they live.
