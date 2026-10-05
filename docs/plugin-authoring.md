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
  `hm.settings.get(key, default)`. The DM changes them in *Rules
  settings* on the DM's screen (strings, booleans and numbers: a
  property's `title` says what it is, an `enum`'s `enumNames` how each
  choice reads); a change is kept in the campaign and the rules are
  loaded again with it, so a view built from a setting shows the new
  one.
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
under the policy. Changes that `override` come after all the others,
whatever order the effects are in: a number an effect sets is that
number (a Speed of 0 beside a bonus to speed is 0); the rest go in the
effects' order.

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
| `combat_end` | `{scene, round, events}` | the turns end (End turns, End the fight): put away what was the fight's own — its initiative, say — with the events the step commits; a veto keeps the turns running |
| `focus_changed` | `{from, to, by, events}` | asked *before* the focus moves: veto to refuse, add events for a cost |
| `rest` | `{kind, events}` | after refills and expiries |
| `session_start`, `scene_start` | `{session}` / `{scene}` | the second clock; `session_start` also fires when a session starts from a campaign, with campaign state already in |
| `time_advanced` | `{from, to, minutes, day, events}` | minutes are absolute since day 1 |
| `track_done` | `{track, roll, events}` | a progress track completed |
| `token_moved` | `{scene, token, actor, from, to, cells, entered, left, by, events}` | asked *before* a move applies: veto (a wall of force), add events (a cost); synchronous. An object's move (below) comes with `actor = ""` |
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
code; a client that does not know a widget shows it as text, and a Table
that does not know a view kind keeps it and never draws it (so a plugin
written for a newer Table still loads; one older than a kind refuses it,
so register a new kind with `pcall(hm.ui.register, …)`). The kinds:

