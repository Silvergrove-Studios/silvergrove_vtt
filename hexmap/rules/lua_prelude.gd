class_name LuaPrelude
extends RefCounted
## The `hexmap` library every plugin sees, in Lua, loaded into each VM
## before the plugin's own chunks. It keeps the plugin's registrations
## (hooks, derive, actions, tests) on the Lua side and calls the host
## through `__host`, a table of callables the PluginHost exposes before
## the VM is sealed. The entry points the host calls back (`__derive`,
## `__run_hook`, `__run_action`, …) are globals defined here.
##
## Kept as a GDScript constant so it ships inside every build without a
## resource import. docs/plugin-authoring.md documents the API.

const SOURCE := """
local host = __host
__host = nil

local hm = {}
hm.id = host.id
hm.version = host.version

local handlers = {}
local derive_fn = nil
local actions = {}
local tests = {}
local turn_initiative_fn = nil
local turn_label_fn = nil

-- What crosses to the host is plain data: a copy with no cycles, no
-- functions, no more than MAX_DEPTH levels (a self-referencing table would
-- otherwise recurse for ever in the bridge). Errors name the problem.
local MAX_DEPTH = 32
local function plain(v, depth, seen)
	if type(v) ~= "table" then
		if type(v) == "function" or type(v) == "thread" or type(v) == "userdata" then
			error("a " .. type(v) .. " cannot cross to the host", 3)
		end
		return v
	end
	depth = depth or 0
	if depth >= MAX_DEPTH then error("data nested deeper than " .. MAX_DEPTH .. " levels", 3) end
	seen = seen or {}
	if seen[v] then error("a table that refers to itself cannot cross to the host", 3) end
	seen[v] = true
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "table" then error("a table key cannot cross to the host", 3) end
		out[k] = plain(x, depth + 1, seen)
	end
	seen[v] = nil
	return out
end

-- A host call that failed hands back { __error = message }; raise it here,
-- on the Lua side, where an error is safe.
local function call(fn, ...)
	local n = select("#", ...)
	local args = { ... }
	for i = 1, n do
		if type(args[i]) == "table" then args[i] = plain(args[i]) end
	end
	local r = fn(table.unpack(args, 1, n))
	if type(r) == "table" and r.__error then
		error(r.__error, 2)
	end
	return r
end

-- ---------------------------------------------------------- registration --

function hm.on(hook, fn)
	if type(hook) ~= "string" or type(fn) ~= "function" then
		error("hm.on(hook, function)", 2)
	end
	handlers[hook] = handlers[hook] or {}
	table.insert(handlers[hook], fn)
	host.hook_registered(hook)
end

function hm.derive(fn)
	if type(fn) ~= "function" then error("hm.derive(function)", 2) end
	derive_fn = fn
end

hm.schema = {}
function hm.schema.define(kind, schema)
	call(host.schema_define, kind, schema)
end

hm.actions = {}
function hm.actions.register(name, spec)
	if type(name) ~= "string" or type(spec) ~= "table" or type(spec.run) ~= "function" then
		error("hm.actions.register(name, {run = function, ...})", 2)
	end
	actions[name] = spec
	local public = {}
	for k, v in pairs(spec) do
		if k ~= "run" then public[k] = v end
	end
	host.action_registered(name, public)
end

function hm.test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

-- An improvisation benchmark: "a level-4 brute, now". `spec.params` is a
-- JSON-schema properties table the Table renders as a form; `spec.make`
-- turns the parameters into { name, kind, ext, token, resources }.
hm.improv = {}
local benchmarks = {}
function hm.improv.register(name, spec)
	if type(name) ~= "string" or type(spec) ~= "table" or type(spec.make) ~= "function" then
		error("hm.improv.register(name, {make = function, params = {...}, label = ...})", 2)
	end
	benchmarks[name] = spec
	local public = {}
	for k, v in pairs(spec) do
		if k ~= "make" then public[k] = v end
	end
	host.improv_registered(name, public)
end

-- A declarative view: "sheet" (rendered for each of this ruleset's actors
-- on their owner's device and on the Table), "status" (the table-wide
-- view every client sees), "gm" (a Table panel). See docs/plugin-authoring.md.
hm.ui = {}
function hm.ui.register(kind, schema)
	call(host.ui_register, kind, schema)
end

-- ------------------------------------------------------------------ map --
-- Questions to the map, and the few things a ruleset may put on it. A
-- place is "token:<id>", a "q,r" cell, or {x, y} in hex units.
hm.map = {}
function hm.map.bands(table) call(host.map_bands, table) end          -- { {name=, max=}, … } ascending
function hm.map.distance(scene, a, b) return call(host.map_distance, scene, a, b) end   -- {units, edge, cells, band}
function hm.map.band(scene, a, b) return call(host.map_distance, scene, a, b).band end
function hm.map.within(scene, origin, r) return call(host.map_within, scene, origin, r) end
function hm.map.template(scene, spec) return call(host.map_template, scene, spec) end
function hm.map.los(scene, a, b, tokens_block)
	if tokens_block == nil then tokens_block = true end
	return call(host.map_los, scene, a, b, tokens_block)
end
function hm.map.light_at(scene, p) return call(host.map_light, scene, p) end
function hm.map.can_see(scene, viewer, target) return call(host.map_can_see, scene, viewer, target) end
function hm.map.regions_at(scene, cell) return call(host.map_regions_at, scene, cell) end
function hm.map.tags_at(scene, cell) return call(host.map_tags_at, scene, cell) end
function hm.map.region(id, cells, tags, extra)
	local r = { id = id, cells = cells, tags = tags or {}, audience = "all", label = "", color = "#ffb060", plugin = hm.id }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end
function hm.map.region_add(scene, region) return { t = "region.add", scene = scene, region = region } end
function hm.map.region_remove(scene, id) return { t = "region.remove", scene = scene, id = id } end
function hm.map.region_set(scene, id, changes) return { t = "region.set", scene = scene, id = id, changes = changes } end
function hm.map.move(scene, token, to) return call(host.map_move, scene, token, to) end   -- {events, entered, left, cells}
function hm.map.cell(scene, key) return call(host.map_cell, scene, key) end
function hm.map.cell_set(scene, key, changes) return { t = "cell.set", scene = scene, id = key, changes = changes } end
function hm.map.cell_state(scene, key, changes) return { t = "ext.set", scope = "cell", scene = scene, id = key, plugin = hm.id, changes = changes } end
function hm.map.neighbors(scene, cell) return call(host.map_cells, "neighbors", scene, cell, 0) end
function hm.map.cells_within(scene, cell, r) return call(host.map_cells, "within", scene, cell, r) end
function hm.map.cells_between(scene, a, b) return call(host.map_cells, "between", scene, a, b) end
function hm.map.highlight(scene, cells, color, label)
	return { t = "scene.set", id = scene, changes = { highlight = cells and { cells = cells, color = color or "#ffffff", label = label or "" } or nil } }
end
function hm.map.token(scene, id) return call(host.map_token, scene, id) end
function hm.map.tokens(scene) return call(host.map_token, scene, "") end

-- ----------------------------------------------------------- compendium --
-- Content packs, indexed on the Table: query a page at a time, never the
-- whole thing. `opts`: filter = { field = value | {values} }, text = "…",
-- sort = "field" | "-field", page, per_page, fields = {…}, facets = {…}.
hm.comp = {}
function hm.comp.query(collection, opts) return call(host.comp_query, collection, opts or {}) end
function hm.comp.get(collection, id) return call(host.comp_get, collection, id) end
function hm.comp.collections() return call(host.comp_collections) end
function hm.comp.count(collection) return call(host.comp_count, collection) end
-- Homebrew: into this ruleset's own writable pack (needs "content").
function hm.comp.put(collection, entry) return call(host.comp_put, collection, entry) end
function hm.comp.remove(collection, id) return call(host.comp_remove, collection, id) end
function hm.comp.versions() return call(host.comp_versions) end
function hm.comp.outdated(actor_id) return call(host.comp_outdated, actor_id) end

-- ---------------------------------------------------------------- turns --

hm.turns = {}
-- Register this ruleset's turn strategy: { shape = "ordered" | "focus",
-- name, description, initiative = function(view, token) | "derived path",
-- tie_break = "highest" | "lowest", budgets = { actions = 3 }, label = function(view, init) }
function hm.turns.register(spec)
	if type(spec) ~= "table" then error("hm.turns.register(spec)", 2) end
	local public = {}
	for k, v in pairs(spec) do
		if type(v) == "function" then
			if k == "initiative" then turn_initiative_fn = v end
			if k == "label" then turn_label_fn = v end
		else
			public[k] = v
		end
	end
	public.has_initiative_fn = turn_initiative_fn ~= nil
	public.has_label_fn = turn_label_fn ~= nil
	call(host.turns_register, public)
end
function hm.turns.current() return call(host.turns_get) end
function hm.turns.focus() return call(host.turns_get).focus end
function hm.turns.holder_actor()
	local f = call(host.turns_get).focus or ""
	if f:sub(1, 6) == "actor:" then return f:sub(7) end
	if f:sub(1, 6) == "token:" then
		local tk = hm.token(f:sub(7))
		return tk and tk.actor or nil
	end
	return nil
end
function hm.turns.set_focus(holder, by) return call(host.turns_op, "set_focus", holder, by or hm.id) end
function hm.turns.request(player, ref) return call(host.turns_op, "request", ref, player) end
function hm.turns.deny(ref) return call(host.turns_op, "deny", ref, "") end
function hm.turns.start(scene, strategy) return call(host.turns_op, "start", scene, strategy or hm.id) end
function hm.turns.next() return call(host.turns_op, "next", "", "") end
function hm.turns.stop() return call(host.turns_op, "stop", "", "") end
function hm.turns.counters(ref) return (call(host.turns_get).counters or {})[ref] or {} end
function hm.turns.consume(ref, counter, n) return call(host.turns_consume, ref, counter, n or 1) end

-- --------------------------------------------------------------- tracks --

hm.tracks = {}
function hm.tracks.make(name, max, kind, advance, audience, on_done)
	return call(host.track_make, name, max, kind or "countdown", advance or {}, audience or "all", on_done or "")
end
function hm.tracks.add(track) return { t = "track.add", track = track } end
function hm.tracks.remove(id) return { t = "track.remove", id = id } end
function hm.tracks.advance(id, n) return call(host.track_advance, id, n or 1) end
function hm.tracks.get(id) return call(host.track_get, id) end
function hm.tracks.all() return call(host.track_all) end

-- ---------------------------------------------------------------- clock --

hm.clock = {}
function hm.clock.get() return call(host.clock_get) end
function hm.clock.advance(minutes, label) return call(host.clock_op, "advance", minutes or 0, label or "") end
function hm.clock.next_session() return call(host.clock_op, "session", 0, "") end
function hm.clock.next_scene() return call(host.clock_op, "scene", 0, "") end

function hm.rest(kind, label) return call(host.rest, kind or "rest", label or "") end

-- ------------------------------------------------------------- helpers --

-- A typed number: { total, parts = { {label, type, value, source}, ... } }.
-- Summed plainly here; the kernel re-totals under the ruleset's policy.
function hm.num(parts)
	local total = 0
	for _, p in ipairs(parts) do
		total = total + (p.value or 0)
	end
	return { total = total, parts = parts }
end

function hm.value(n)
	if type(n) == "table" then return n.total or 0 end
	return tonumber(n) or 0
end

-- The only way to wait: yield a request to the host, resume with the answer.
function hm.prompt(to, form, opts)
	return coroutine.yield(plain({ kind = "prompt", to = to, form = form, opts = opts or {} }))
end

-- Ask several players the same question at once; resumes with
-- { [player] = answer } once every one has answered or timed out.
function hm.prompt_all(players, form, opts)
	if type(players) ~= "table" then error("hm.prompt_all(players, form, opts)", 2) end
	return coroutine.yield(plain({ kind = "prompt_all", to = players, form = form, opts = opts or {} }))
end

-- Ask without waiting: the answer arrives as the `prompt_answered` hook
-- ({prompt, answer, by, timed_out, plugin, context}). Returns the prompt id.
-- opts.context travels to the hook untouched.
function hm.prompt_open(to, form, opts)
	return call(host.prompt_open, to, form, opts or {})
end

-- ---------------------------------------------------------------- state --

function hm.actor(id) return call(host.actor, id) end
function hm.actors() return call(host.actors) end
function hm.derived(id) return call(host.derived, id) end
function hm.token(id) return call(host.token, id) end
function hm.tokens(actor_id) return call(host.tokens, actor_id) end

hm.state = {}
function hm.state.get(scope, id) return call(host.state_get, scope, id or "") end
function hm.state.set(scope, id, changes)
	return { t = "ext.set", scope = scope, id = id, plugin = hm.id, changes = changes }
end

function hm.commit(events, label, reason)
	if type(events) ~= "table" then error("hm.commit(events, label)", 2) end
	if events.t then events = { events } end
	return call(host.commit, events, label or "", reason or {})
end

function hm.log(text, audience)
	return call(host.note, tostring(text), audience or "all")
end

-- "We ruled that X": kept in the campaign's journal. opts = { rule =, roll =, tags = {...}, audience = }
function hm.ruling(text, opts)
	return call(host.ruling, tostring(text), opts or {})
end

-- One thing done to many refs as one step (docs/plugin-authoring.md, "Bulk").
hm.bulk = {}
function hm.bulk.run(targets, op, label) return call(host.bulk_run, targets, op, label or "") end
function hm.bulk.effect(targets, effect, label) return hm.bulk.run(targets, { kind = "effect", effect = effect }, label) end
function hm.bulk.resource(targets, name, delta, label) return hm.bulk.run(targets, { kind = "resource", plugin = hm.id, name = name, delta = delta }, label) end
function hm.bulk.roll(targets, spec, ctx, per, label) return hm.bulk.run(targets, { kind = "roll", spec = spec, ctx = ctx or {}, per = per or {} }, label) end

-- Named snapshots of the whole encounter (needs "state").
hm.checkpoint = {}
function hm.checkpoint.mark(name) return call(host.checkpoint_op, "mark", tostring(name)) end
function hm.checkpoint.list() return call(host.checkpoint_op, "list", "") end
function hm.checkpoint.restore(id) return call(host.checkpoint_op, "restore", tostring(id)) end

-- The campaign this session belongs to: { id, session }. Campaign-scoped
-- state is hm.state.get("campaign") / hm.state.set("campaign", "", changes).
function hm.campaign() return call(host.campaign_get) end

hm.settings = {}
function hm.settings.get(key, default)
	local v = call(host.setting, key)
	if v == nil then return default end
	return v
end

-- ----------------------------------------------------------------- dice --

hm.dice = {}
function hm.dice.roll(spec, ctx, label)
	if type(spec) == "string" then spec = { expr = spec } end
	return call(host.roll, spec, ctx or {}, label or "Roll")
end
function hm.dice.parse(expr) return call(host.dice_parse, expr) end
-- A roll that waits for contributions (help dice, joined actions) before
-- it resolves: open it, let others contribute, resolve it.
function hm.dice.open(spec, ctx, label, open_to, deadline)
	if type(spec) == "string" then spec = { expr = spec } end
	return call(host.roll_open, spec, ctx or {}, label or "Roll", open_to or "all", deadline or 30)
end
function hm.dice.contribute(id, who, name, expr) return call(host.roll_contribute, id, who or "", name, expr) end
function hm.dice.resolve(id) return call(host.roll_resolve, id) end
function hm.dice.pending() return call(host.roll_pending) end

-- -------------------------------------------------------------- effects --

hm.effects = {}
function hm.effects.apply(effect)
	effect.plugin = effect.plugin or hm.id
	return call(host.effects_apply, effect)
end
function hm.effects.remove(id) return call(host.effects_remove, id) end
function hm.effects.on(ref, key) return call(host.effects_on, ref, key or "") end
function hm.effects.has(ref, key) return #call(host.effects_on, ref, key or "") > 0 end
function hm.effects.expire(trigger) return call(host.effects_expire, trigger) end
function hm.effects.set(id, changes) return { t = "effect.set", id = id, changes = changes } end

-- ------------------------------------------------------------ resources --

hm.resources = {}
function hm.resources.get(ref, name) return call(host.resource_get, ref, name) end
function hm.resources.pool(current, max, recharge)
	return { kind = "pool", current = current, max = max, recharge = recharge or "manual" }
end
function hm.resources.track(max, marked, extra, crossed, recharge)
	return { kind = "track", max = max, marked = marked or 0, extra = extra or 0, crossed = crossed or {}, recharge = recharge or "manual" }
end
function hm.resources.set(ref, name, record)
	return { t = "resource.set", ref = ref, plugin = hm.id, name = name, record = record }
end
function hm.resources.spend(ref, name, amount) return call(host.resource_op, "spend", ref, name, amount, false) end
function hm.resources.gain(ref, name, amount, overflow) return call(host.resource_op, "gain", ref, name, amount, overflow == true) end
function hm.resources.mark(ref, name, n) return call(host.resource_op, "mark", ref, name, n or 1, false) end
function hm.resources.clear(ref, name, n) return call(host.resource_op, "clear", ref, name, n or 1, false) end
function hm.resources.cross(ref, name, slot, crossed)
	if crossed == nil then crossed = true end
	return call(host.resource_op, "cross", ref, name, slot, crossed)
end
function hm.resources.refill(kind) return call(host.resource_refill, kind) end

-- ------------------------------------------------ entry points for the host --

function __derive(view)
	if derive_fn == nil then return {} end
	local out = derive_fn(view)
	if type(out) ~= "table" then error("derive returned a " .. type(out) .. ", not a table") end
	return plain(out)
end

function __run_hook(hook, payload)
	local list = handlers[hook]
	if list == nil then return payload end
	for _, fn in ipairs(list) do
		local r = fn(payload)
		if type(r) == "table" then payload = r end
		if payload.veto ~= nil and payload.veto ~= false and payload.veto ~= "" then break end
	end
	return plain(payload)
end

function __turn_initiative(view, token)
	if turn_initiative_fn == nil then return nil end
	return plain(turn_initiative_fn(view, token))
end

function __turn_label(view, init)
	if turn_label_fn == nil then return tostring(init) end
	return tostring(turn_label_fn(view, init))
end

function __run_action(name, ctx)
	local a = actions[name]
	if a == nil then error("no action '" .. tostring(name) .. "'") end
	return plain(a.run(ctx or {}))
end

function __run_improv(name, params)
	local b = benchmarks[name]
	if b == nil then error("no benchmark '" .. tostring(name) .. "'") end
	return plain(b.make(params or {}))
end

function __tests()
	local names = {}
	for i, t in ipairs(tests) do names[i] = t.name end
	return names
end

function __run_test(index, helpers)
	local t = tests[index]
	if t == nil then error("no test " .. tostring(index)) end
	local h = {}
	function h.ok(cond, msg) host.test_check(cond and true or false, msg or "ok") end
	function h.eq(a, b, msg)
		local same = a == b
		if type(a) == "number" and type(b) == "number" then same = math.abs(a - b) < 1e-9 end
		host.test_check(same, (msg or "eq") .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")")
	end
	function h.actor(data) return call(host.test_actor, data) end
	function h.roll_with_faces(faces, spec, ctx, label)
		if type(spec) == "string" then spec = { expr = spec } end
		spec.faces = faces
		return call(host.roll, spec, ctx or {}, label or "Test roll")
	end
	function h.commit(events, label) return hm.commit(events, label or "test") end
	function h.dispatch(action, ctx, answers) return call(host.test_dispatch, action, ctx or {}, answers or {}) end
	-- answer an open prompt as a player ("" for the GM); the open prompts
	function h.answer(prompt, answer, who) return call(host.test_answer, prompt, answer, who or "") end
	function h.prompts() return call(host.test_prompts) end
	function h.tick(seconds) return call(host.test_tick, seconds or 0) end
	function h.turns_start(scene, strategy) return hm.turns.start(scene, strategy or hm.id) end
	-- a scene over a map file (the examples' chapel by default), with tokens = { {id, actor, x, y}, … }
	function h.scene(map_path, tokens) return call(host.test_scene, map_path or "res://examples/ruined_chapel.hexmap", tokens or {}) end
	-- a creature from one of this plugin's benchmarks, placed on a scene at a "q,r" cell: its actor id
	function h.improvise(benchmark, params, scene, at) return call(host.test_improvise, benchmark, params or {}, scene, at or "") end
	for k, v in pairs(helpers or {}) do h[k] = v end
	return t.fn(h)
end

hexmap = hm
"""