- **sheet** — rendered on the owner's phone (and for the GM) for each
  actor that carries this plugin's data. Its data: `me` (player id),
  `role`, `actor {id, name, owner, kind, mine}`, `ext` and `derived`
  (this plugin's blocks), `resources` (name → record), `effects`,
  `effect_keys` (the keys of those effects, for an `if`: `"'prone' in
  (@effect_keys ?? [])"` — an Expr can't search a list of records),
  `tokens`, `turns`, `clock`, `state` (this plugin's encounter state),
  `party` (the other player characters and companions, `{id, name}`:
  whom to hand something to).
- **status** — the table-wide view every client sees. Data: `me`,
  `mine` (the ids of this player's own actors: offer a new character only
  when it is empty), `role`, `turns`, `clock`, `actors` (the ones this
  viewer may see, with this plugin's `derived` and `resources`), `tracks`,
  `prompts`, `rolls`, `log`, `state`.
- **gm** — a Table panel, with the status data for the GM audience.
- **party** — the Table's World view, on screen all session: the party
  at a glance and what a DM asks of them while they talk and explore.
  Same data as `gm`, whose view the Table shows when there is no `party`.
  Its buttons may send `{kind = "show", actor = "$/item/id"}` (or `ref =
  "actor:<id>"`): the Table opens that card in its Reference pane.
- **entry:&lt;collection&gt;** — how an entry of that collection reads
  when looked up: in the Compendium pane, in the lookup popup (View →
  Look up…, Ctrl/Cmd+L), and on a phone when a sheet's button sends
  `{kind = "lookup", collection, id}`. Data: `entry` (the record),
  `role`, `me`, `facts` (the scalar fields as strings). Read-only; a
  collection with no card gets a generic one (name, facts, text).

Values: `text` (literal), `bind` (a JSON pointer, `"/derived/evade"`),
`expr` (an Expr over the data, `"'Level ' .. @ext.level"`). A node with
`if = "<expr>"` is hidden when it is false; so is a tab of a `tabs` node
(the DM's own tab on a sheet: `{ title = "Adjust", ["if"] = "@role ==
'gm'", children = {…} }`), and a `tabs` node left with one tab is drawn
without a bar of one. A `text` node with
`rich = true` renders rules text as the SRDs write it — `**bold**`,
`*italic*`, `# headings`, `- ` bullets, paragraphs.

Widgets: `column`, `row`, `section {title}`, `tabs {tabs = {{title,
children}}}`, `text {style = header|dim|mono}`, `title {sub, icon}` (a
card's heading: the name, a line under it, an icon — a pack ref — when
there is one), `facts {items = {{label, text | bind | expr, if, rich}}}`
(labelled facts, an empty one left out), `tags {items = {{text | expr,
if, tone = "accent"}}}`, `number {signed}` (a typed number
with its breakdown as tooltip; `signed = true` reads it as a modifier,
"+2" or "-1"), `pool {spend, gain}` (intents for the
− / + buttons), `track {on_mark, on_clear}`, `effects`, `list {bind,
item, empty}` (the item schema sees `@item` and `@index`), `cards
{on_tap}` (the tap sees `@card` and `@card_id`), `button {label,
intent, cost, enabled = "<expr>", accent}`, `action_bar {actions}`,
`tracker`, `prompt`, `form {fields, values, submit, submit_label, keep,
done}` (a field of type `list` with its own `fields` is a repeater: an
array of records, one sub-form each; on the web screens a form the Table
took starts over from its `values` and says `done` — "Done ✓" unless
given — beside its button for a moment, and one refused keeps what was
typed; `keep = true` keeps what was sent too, for a form sent again and
again with a change or two), `log {limit}`, `spacer`, and:

- `picker {label, bind | collection, query, fields, sort, per_page,
  search, multi, sub, detail, on_pick}` — a searchable list to choose
  from: a bound list of strings or `{id, name}` records, or a compendium
  collection the client fetches from the Table a page at a time (under
  its audience). A query's `{expr = "…"}` values are worked out from the
  data (`level = {max = {expr = "@derived.spell.classes.druid.max_level"}}`:
  a class's spells up to the level it casts). `sub` is a line under each
  name (an Expr over `@item`), `detail` a collection whose card a "?"
  opens. `pick_label` (an Expr over `@item`, `"'Learn ' .. @item.name"`)
  makes each choice a button that says what it does, and the card's "?"
  a Read button. A choice sends `on_pick` with `@pick` (the record) and
  `@pick_id`; with `multi`, a Done button sends `@picks` (the ids). This
  is how a Player picks a feat, prepares spells, or an encounter builder
  lists monsters. Its search, like a `choose` field's and a collection
  query's `text`, takes the words typed in any order, each the start of a
  word, punctuation aside: "hooded lan" finds "Lantern, Hooded".
- `wizard {label, steps = {{title, text, fields, if}}, submit,
  submit_label}` — one step at a time with Back and Next; the last
  step's Submit sends `submit` with `"$values"` replaced by the values
  of every step and field that applies. A step's or a field's `if`, and
  any field property or step `text` written `{expr = "…", default = …}`,
  see the view's data and `@values` (the answers so far) and `@chosen`
  (for an answer picked from a compendium `collection` or a list of
  records, that whole record: the class chosen, with what the class entry
  carries; the package picked, with its items). A step's text reads as
  rules text does (`**bold**`, paragraphs), and a step may have no fields:
  a last step that says what the answers give.
  Next waits until the step's fields are right — a `required` field
  filled (`required_text` says so), a `scores` or `choose` field
  complete — and says what is missing; a field's `help` is a line under
  its label. The step and the answers are kept in the browser until the
  wizard is done (a phone that drops the page comes back to them); once
  the Table takes what it sends they go, and it starts over at its first
  step — a wizard that stands on a sheet for each level asks each level
  afresh. A refused one keeps its answers, to put right.
- `image {bind | src, height}` — pack art by ref (`pack:asset`).
- `field {label, bind, kind, on_change, options, min, max}` — one value
  edited in place (`kind` is a form field type); a change sends
  `on_change` with `"$value"` replaced. Sheets edited on the phone are
  fields and forms whose intents are actions that commit `actor.set`.

Besides `string`, `text`, `int`, `float`, `bool`, `enum`, `color`, `vec2`
and `list`, a form or wizard field may be:

- `choose {options | collection + query, count | min + max, single,
  allowed, fixed, fixed_label, what, fields, sub, detail, search}` —
  some of a list of described options: records `{id, name, text, tag,
  sub}`, or a collection's entries (their `fields` fetched with the
  name and text, `sub` an Expr over `@item` for the line under each).
  `allowed` limits what may be chosen, `fixed` is had already (shown
  ticked and locked, not counted), `count` how many to choose (the
  counter counts down; nothing past it can be picked; with fewer on
  offer than it asks — `allowed`, less `fixed` — Next asks for all
  there are, and for none when none is left: a level once asked a
  cleric for an eighth cantrip of seven), `single` just one. `empty`
  says why there is nothing to choose. Its value: a list of ids, or
  one id with `single`. `detail` names a collection whose card a "?"
  opens. Skills, spells, an equipment package. (The plugin checks the
  value again: a client's leniency is no rule.)
- `scores {stats, method, point_buy, array, rolled, manual, primary,
  suggest, who, bonus}` — numbers for named stats (`{id, name, text,
  uses}`), made by `method`: `point_buy` (`{budget, min, max, cost}`:
  − / + that never go out of range or past the budget), `array` (the
  numbers, each given to one stat), `rolled` (`{values, roll}`: the
  numbers the table rolled, and the intent that rolls them), or
  `manual` (`{min, max}`, typed). `primary` marks what the choice
  before wants (a class's key abilities) and `suggest` fills it in
  (`who` names it: "Suggested for a Druid"). `bonus {among, patterns,
  cap, source}`: increases on some of the stats (+2 and +1, or +1 to
  each of three). Its value: `{method, base, bonus, final}`. The client
  keeps it within the method; the plugin checks it again.

A client that does not know a field type shows a line of text for it.

An `enum` with no value shows none chosen on the web screens ("Choose…",
unless one of its options is itself the empty value), not its first option
as if picked; on the desktop form, mark it `required = true` for the same
(else the desktop selects the first, as it always has). For a choice the
rules leave to the player and nothing may take for them (srd5e: a summoned
dragon's breath), check the answer has one.

A form or wizard field may take its choices from the compendium instead
of a fixed list: `{key = "class", label = "Class", type = "enum",
collection = "classes", query = {filter = {subclass_of = ""}}, limit =
200, optional = false}`. The client asks the Table for that collection
under its own audience and fills the control when the answer arrives, so
the choices are what the campaign actually has — its packs, less what it
turned off, plus what it imported. The value the intent carries is the
entry's id. **Do not hardcode a list of your own content** (the classes,
the species): a campaign that disables one, or imports another, must see
that where a character is made.

A field may also take its choices from the view's own data: `{key =
"who", type = "enum", from = {bind = "/actors", ["if"] = "@item.kind ==
'pc'", first = {{id = "", name = "The whole party"}}}}` — the `first`
records, then each record at `bind` passing `if` (an Expr over `@item`),
as `{id = <id expr, default @item.id>, name = <label expr, default
@item.name>}`, then the `last` records (`last = {{id = "else", name =
"Someone else…"}}`: a choice that points to another field, after the
characters).

`"$values"` and `"$value"` are replaced wherever they sit in the intent.

Intents are Dictionaries; string values that start with `$/` are
pointers into the data, filled in when the tap happens. What a client
may send: `{kind = "action", plugin, action, ctx}` (the Table checks
`ctx.actor` / `ctx.token` are the player's), `{kind = "answer", prompt,
answer}` (only the player a prompt is for), `{kind = "focus", ref}`
(one of their tokens or characters), `{kind = "contribute", roll, name,
expr}`. `{kind = "lookup", collection, id}` never reaches the Table: the
device opens the entry's card (the phone fetches the entry under its
audience). Displays may send none.

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
| `hm.turns.current()` | the turns block: `strategy`, `running`, `order`, `turn`, `round`, `focus`, `counters`, `requests`, `history`, `scene` (the one the order is for), `last` (the turn that ended: `{by, entry, round, turn, at}`) and `data` (the strategy's own: `labels`, `groups`, and `notes` — token id → a line the screens show with that token's turn, its player's header and the DM's order: "Movement 15 of 30 ft"; a ruleset keeps it with `{ t = "turns.set", changes = { ["data/notes/<token>"] = "…" } }`) |
| `hm.turns.next([by, expect])` | end the current turn and start the next. `by` says who ended it (a player's id, `"gm"`, or this plugin when not given): a player's end is noted in the log for everyone. `expect = {round, turn}` is the turn meant: when it has already ended, nothing changes and the call fails saying whose turn it is now |
| `hm.turns.focus()` / `hm.turns.holder_actor()` | the focus holder ref / the actor behind it |
| `hm.turns.set_focus(holder, by)` | move the focus (`"gm"`, `"token:id"`, `"actor:id"`); `focus_changed` may veto |
| `hm.turns.request(player, ref)` / `hm.turns.deny(ref)` | a Player's request for the focus |
| `hm.turns.counters(ref)` | this turn's budgets for a participant |
| `{ t = "turns.set", changes = { ["data/skip/<token>"] = true } }` | that token loses its next turn: when it comes, the turn begins (its `turn_start` hooks run, what ends then ends) and ends at once, and the next one begins, in the same step; the mark goes as it's used (`false` takes it back). A group's slot goes by when every member is marked |
| `hm.turns.consume(ref, counter, n)` | a `turns.set` event spending from a budget, or nil when there is not enough |
| `hm.turns.reorder(order)`, `hm.turns.insert(entry [, index])`, `hm.turns.remove(entry)` | the ordered shape's order itself: a delay, a ready action, a late arrival, a departure. Entries are token ids or `group:<id>`; the participant whose turn it is stays current. `remove` of one member of a group's slot takes it out of the group (the others keep the slot; an emptied group leaves the order) |
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
| `hm.map.within(scene, origin, r)` | token ids whose edge is within `r` of the origin (creatures: objects are never among them) |
| `hm.map.template(scene, spec)` | `{cells, tokens, origin}` for `{shape="circle", at, radius}`, `{shape="cone", at, direction, length, angle}`, `{shape="line", at, direction, length, width}` or `{shape="band", at, band}`; `origin="edge"` starts cones and lines at the token's edge, `blocked_by_walls=true` drops what the origin cannot see; `tokens` are the creatures in it, and objects too with `objects=true` |
| `hm.map.los(scene, a, b [, tokens_block])` | `{clear, cover="none" \| "partial" \| "total", blocked_by, walls, seen, of}` — rays to the target's centre and corners against walls (doors as they stand) and, by default, other tokens (creatures: an object gives no cover); `blocked_by` lists the tokens in the way and `walls` how many rays a wall stopped, so cover from walls and from creatures can be priced apart |
| `hm.map.light_at(scene, p)` | `{level="bright" \| "dim" \| "dark", sources, ambient}` — from the scene's own light (`ambient`: `daylight` is bright everywhere, `dim` dim), raised by the lights that reach the point: the map's, those tokens carry, and those effects put at places (below) |
| `hm.map.can_see(scene, viewer, target)` | the viewer sees (`vision.radius` above 0), sight clear, target lit — or within the viewer's darkvision (`vision.dark_radius` in its `units`; `dark_sight = true` in the answer) or the viewer's `vision.mode` is `"dark"`. No range: in light a line of sight is enough. A ruleset sets those with `token.set` (and the actor's `token.vision`, which a token placed later starts from) from the sheet's senses, in the sheet's own units: `{ dark_radius = 60, units = "ft" }` — the Table turns them into hexes by the map's scale, which a plugin cannot see |
| `hm.map.neighbors(scene, cell)`, `hm.map.cells_within(scene, cell, r)`, `hm.map.cells_between(scene, a, b)` | cell keys (six neighbours and a hex of hexes, or four and a square block) |
| `hm.map.cell(scene, key)` | the cell's record (`revealed`, plain fields, `ext`) with the map's `terrain` for it — and that terrain's `tags` from its art (a pack's rubble is `"difficult"`), when the Table has the art |
| `hm.map.regions_at(scene, cell)` / `hm.map.tags_at(scene, cell)` | the regions covering a cell / the union of their tags |
| `hm.map.path(scene, a, b [, opts])` | the cheapest way from `a` to `b` cell by cell (six neighbours, or eight on squares), round the walls that stop movement (doors as they are; a diagonal never cuts a wall's corner): `{ok, cells, steps, cost, step_costs, step_lengths, length, diagonals, costly, space, why, through}`. Each cell entered costs 1, or what the ruleset says: `costs = {tag = n}` by the cell's tags — its regions' and its terrain's — the dearest that applies, and on top of it `extra = {tag = n}`, what each of its tags adds (swimming a cell more: `{water = 1}`, so difficult water is 2 + 1); `free = {tag, …}` ground of those kinds pays none of `costs` (boots that ignore ice: `{"ice"}`); these three read the cell's tags and its terrain's own name (the art's id without its pack: `"rubble"`); `cell_costs = {["q,r"] = n}`; `blocked = {"q,r", …}` can't be entered; `diagonals = "5-5-5" \| "5-10-5" \| "euclid"`; `size` the mover's space in cells across, as its token's `size` (a square of 2 by 2 for 2, three hexes on a hex grid; 3 by 3 or seven hexes for 3): the whole space goes the way — on the map, none of it blocked, no wall through it or crossed — its token on one of its cells: each step of the token takes the space along, or leaves it where it is and steps within it (a step into several cells at once costs the dearest of them; `space` is where it ends); `max` a cost to stop looking at. `length` is the same way at 1 a cell; `step_costs` what each step cost, `step_lengths` each at 1 a cell. Not `ok`: `why` is `"walls"`, `"narrow"` (a way only for something smaller), `"no room"` (the space can't be there), `"blocked"` (only through blocked cells: `through` lists those on the shortest), `"far"`, `"off the map"` or `"no map"`. A ruleset counting a creature's movement asks it in `token_moved` (from `p.from` to `p.to`) |
| `hm.map.space(scene, at [, size, opts])` | `{cells, fits, why}` — the cells a creature `size` cells across (by default the token's own, when `at` is one) covers standing at `at`: its token's cell is one of them, the first way it fits (on the map, no wall through it, none of `opts.blocked`); `fits = false`, `why = "no room"` when none does |
| `hm.map.token(scene, id)` / `hm.map.tokens(scene)` | a token (a bare id or `token:<id>`) / all of them |
| `hm.map.move(scene, token, to)` | `{events, entered, left, from, to, cells}` — nothing applied; the events move what is attached to the token too (tokens, and regions: below); the Table's own moves go through the kernel and the `token_moved` hooks |

What a ruleset may put on the map, as events for `hm.commit`:

| helper | event |
|---|---|
| `hm.map.region(id, cells, tags [, extra])` | a region record (`label`, `color`, `audience`, `duration` as for effects; `attached_to`, `area` and `effect`: below) — then `hm.map.region_add(scene, region)`, `hm.map.region_set(scene, id, changes)`, `hm.map.region_remove(scene, id)` |
| `hm.map.cell_set(scene, key, changes)` | plain fields on a cell (`revealed`, a note…) |
| `hm.map.cell_state(scene, key, changes)` | this ruleset's `ext` on a cell (a trap, a marker); Players receive it only once the cell is `revealed` |
| `hm.map.highlight(scene, cells [, color, label])` | show a template on the table; `hm.map.highlight(scene, nil)` clears it |

Regions with a `duration` expire with the same triggers as effects; a
token entering or leaving one fires `region_entered` / `region_left`.

**Lights creatures carry.** A token's `light` (`{bright, dim, color,
angle, direction, shadows}`, `dim` the outer radius) moves with it, and so
does the `light` of any effect on the token or on its actor — a light that
lasts as long as an effect does (a blessed blade's for ten minutes) goes on
the effect and ends with it. Either may name its `units`: `{ bright = 20,
dim = 40, units = "ft" }` is turned into hexes by the map's scale, as
`vision.dark_radius` is; without units the radii are hexes. The rules'
questions (`light_at`, `can_see`) count every one; the fog and what a
player's screen shows count all but a hidden token's (its torch would give
away the creature the DM hasn't revealed). An effect's light that names a
place — `at`, a point as a token's `pos`, on its `scene` — stands there
instead, wherever its creature goes, and goes out with the effect: a rod
planted in the ground, a spell's sunlight at a point (`{ bright = 60, dim =
120, units = "ft", at = { x, y }, scene = scene }`). `light_at` names it
`effect:<id>` among its `sources`.

### Objects on the map

A spell that puts a thing on the map — lights its caster moves about, a
floating hand, a sphere of fire, the beam of a moonlit spell, a torch set
down — puts a token tagged `object`. It is a thing, not a creature:

- **It shares a space with anything.** Its owner may move it onto a
  creature's space (their own character's), and a creature onto its space;
  the web screens never say "That space is taken" for one. Only creatures
  stop creatures (a ruleset's own rule for where a creature may end its
  move sees that an object has no actor).
- **It is never a target** — unless it has an `actor` (below). Picks on
  the map pass over it to the creature under it; a pick's list leaves it
  out; `check_target` refuses it as a token target ("… is a thing, not a
  creature"), though an area may start at one; `hm.map.template`'s
  `tokens` and `hm.map.within` leave it out (`objects = true` on a
  template brings them in); `hm.map.los` counts no cover from it; it takes
  no turn (the order leaves it out).
- **A thing with statistics is a target.** An object token that has an
  `actor` (a floating hand with hit points, a servant, an image that any
  damage ends) is picked, listed and accepted by `check_target` like a
  creature (`Encounter.is_target`), so it can be attacked and damaged; it
  still shares its space, gives no cover, takes no turn and stays out of an
  area's `tokens` unless `objects = true`.
- **It sees nothing unless given vision.** A token tagged `object` with no
  `vision` gets `{ radius = 0 }`. Give one `vision` (an eye with darkvision:
  `{ radius = 1, dark_radius = 30, units = "ft" }`) and its player sees
  through it as through their own token, their fog explored by its moves.
- **Only its owner may see it**, with `audience = "owner"` (a thing
  invisible to all but its caster: an unseen servant, a phantom hound):
  the other players' screens never get it; the DM's does.
- **It is drawn as a thing**: a diamond of its own `size` (under 1 for
  something Tiny: 0.5), in its `color` — or, when it has a `light`, that
  light's colour, glowing — with its owner's ring. Over a creature whose
  space it shares it sits at the space's upper corner, small, so a tap on a
  phone finds either; one bigger than a space lies faint under the
  creatures. Its own `light` shines as any token's does. One tagged
  `likeness` too (a double of its caster, an image of them) is drawn as
  the creature it copies — its picture, its ring — though it is no more a
  target than any thing.
- **It moves as a character does.** Its owner (`owner`, a player id) moves
  it the way they move their character — tap it, then where; or drag it —
  whenever one of their creatures may move (in a fight, on their turn); the
  DM moves it like any token and can take it off the map. `token_moved`
  and `after_move` fire for it as for a creature, with `actor = ""`: the
  ruleset says who may move it, when (a Bonus Action, once a turn), how far
  and where, and what the move does, vetoing with the reason.
- **It goes with its effect.** A token or a region that names an effect id
  (`effect = "e_…"`) is removed when that effect is — ended, expired, its
  concentration broken (an effect `linked` to it), cleared by hand — in the
  same step, and an undo brings them back together. A ruleset that removes
  some of them itself in the same batch is not refused.
- **A region can move with a token.** A region `attached_to` a token id
  moves with it, and with a token attached to that one (a torch carried by
  a creature's token, its light's area with it): its `area` — a template
  spec without `at`, `{ shape = "circle", radius = 1 }` — is laid round the
  token where it now stands, as `hm.map.template` would lay it round the
  token (`size = 0` in it lays it round the token's middle, as round a
  point: a cylinder centred where a beam is); with no `area` its cells move
  as many cells as the token did. The
  mover never enters or leaves an area attached to it (`region_entered`
  and `region_left` don't fire for it); `hm.map.move`'s events carry the
  area along too.

```lua
-- a light of Wren's, linked to her spell's effect; the area under a beam
hm.commit({
  { t = "token.add", scene = scene, token = { id = "t_dl_1", name = "Light 1", label = "L1", pos = { x, y },
      size = 0.5, tags = { "object" }, owner = player, effect = fx_id, color = "#fff1c0",
      light = { bright = 0, dim = 10, units = "ft", color = "#fff1c0" } } },
  hm.map.region_add(scene, hm.map.region("rg_beam", cells, { "moonbeam" },
      { attached_to = "t_beam", area = { shape = "circle", radius = 1 }, effect = fx_id })),
}, "Dancing Lights")
```

### Creatures a spell makes

A spell that makes a creature — a familiar, a steed, animated undead, a
conjured beast — adds an actor (its stat block) and a token for it, owned by
its caster's player, so it is a creature like any other: a target, a sheet
of its own in its player's Character tab, moved by its player. The host
gives such a creature four things:

- **It goes with its spell.** An actor that names an effect id
  (`effect = "e_…"` on the actor) leaves the table when that effect goes —
  the spell ended, expired, dismissed, its concentration broken (an effect
  `linked` to that) — in the same step, with everything of its own: its
  tokens, the effects on it (and those elsewhere linked to them), its
  pools, its place in the order, and what its own effects put on the map or
  made. An undo brings it all back together. One that outlasts its spell
  (undead that only stop obeying) names none.
- **Its senses are its own until shared.** A token with `vision.shared =
  false` sees for the rules (`hm.map.can_see`, what it may target) but is
  not its player's view: their fog, their exploring and the party's sight
  leave it out until the flag is cleared (`Vision.shares`). A familiar's
  player looks through its eyes only when the rules say (a Bonus Action,
  until the start of their next turn).
- **Its turns as its words say.** A token with `turn_with = "<token id>"`
  acts in that token's slot (a group of the two: "Wren and Steed"); one
  with `turn_after = "<token id>"` has a slot of its own right after it.
  The order's start and `hm.turns.insert(entry)` with no index put them
  there (`TurnRunner.place_followers`); any other creature a spell makes
  in a fight is inserted where its own roll puts it.
- **Things with hit points are creatures enough.** An object token with
  an `actor` (above) is a target that takes damage, while it still moves as
  a thing and takes no turn.

```lua
-- an owl for Wren's player, gone with the spell's effect; its sight hers only when shared
hm.commit({ { t = "actor.add", actor = { id = "a_owl", kind = "companion", name = "Owl", owner = player,
    effect = fx_id, ext = { [ID] = block } } } }, "Find Familiar")
hm.commit({ { t = "token.add", scene = scene, token = { id = "t_owl", actor = "a_owl", name = "Owl", owner = player,
    pos = { x, y }, size = 0.5, vision = { radius = 6, dark_radius = 120, units = "ft", shared = false } } } }, "Find Familiar")
```

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
Dice expressions: `NdS`, `+`/`-`, `kh`/`kl`/`dh`/`dl` N, `rN` (reroll faces
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
hm.prompt_close(id)
-- closes one of your own unattended prompts unanswered (no hook fires):
-- what it asked for was done some other way, or taken back
```

A group is how a question is asked of three Players at once when the
action needs every answer before it goes on; an unattended prompt is how a
question can stay open across the rest of the action, or the session, and
how each Player can answer in their own time (srd5e asks for rolls that
way: a card each, and each roll made when its Player taps).

A form's `choices` (`[{ id, label, intent? }]`) draw as a button each
instead of one submit button: a button with an `intent` sends that (with
the form's values at `$values`), one without answers the prompt with the
values plus `choice = id` — its fields' values only, on the desktop and the
web alike: the rest of the prompt's `default` is what it answers when nobody
does, so a `late = true` there comes only with a deadline's answer or the
DM's Go on (the web once sent it with every button pressed: a player's "No
reaction" was said as "No answer in time"). A form's
`heading` is what the screens call the card, on its window and its pill
("Your hit", "Your choice": srd5e's); without one, an urgent card is "Your
reaction" ("A reaction" on the DM's screen) and another "The DM asks" ("The
rules ask you"). `opts.actor` names the character a prompt is
about, for the screens to say. The Table counts a prompt's `deadline`
down (seconds) and answers it with its default when it passes, so a
question left unanswered doesn't wait over a player's screen for ever; a
`deadline` of 0 (or less) waits for the answer however long that takes (or
for the GM to answer it) — a player's roll is theirs to make.

**A question to answer now** — a reaction: Shield as an attack's hit lands,
an opportunity attack as a creature leaves reach. Two options make a prompt
one, and say what a host and its screens owe it:

```lua
local ans = hm.prompt(player, {
    title = "The goblin hits you (Scimitar): 14 against your AC 12. Your reaction?", fields = {},
    choices = { { id = "shield", label = "Shield (a level 1 slot): AC 17 against this 14: it misses" },
                { id = "none", label = "No reaction" } } },
  { default = { choice = "none", late = true }, deadline = 30, actor = "a_1",
    urgent = true, public = "a reaction (Ilvara)" })
```

- `urgent = true`: it can't wait for the player to finish what they're
  doing. A screen puts it in front of everything at once — a handout,
  another card, a half-typed message — and ignores taps in its first moment
  (0.6 s on the web screens), so a tap already on its way isn't taken for an
  answer. It shows the seconds the card has left, counting down: every
  prompt a viewer is sent carries `left` (the seconds the Table's count had
  left when the view was sent; absent when nothing counts), and the screen
  counts on from when that view arrived. A choice whose id is `none` is
  drawn as the quiet one.
- `public = "words"`: everyone is told the table waits on it. Each
  viewer's projection lists such prompts under `waiting`: `{ id, to, who
  (the player's name, or "the DM"), what (these words), urgent, deadline,
  left }`; the question itself stays its player's. The DM's list carries
  each one's `default` too, and the DM's screen offers **Go on**: it answers
  the prompt for its player with that default and `waved = true` (an
  `answer` intent; the GM may answer any prompt), so the fight needn't wait
  on someone who has stepped away; and **Answer**, which opens the player's
  own card on the DM's screen to answer for them with a choice (a card whose
  default chooses nothing, a hit's damage type, needs it). The Table's Rules panel's **Default** does
  the same for any prompt whose default is a table (a deadline's default
  comes without `waved`). With `late` in the default, the plugin can tell a
  player's own "no" from a deadline's or the DM's, and say which.
  The words reach every screen: they shouldn't name what a player may not
  know (say only "a reaction" for the DM's own creatures).

An action that asks for a reaction waits on it with `hm.prompt`, one
creature at a time (the trigger's damage waits on the Shield). A move's
aftermath asks with `hm.prompt_open` instead, since the move stands whatever
the answer: an opportunity attack's card can have the attacks as buttons,
each an intent, and close when its turn ends. Where nothing may wait (a
turn's hooks, `prompt_answered` itself) a plugin can't ask; it can tell the
DM and the player what could have been taken.

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
- What everyone may see of a creature's state goes on its tokens as
  tags the maps draw: `bloodied` (a red ring and mark), `down` (the
  token darkened), `dead` (darkened and crossed out). A token named with
  a number ("Goblin Warrior 2") shows it after its label ("G2"), and the
  unnumbered one of the set shows "G1".
- Effects that last rounds or turns (`duration.kind` `rounds`,
  `turn_start`, `turn_end`) end when the turns stop: a fight's effects
  don't outlive it.
- An action's `error("…")` reaches the person as that sentence; the
  chunk and line (`[string "…"]:103:`) go to the Table's log only. Write
  the sentence for them: "Thok is behind total cover".
