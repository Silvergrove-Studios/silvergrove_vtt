class_name PluginHost
extends RefCounted
## Loads plugins and stands between them and the kernel. A plugin is a
## directory: manifest.json, Lua files, schemas, packs. Each gets its own
## sealed LuaVm with the `hexmap` library (LuaPrelude) and a table of host
## callables gated by the manifest's capabilities. The host registers the
## plugin's derive and hooks with the RulesKernel, dispatches its actions,
## runs its tests, and turns every plugin failure into a logged error
## rather than an engine one.
##
## Everything crossing into a VM is plain data; everything coming back is
## normalised (an empty Lua table arrives as an empty Array, so places
## that must be objects are fixed up) before the kernel sees it.

## A plugin misbehaved: (plugin id, where, message).
signal plugin_failed(id: String, where: String, message: String)
signal plugin_loaded(id: String)

const API_VERSION := 1
const CAPABILITIES := ["state", "prompts", "log", "actions", "effects", "resources", "dice", "content"]
## What a manifest must look like.
const MANIFEST_SCHEMA := {
	"type": "object",
	"required": ["id", "version", "api", "name"],
	"properties": {
		"id": {"type": "string", "format": "id"},
		"version": {"type": "string", "minLength": 1},
		"api": {"type": "integer", "const": 1},
		"name": {"type": "string", "minLength": 1},
		"description": {"type": "string"},
		"attribution": {"type": "string"},
		"license": {"type": "string"},
		"main": {"type": "string"},
		"files": {"type": "array", "items": {"type": "string"}},
		"depends": {"type": "array", "items": {"type": "string"}},
		# plugin layering: this plugin replaces another's handlers for these
		# hooks ("*" for all of them); it must depend on that plugin
		"overrides": {"type": "object", "additionalProperties": {"type": "array", "items": {"type": "string"}}},
		"packs": {"type": "array", "items": {"type": "string"}},
		"capabilities": {"type": "array", "items": {"type": "string", "enum": CAPABILITIES}},
		"policy": {"type": "object"},
		"settings": {"type": "object"},
		"tests": {"type": "boolean"},
	},
	"additionalProperties": true,
}

var kernel: RulesKernel
## id -> Plugin
var plugins: Dictionary = {}
## Budgets applied to every VM.
var instruction_budget := 1_000_000
var memory_budget := 64 * 1024 * 1024
## Wall-clock budget for one call into a plugin (an action, a hook, a
## derive): the instruction budget bounds Lua, this bounds what a loop of
## host calls (commits, rolls) may cost the table. Checked by the costly
## host calls; a call over it fails with a readable error.
var call_ms_budget := 2000
var _call_started_ms := 0


class Plugin:
	var id := ""
	var manifest: Dictionary = {}
	var dir := ""
	var vm: LuaVm
	var hooks: Array = []
	var actions: Dictionary = {}
	var schemas: Dictionary = {}
	var settings: Dictionary = {}
	var errors: Array = []
	var capabilities: Array = []
	var bridge: RefCounted
	var turn_strategy: Dictionary = {}
	## kind ("sheet", "status", "gm") -> view schema
	var views: Dictionary = {}
	## improvisation benchmarks: name -> {label, params}
	var improv: Dictionary = {}

	func can(cap: String) -> bool:
		return capabilities.has(cap)


## One dispatched action: finished, waiting on a prompt, or failed.
class PluginCall:
	const OK := "ok"
	const PENDING := "pending"
	const ERROR := "error"

	var plugin_id := ""
	var action := ""
	var status := OK
	var value: Variant = null
	## While PENDING: the request the plugin yielded ({kind: "prompt", to, form, opts}).
	var request: Dictionary = {}
	var error := ""
	var _call: LuaVm.Call
	var _host: WeakRef

	func resume(answer: Variant) -> PluginCall:
		if status != PENDING or _call == null:
			return self
		var h: PluginHost = _host.get_ref()
		if h != null:
			h._call_started_ms = Time.get_ticks_msec()
		_call.resume(answer)
		if h != null:
			h._absorb_call(self, _call)
		return self


func _init(p_kernel: RulesKernel) -> void:
	kernel = p_kernel
	kernel.plugin_host = weakref(self)


static func available() -> bool:
	return LuaVm.available()


# ------------------------------------------------------------- loading --

## Manifests of the plugins found directly under each directory.
static func discover(dirs: Array) -> Array:
	var out := []
	for d in dirs:
		var da := DirAccess.open(str(d))
		if da == null:
			continue
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if da.current_is_dir() and not name.begins_with("."):
				var mp := str(d).path_join(name).path_join("manifest.json")
				if FileAccess.file_exists(mp):
					var err := []
					var m := JsonDoc.parse(FileAccess.get_file_as_string(mp), err)
					if not m.is_empty():
						m.__dir = str(d).path_join(name)
						out.append(m)
			name = da.get_next()
		da.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	return out


## Load the plugin in `dir` (manifest.json plus its files). "" or why not.
func load_dir(dir: String) -> String:
	var mp := dir.path_join("manifest.json")
	if not FileAccess.file_exists(mp):
		return "no manifest.json in %s" % dir
	var err := []
	var manifest := JsonDoc.parse(FileAccess.get_file_as_string(mp), err)
	if manifest.is_empty():
		return "manifest.json: %s" % ("; ".join(PackedStringArray(err)) if not err.is_empty() else "not an object")
	var files: Array = manifest.get("files", [])
	if files.is_empty():
		files = [str(manifest.get("main", "main.lua"))]
	var sources := []
	for f in files:
		var p := dir.path_join(str(f))
		if not FileAccess.file_exists(p):
			return "%s: missing file %s" % [str(manifest.get("id", "?")), str(f)]
		sources.append([str(f), FileAccess.get_file_as_string(p)])
	return load_source(manifest, sources, dir)


## Load a plugin from its manifest and [name, source] chunks. "" or why not.
func load_source(manifest: Dictionary, sources: Array, dir := "") -> String:
	if not available():
		return "no Lua runtime in this build"
	var why := JsonSchema.new(MANIFEST_SCHEMA).first_error(manifest)
	if why != "":
		return "manifest: " + why
	var id := str(manifest.id)
	if plugins.has(id):
		return "plugin '%s' is already loaded" % id
	for dep in manifest.get("depends", []):
		if not plugins.has(str(dep)):
			return "%s depends on '%s', which is not loaded" % [id, str(dep)]
	for over in manifest.get("overrides", {}):
		if not Array(manifest.get("depends", [])).has(str(over)):
			return "%s overrides '%s' without depending on it" % [id, str(over)]
	var p := Plugin.new()
	p.id = id
	p.manifest = JsonDoc.deep(manifest)
	p.dir = dir
	p.capabilities = Array(manifest.get("capabilities", []))
	p.settings = JsonDoc.deep(manifest.get("settings", {}).get("defaults", {}))
	# the campaign's settings for it, over the defaults
	for k in settings_overrides.get(id, {}):
		JsonDoc.set_at_path(p.settings, str(k), settings_overrides[id][k])
	p.vm = LuaVm.new()
	p.vm.instruction_budget = instruction_budget
	p.vm.memory_budget = memory_budget
	p.vm.expose_value("__host", _host_table(p))
	why = p.vm.load_chunk(LuaPrelude.SOURCE, "hexmap")
	if why != "":
		return "%s: prelude: %s" % [id, why]
	plugins[id] = p   # registration callbacks during load need it
	for s in sources:
		why = p.vm.load_chunk(str(s[1]), "%s/%s" % [id, str(s[0])])
		if why != "":
			plugins.erase(id)
			kernel.hooks.off(id)
			return "%s: %s" % [id, why]
	p.vm.seal()
	# the packs the plugin ships, layered under whatever the table adds
	for rel in manifest.get("packs", []):
		if dir == "":
			continue
		var pw := kernel.comp.load_path(dir.path_join(str(rel)))
		if pw != "":
			_fail(p, "pack " + str(rel), pw)
	var spec := {"derive": _derive.bind(id), "policy": manifest.get("policy", {}), "depends_on_state": bool(manifest.get("depends_on_state", false))}
	if load_order.has(id):
		# the campaign's list runs first, in its order; the rest follow in load order
		spec.order = load_order.find(id) - 1000
	kernel.register_ruleset(id, spec)
	_attach_hooks(p, kernel)
	for over in manifest.get("overrides", {}):
		kernel.hooks.override(id, str(over), Array(manifest.overrides[over]))
	plugin_loaded.emit(id)
	return ""


## Settings a campaign gives plugins (id -> {path: value}), applied when
## each loads. Set before load_dir / load_all.
var settings_overrides: Dictionary = {}
## The campaign's plugin order: ids listed here get that order; the rest
## follow in load order.
var load_order: Array = []


## Load every plugin found under `dirs`, dependencies first, in the
## campaign's order where it names them. Returns [{id, why}] per plugin
## ("" for loaded), in the order tried.
func load_all(dirs: Array, order: Array = []) -> Array:
	load_order = order.duplicate()
	var found := discover(dirs)
	var by_id := {}
	for m in found:
		by_id[str(m.get("id", ""))] = m
	# the campaign's order first, then the rest by id; dependencies pulled ahead
	var ids := []
	for id in order:
		if by_id.has(str(id)) and not ids.has(str(id)):
			ids.append(str(id))
	for m in found:
		if not ids.has(str(m.get("id", ""))):
			ids.append(str(m.get("id", "")))
	var sorted := []
	var visiting := {}
	var missing := {}
	var visit := func(id: String, self_ref: Callable) -> void:
		if sorted.has(id) or not by_id.has(id):
			if not by_id.has(id):
				missing[id] = true
			return
		if visiting.has(id):
			return   # a cycle: the load itself will complain
		visiting[id] = true
		for dep in by_id[id].get("depends", []):
			self_ref.call(str(dep), self_ref)
		sorted.append(id)
	for id in ids:
		visit.call(id, visit)
	# the campaign's plugins keep their place in the resolved order (a
	# base always precedes what layers over it, whatever the list said)
	load_order = sorted.filter(func(id: String) -> bool: return order.has(id))
	var out := []
	for id in sorted:
		out.append({"id": id, "why": load_dir(str(by_id[id].__dir))})
	return out


## Register the plugin's hook handlers on a kernel, in the plugin's order.
func _attach_hooks(p: Plugin, k: RulesKernel) -> void:
	k.hooks.off(p.id)
	for h in p.hooks:
		k.hooks.on(str(h), _on_hook.bind(p.id, str(h)), p.id, k.ruleset_order(p.id))


func unload(id: String) -> void:
	if not plugins.has(id):
		return
	for pid in kernel.comp.packs.keys():
		if str(kernel.comp.packs[pid].plugin) == id and not bool(kernel.comp.packs[pid].get("user", false)):
			kernel.comp.unload(str(pid))
	kernel.unregister_ruleset(id)
	kernel.hooks.unoverride(id)
	kernel.validators = kernel.validators.filter(func(v: Dictionary) -> bool: return str(v.get("owner", "")) != id)
	plugins.erase(id)


func plugin(id: String) -> Plugin:
	return plugins.get(id)


func _fail(p: Plugin, where: String, message: String) -> void:
	p.errors.append({"where": where, "message": message, "when": JsonDoc.now()})
	plugin_failed.emit(p.id, where, message)


# ----------------------------------------------------- kernel callbacks --

## The ruleset's derive: the view in, the plugin's block out.
func _derive(view: Dictionary, id: String) -> Dictionary:
	_call_started_ms = Time.get_ticks_msec()
	var p: Plugin = plugins.get(id)
	if p == null:
		return {}
	var c := p.vm.call_function("__derive", [view])
	if c.status != LuaVm.Call.OK:
		_fail(p, "derive", c.error if c.status != LuaVm.Call.YIELD else "derive may not yield")
		return {"__error": c.error if c.error != "" else "derive yielded"}
	return _as_dict(c.value)


## One HookBus handler per (plugin, hook): runs the plugin's handlers in a
## thread; a yield becomes a Wait the bus can resume.
func _on_hook(payload: Dictionary, id: String, hook: String) -> Variant:
	_call_started_ms = Time.get_ticks_msec()
	var p: Plugin = plugins.get(id)
	if p == null:
		return null
	var c := p.vm.call_function("__run_hook", [hook, payload])
	return _hook_result(p, hook, c)


func _hook_result(p: Plugin, hook: String, c: LuaVm.Call) -> Variant:
	match c.status:
		LuaVm.Call.OK:
			return _as_dict(c.value)
		LuaVm.Call.YIELD:
			if not p.can("prompts"):
				_fail(p, "hook " + hook, "yielded without the 'prompts' capability")
				return {"__error": "no 'prompts' capability"}
			return HookBus.Wait.make(_as_dict(c.value), func(_payload: Dictionary, answer: Variant) -> Variant:
				c.resume(answer)
				return _hook_result(p, hook, c))
		_:
			_fail(p, "hook " + hook, c.error)
			return {"__error": c.error}


## Validate an actor's data for this plugin against its declared schema.
func _validate_actor(actor: Dictionary, id: String) -> String:
	var p: Plugin = plugins.get(id)
	if p == null or not p.schemas.has("actor"):
		return ""
	var data: Variant = actor.get("ext", {}).get(id)
	if data == null:
		return ""
	var why: String = (p.schemas["actor"] as JsonSchema).first_error(data)
	return "" if why == "" else "%s: actor %s: %s" % [id, str(actor.get("id", "")), why]


# ------------------------------------------------------------- actions --

## Run a plugin's action. The call may finish, pause on a prompt (answer
## it with resume()) or fail.
func dispatch(id: String, action: String, ctx: Dictionary = {}) -> PluginCall:
	var pc := PluginCall.new()
	pc.plugin_id = id
	pc.action = action
	pc._host = weakref(self)
	var p: Plugin = plugins.get(id)
	if p == null:
		pc.status = PluginCall.ERROR
		pc.error = "no plugin '%s'" % id
		return pc
	if not p.actions.has(action):
		pc.status = PluginCall.ERROR
		pc.error = "%s has no action '%s'" % [id, action]
		return pc
	# Every action knows who asked: a Player's id (stamped by the host from
	# the connection) or "" with gm = true for the Table and its co-GMs.
	if not ctx.has("gm"):
		ctx = ctx.duplicate()
		ctx.gm = not ctx.has("player") or str(ctx.player) == ""
		if not ctx.has("player"):
			ctx.player = ""
	_call_started_ms = Time.get_ticks_msec()
	var c := p.vm.call_function("__run_action", [action, ctx])
	pc._call = c
	_absorb_call(pc, c)
	return pc


## Whether the call in flight has spent its wall-clock budget.
func over_time_budget() -> bool:
	return call_ms_budget > 0 and Time.get_ticks_msec() - _call_started_ms > call_ms_budget


## Run a benchmark: the plugin's `make(params)` → an actor's data.
## Benchmarks may not prompt.
func improvise(id: String, benchmark: String, params: Dictionary = {}) -> PluginCall:
	var pc := PluginCall.new()
	pc.plugin_id = id
	pc.action = "improv " + benchmark
	pc._host = weakref(self)
	var p: Plugin = plugins.get(id)
	if p == null:
		pc.status = PluginCall.ERROR
		pc.error = "no plugin '%s'" % id
		return pc
	if not p.improv.has(benchmark):
		pc.status = PluginCall.ERROR
		pc.error = "%s has no benchmark '%s'" % [id, benchmark]
		return pc
	var c := p.vm.call_function("__run_improv", [benchmark, params])
	pc._call = c
	_absorb_call(pc, c)
	if pc.status == PluginCall.PENDING:
		pc.status = PluginCall.ERROR
		pc.error = "a benchmark may not prompt"
	return pc


func _absorb_call(pc: PluginCall, c: LuaVm.Call) -> void:
	var p: Plugin = plugins.get(pc.plugin_id)
	match c.status:
		LuaVm.Call.OK:
			pc.status = PluginCall.OK
			pc.value = c.value
			pc.request = {}
		LuaVm.Call.YIELD:
			if p != null and not p.can("prompts"):
				pc.status = PluginCall.ERROR
				pc.error = "yielded without the 'prompts' capability"
				_fail(p, "action " + pc.action, pc.error)
				return
			pc.status = PluginCall.PENDING
			pc.request = _as_dict(c.value)
		_:
			pc.status = PluginCall.ERROR
			pc.error = c.error
			if p != null:
				_fail(p, "action " + pc.action, c.error)


# --------------------------------------------------------------- tests --

## Run the plugin's own `hm.test`s on a scratch encounter, one fresh state
## per test. Returns {count, fails, failures: [{test, message}], names}.
func run_tests(id: String, say: Callable = func(_l: String) -> void: pass) -> Dictionary:
	var out := {"count": 0, "fails": 0, "failures": [], "names": []}
	var p: Plugin = plugins.get(id)
	if p == null:
		out.failures.append({"test": "", "message": "no plugin '%s'" % id})
		out.fails = 1
		return out
	var names := p.vm.call_function("__tests")
	if names.status != LuaVm.Call.OK:
		out.failures.append({"test": "", "message": names.error})
		out.fails = 1
		return out
	var list: Array = names.value if names.value is Array else []
	out.names = list
	var real_kernel := kernel
	for i in list.size():
		var name := str(list[i])
		say.call("  · " + name)
		var scratch := EncounterState.new(Encounter.create("plugin test"))
		scratch.encounter.doc.rng = {"seed": 7, "index": 0}
		kernel = RulesKernel.new(scratch)
		kernel.plugin_host = weakref(self)
		kernel.validators = real_kernel.validators.duplicate()
		# the plugin, its dependencies (so a layered plugin is tested over
		# its base) and their packs, fresh for each test
		for pid in _with_dependencies(id):
			_attach_to(kernel, real_kernel, str(pid))
		_test_counts = [0, 0]
		_test_failures = []
		var c := p.vm.call_function("__run_test", [i + 1, {}])
		if c.status != LuaVm.Call.OK:
			_test_failures.append("the test %s: %s" % ["yielded — tests may not prompt; use t.dispatch(action, ctx, answers)" if c.status == LuaVm.Call.YIELD else "failed", c.error])
			_test_counts[1] += 1
		out.count += _test_counts[0]
		out.fails += _test_counts[1]
		for f in _test_failures:
			out.failures.append({"test": name, "message": f})
			say.call("    FAIL: " + f)
	kernel = real_kernel
	return out

var _test_counts := [0, 0]
var _test_failures: Array = []


## A plugin's dependencies (transitively) then itself, in load order.
func _with_dependencies(id: String) -> Array:
	var out := []
	var walk := func(pid: String, self_ref: Callable) -> void:
		if out.has(pid) or not plugins.has(pid):
			return
		for dep in (plugins[pid] as Plugin).manifest.get("depends", []):
			self_ref.call(str(dep), self_ref)
		out.append(pid)
	walk.call(id, walk)
	return out


## Register a loaded plugin on another kernel (a scratch one): its
## ruleset, turn strategy, bands, hooks, overrides and shipped packs.
func _attach_to(k: RulesKernel, real_kernel: RulesKernel, pid: String) -> void:
	var p: Plugin = plugins[pid]
	k.register_ruleset(pid, real_kernel.rulesets[pid])
	if not p.turn_strategy.is_empty():
		k.turns.register(pid, p.turn_strategy)
	if real_kernel.map.band_tables.has(pid):
		k.map.band_tables[pid] = real_kernel.map.band_tables[pid]
	_attach_hooks(p, k)
	for over in p.manifest.get("overrides", {}):
		k.hooks.override(pid, str(over), Array(p.manifest.overrides[over]))
	for rel in p.manifest.get("packs", []):
		if p.dir != "":
			k.comp.load_path(p.dir.path_join(str(rel)))


# --------------------------------------------------------- host table --

## The callables the prelude wraps, as methods of a bridge that holds the
## host weakly (the VM keeps the table; the table must not keep the host).
## Every one returns at once and returns plain data; failures come back as
## {__error} for the prelude to raise.
func _host_table(p: Plugin) -> Dictionary:
	var br := Bridge.new()
	br.host = weakref(self)
	br.plugin_id = p.id
	p.bridge = br
	var t := {"id": p.id, "version": str(p.manifest.get("version", ""))}
	for m in ["hook_registered", "action_registered", "schema_define", "actor", "actors", "derived", "token", "tokens",
			"state_get", "commit", "note", "setting", "roll", "dice_parse", "effects_apply", "effects_remove", "effects_on",
			"effects_expire", "resource_get", "resource_op", "resource_refill", "test_check", "test_actor", "test_dispatch",
			"turns_register", "turns_get", "turns_op", "turns_consume", "track_make", "track_advance", "track_get", "track_all",
			"clock_get", "clock_op", "rest", "roll_open", "roll_contribute", "roll_resolve", "roll_pending", "ui_register",
			"comp_query", "comp_get", "comp_collections", "comp_count", "comp_put", "comp_remove", "comp_versions", "comp_outdated",
			"map_bands", "map_distance", "map_within", "map_template", "map_los", "map_light", "map_can_see", "map_regions_at", "map_tags_at",
			"map_move", "map_cell", "map_cells", "map_token", "test_scene",
			"improv_registered", "ruling", "bulk_run", "checkpoint_op", "campaign_get", "test_improvise"]:
		t[m] = Callable(br, m)
	return t


class Bridge:
	var host: WeakRef
	var plugin_id := ""

	func _h() -> PluginHost:
		return host.get_ref()

	func _p() -> Plugin:
		var h := _h()
		return h.plugins.get(plugin_id) if h != null else null

	func _k() -> RulesKernel:
		var h := _h()
		return h.kernel if h != null else null

	func hook_registered(hook: String) -> void:
		var p := _p()
		if p != null and not p.hooks.has(hook):
			p.hooks.append(hook)

	func improv_registered(name: String, public: Variant) -> void:
		_p().improv[str(name)] = PluginHost._as_dict(public)

	func action_registered(name: String, public: Variant) -> void:
		var p := _p()
		if p != null:
			p.actions[name] = PluginHost._as_dict(public)

	func schema_define(kind: String, schema: Variant) -> Variant:
		var p := _p()
		var h := _h()
		if p == null:
			return {"__error": "unloaded"}
		var s: Variant = PluginHost._norm_schema(schema)
		if not (s is Dictionary):
			return {"__error": "schema must be an object"}
		p.schemas[kind] = JsonSchema.register("%s:%s" % [plugin_id, kind], s)
		if kind == "actor" and not h.kernel.validators.any(func(v: Dictionary) -> bool: return str(v.get("owner", "")) == plugin_id):
			h.kernel.validators.append({"owner": plugin_id, "fn": h._validate_actor.bind(plugin_id)})
		return true

	func actor(aid: String) -> Variant:
		var v := _k().actor_view(str(aid))
		return v if not v.is_empty() else null

	func actors() -> Array:
		var ids := _k().state.encounter.actors.keys()
		ids.sort()
		return ids

	func derived(aid: String) -> Variant:
		return _k().state.encounter.actor(str(aid)).get("derived", {}).get(plugin_id, {})

	func token(tid: String) -> Variant:
		var tk := _k().state.find_token(str(tid))
		return JsonDoc.deep(tk) if not tk.is_empty() else null

	func tokens(aid: String) -> Array:
		var out := []
		for sc in _k().state.encounter.scenes:
			for tk in sc.tokens:
				if str(tk.get("actor", "")) == str(aid):
					out.append(JsonDoc.deep(tk))
		return out

	func state_get(scope: String, sid: String) -> Variant:
		var st := _k().state
		match str(scope):
			"campaign": return JsonDoc.deep(st.encounter.campaign.get("ext", {}).get(plugin_id, {}))
			"encounter": return JsonDoc.deep(st.encounter.doc.state.ext.get(plugin_id, {}))
			"scene": return JsonDoc.deep(st.encounter.scene(str(sid)).get("ext", {}).get(plugin_id, {}))
			"token": return JsonDoc.deep(st.find_token(str(sid)).get("ext", {}).get(plugin_id, {}))
		return {"__error": "unknown scope '%s'" % scope}

	func _timed_out() -> Variant:
		var h := _h()
		if h != null and h.over_time_budget():
			return {"__error": "the plugin ran out of time (%d ms in one call)" % h.call_ms_budget}
		return null

	func commit(events: Variant, label: String, reason: Variant) -> Variant:
		var late: Variant = _timed_out()
		if late != null:
			return late
		var p := _p()
		var evs := PluginHost._norm_events(events)
		for ev in evs:
			if str(ev.get("t", "")) == "ext.set" and not p.can("state"):
				return {"__error": "ext.set needs the 'state' capability"}
		var r: Dictionary = PluginHost._as_dict(reason)
		r.by = plugin_id
		var why := _k().commit(evs, label if label != "" else plugin_id, r)
		if why != "":
			return {"__error": why}
		return true

	func note(text: String, audience: String) -> Variant:
		if not _p().can("log"):
			return {"__error": "hm.log needs the 'log' capability"}
		var why := _k().commit([{"t": "log.add", "entry": {"id": JsonDoc.new_id("n"), "kind": "note", "text": text, "audience": audience, "plugin": plugin_id}}], "Note", {"by": plugin_id}, audience)
		return true if why == "" else {"__error": why}

	func setting(key: String) -> Variant:
		return JsonDoc.at_path(_p().settings, str(key))

	## A ruling in the log (kind "ruling"): what was decided, the rule it
	## rests on, the roll that prompted it, tags to find it by. GM audience
	## unless said otherwise; the campaign's journal keeps it.
	func ruling(text: String, opts: Variant) -> Variant:
		if not _p().can("log"):
			return {"__error": "hm.ruling needs the 'log' capability"}
		var o := PluginHost._as_dict(opts)
		var entry := {"id": JsonDoc.new_id("j"), "kind": "ruling", "text": text, "rule": str(o.get("rule", "")), "roll": str(o.get("roll", "")),
			"tags": PluginHost._as_list(o.get("tags", [])), "audience": str(o.get("audience", "gm")), "plugin": plugin_id}
		var why := _k().commit([{"t": "log.add", "entry": entry}], "Ruling", {"by": plugin_id}, entry.audience)
		return entry.id if why == "" else {"__error": why}

	## Bulk.run for the plugin: targets are refs, op is data. Each kind of
	## op needs the capability its single form would.
	const BULK_CAPS := {"effect": "effects", "resource": "resources", "roll": "dice", "action": "actions", "set": "state", "move": "state", "remove": "state"}

	func _bulk_cap_missing(op: Dictionary) -> String:
		var kind := str(op.get("kind", ""))
		var cap := str(BULK_CAPS.get(kind, ""))
		if cap != "" and not _p().can(cap):
			return "hm.bulk '%s' needs the '%s' capability" % [kind, cap]
		for sub in op.get("ops", []):
			var w := _bulk_cap_missing(PluginHost._as_dict(sub))
			if w != "":
				return w
		for outcome in PluginHost._as_dict(op.get("per", {})):
			for sub in PluginHost._as_list(op.per[outcome]):
				var w := _bulk_cap_missing(PluginHost._as_dict(sub))
				if w != "":
					return w
		return ""

	func bulk_run(targets: Variant, op: Variant, label: String) -> Variant:
		var late: Variant = _timed_out()
		if late != null:
			return late
		var spec := PluginHost._as_dict(op)
		var missing := _bulk_cap_missing(spec)
		if missing != "":
			return {"__error": missing}
		var r := Bulk.run(_k(), PluginHost._as_list(targets), spec, label)
		if not r.ok:
			return {"__error": r.why}
		return r.results

	func checkpoint_op(op: String, arg: String) -> Variant:
		if not _p().can("state"):
			return {"__error": "checkpoints need the 'state' capability"}
		match op:
			"mark":
				var id := _k().checkpoint(arg)
				return id if id != "" else {"__error": "could not mark"}
			"list":
				var out := []
				for cp in _k().state.encounter.checkpoints:
					out.append({"id": str(cp.id), "name": str(cp.get("name", "")), "when": str(cp.get("when", ""))})
				return out
			"restore":
				var why := _k().restore_checkpoint(arg)
				return true if why == "" else {"__error": why}
		return {"__error": "unknown checkpoint op '%s'" % op}

	## What the plugin may know about the campaign: its id and the session.
	func campaign_get() -> Dictionary:
		var e := _k().state.encounter
		return {"id": str(e.campaign.get("id", "")), "session": int(e.clock.get("session", 1))}

	func roll(spec: Variant, ctx: Variant, label: String) -> Variant:
		var late: Variant = _timed_out()
		if late != null:
			return late
		var s := PluginHost._as_dict(spec)
		if s.has("faces"):
			s.faces = PluginHost._as_dict(s.faces)
		var k := _k()
		var entry := k.roll(s, PluginHost._as_dict(ctx), label, {"by": plugin_id})
		if entry.is_empty():
			return {"__error": k.last_veto}
		return entry

	func dice_parse(expr: String) -> Dictionary:
		return Dice.parse(str(expr))

	func effects_apply(effect: Variant) -> Variant:
		var fx := PluginHost._norm_effect(effect)
		if str(fx.get("on", "")) == "" or str(fx.get("key", "")) == "":
			return {"__error": "an effect needs 'on' and 'key'"}
		return Effects.apply(_k().state, fx)

	func effects_remove(eid: String) -> Array:
		return Effects.remove(_k().state, str(eid))

	func effects_on(ref: String, key: String) -> Array:
		return JsonDoc.deep(Effects.on(_k().state, str(ref), str(key)))

	func effects_expire(trigger: Variant) -> Array:
		return Effects.expire(_k().state, PluginHost._as_dict(trigger))

	func resource_get(ref: String, name: String) -> Variant:
		var rec := Resources.get_record(_k().state, str(ref), plugin_id, str(name))
		return JsonDoc.deep(rec) if not rec.is_empty() else null

	func resource_op(op: String, ref: String, name: String, a: Variant, b: Variant) -> Variant:
		var st := _k().state
		var ev := {}
		match str(op):
			"spend": ev = Resources.spend(st, ref, plugin_id, name, float(a))
			"gain": ev = Resources.gain(st, ref, plugin_id, name, float(a), bool(b))
			"mark": ev = Resources.mark(st, ref, plugin_id, name, int(a))
			"clear": ev = Resources.clear(st, ref, plugin_id, name, int(a))
			"cross": ev = Resources.cross(st, ref, plugin_id, name, int(a), bool(b))
		return ev if not ev.is_empty() else null

	func resource_refill(kind: String) -> Array:
		return Resources.refill(_k().state, str(kind), plugin_id)

	# --- turns
	func turns_register(public: Variant) -> Variant:
		var spec := PluginHost._as_dict(public)
		var p := _p()
		if bool(spec.get("has_initiative_fn", false)):
			spec.initiative = Callable(self, "turn_initiative")
		if bool(spec.get("has_label_fn", false)):
			spec.order_label = Callable(self, "turn_label")
		spec.erase("has_initiative_fn")
		spec.erase("has_label_fn")
		_k().turns.register(plugin_id, spec)
		p.turn_strategy = spec
		return true

	func turn_initiative(view: Dictionary, token: Dictionary) -> Variant:
		var p := _p()
		if p == null:
			return null
		var c := p.vm.call_function("__turn_initiative", [view, token])
		if c.status != LuaVm.Call.OK:
			_h()._fail(p, "initiative", c.error)
			return null
		return c.value

	func turn_label(view: Dictionary, init: Variant) -> String:
		var p := _p()
		if p == null:
			return str(init)
		var c := p.vm.call_function("__turn_label", [view, init])
		return str(c.value) if c.status == LuaVm.Call.OK else str(init)

	func turns_get() -> Dictionary:
		return JsonDoc.deep(_k().state.encounter.turns)

	func turns_op(op: String, a: String, b: String) -> Variant:
		var why := ""
		var t := _k().turns
		match str(op):
			"set_focus": why = t.set_focus(a, b)
			"request": why = t.request_focus(b, a)
			"deny": why = t.deny_focus(a)
			"start": why = t.start(a, b)
			"next": why = t.next()
			"stop": why = t.stop()
			_: why = "unknown turns op " + op
		return true if why == "" else {"__error": why}

	func turns_consume(ref: String, counter: String, n: Variant) -> Variant:
		var ev := _k().turns.consume_event(str(ref), str(counter), int(n))
		return ev if not ev.is_empty() else null

	# --- tracks
	func track_make(name: String, max_value: Variant, kind: String, advance: Variant, audience: String, on_done: String) -> Dictionary:
		return Tracks.make(plugin_id, str(name), int(max_value), str(kind), PluginHost._as_dict(advance), str(audience), str(on_done))

	func track_advance(id: String, n: Variant) -> Array:
		return Tracks.advance(_k().state, str(id), int(n))

	func track_get(id: String) -> Variant:
		var tr: Dictionary = _k().state.encounter.tracks.get(str(id), {})
		return JsonDoc.deep(tr) if not tr.is_empty() else null

	func track_all() -> Array:
		var out := []
		var ids := _k().state.encounter.tracks.keys()
		ids.sort()
		for id in ids:
			out.append(JsonDoc.deep(_k().state.encounter.tracks[id]))
		return out

	# --- clock and rests
	func clock_get() -> Dictionary:
		return JsonDoc.deep(_k().state.encounter.clock)

	func clock_op(op: String, minutes: Variant, label: String) -> Variant:
		var why := ""
		match str(op):
			"advance": why = _k().clock.advance(float(minutes), str(label) if str(label) != "" else "Time passes")
			"session": why = _k().clock.next_session()
			"scene": why = _k().clock.next_scene()
			_: why = "unknown clock op " + op
		return true if why == "" else {"__error": why}

	func rest(kind: String, label: String) -> Variant:
		var why := _k().rest(str(kind), str(label))
		return true if why == "" else {"__error": why}

	# --- open rolls
	func roll_open(spec: Variant, ctx: Variant, label: String, open_to: Variant, deadline: Variant) -> Variant:
		var id := _k().pending.open_roll(PluginHost._as_dict(spec), PluginHost._as_dict(ctx), plugin_id, str(label), open_to, float(deadline))
		return id if id != "" else {"__error": "could not open the roll"}

	func roll_contribute(id: String, who: String, name: String, expr: String) -> Variant:
		var why := _k().pending.contribute(str(id), str(who), str(name), str(expr))
		return true if why == "" else {"__error": why}

	func roll_resolve(id: String) -> Variant:
		var k := _k()
		var entry := k.pending.resolve(str(id))
		return entry if not entry.is_empty() else {"__error": k.last_veto}

	func roll_pending() -> Array:
		var out := []
		var ids := _k().pending.rolls().keys()
		ids.sort()
		for id in ids:
			out.append(JsonDoc.deep(_k().pending.rolls()[id]))
		return out

	# --- views
	func ui_register(kind: String, schema: Variant) -> Variant:
		var p := _p()
		if p == null:
			return {"__error": "unloaded"}
		if not (schema is Dictionary):
			return {"__error": "a view schema must be an object"}
		if not ["sheet", "status", "gm"].has(str(kind)):
			return {"__error": "unknown view kind '%s' (sheet, status, gm)" % kind}
		p.views[str(kind)] = PluginHost._norm_view(schema)
		return true

	# --- map
	static func _place(v: Variant) -> Variant:
		if v is Array and (v as Array).size() == 2:
			return Vector2(float(v[0]), float(v[1]))
		if v is Dictionary and v.has("x") and v.has("y"):
			return Vector2(float(v.x), float(v.y))
		return v

	func map_bands(table: Variant) -> void:
		_k().map.register_bands(plugin_id, table if table is Array else [])

	func map_distance(scene: String, a: Variant, b: Variant) -> Dictionary:
		var d := _k().map.distance(str(scene), _place(a), _place(b), plugin_id)
		if is_inf(float(d.get("units", 0))):
			d.units = -1
			d.edge = -1
		return d

	func map_within(scene: String, origin: Variant, r: Variant) -> Array:
		return _k().map.within(str(scene), _place(origin), float(r))

	func map_template(scene: String, spec: Variant) -> Dictionary:
		var s := PluginHost._as_dict(spec)
		if s.has("at"):
			s.at = _place(s.at)
		s.plugin = plugin_id
		return _k().map.template(str(scene), s)

	func map_los(scene: String, a: Variant, b: Variant, tokens_block: bool) -> Dictionary:
		return _k().map.line_of_sight(str(scene), _place(a), _place(b), tokens_block)

	func map_light(scene: String, p: Variant) -> Dictionary:
		return _k().map.light_at(str(scene), _place(p))

	func map_can_see(scene: String, viewer: String, target: String) -> Dictionary:
		return _k().map.can_see(str(scene), str(viewer), str(target))

	func map_regions_at(scene: String, cell: Variant) -> Array:
		return JsonDoc.deep(_k().map.regions_at(str(scene), _place(cell)))

	func map_tags_at(scene: String, cell: Variant) -> Array:
		return _k().map.tags_at(str(scene), _place(cell))

	func map_move(scene: String, token: String, to: Variant) -> Dictionary:
		var p: Variant = _place(to)
		if not (p is Vector2):
			return {"events": [], "error": "a destination is {x, y}"}
		return _k().map.move(str(scene), str(token), p)

	func map_cell(scene: String, key: Variant) -> Dictionary:
		return _k().map.cell(str(scene), _place(key))

	func map_cells(op: String, scene: String, a: Variant, b: Variant) -> Array:
		var m := _k().map
		match str(op):
			"neighbors": return m.neighbors(str(scene), _place(a))
			"within": return m.cells_within(str(scene), _place(a), int(b))
			"between": return m.cells_between(str(scene), _place(a), _place(b))
		return []

	func map_token(scene: String, id: String) -> Variant:
		if str(id) == "":
			return JsonDoc.deep(_k().state.tokens(str(scene)))
		var tk := _k().state.token(str(scene), str(id))
		return JsonDoc.deep(tk) if not tk.is_empty() else null

	# --- compendium
	func comp_query(coll: String, opts: Variant) -> Dictionary:
		return _k().comp.query(str(coll), PluginHost._as_dict(opts))

	func comp_get(coll: String, id: String) -> Variant:
		var e := _k().comp.get_entry(str(coll), str(id))
		return e if not e.is_empty() else null

	func comp_collections() -> Array:
		return _k().comp.collections()

	func comp_count(coll: String) -> int:
		return _k().comp.count(str(coll))

	## Into this plugin's homebrew pack, validated against the collection's
	## schema when the plugin declared one.
	func comp_put(coll: String, entry: Variant) -> Variant:
		var p := _p()
		if not p.can("content"):
			return {"__error": "hm.comp.put needs the 'content' capability"}
		var k := _k()
		var pack := k.comp.user_pack(plugin_id + ".homebrew", str(p.manifest.get("name", plugin_id)) + " homebrew", plugin_id)
		var why := k.comp.put(str(coll), PluginHost._as_dict(entry), str(pack.id), p.schemas.get(str(coll)))
		return true if why == "" else {"__error": why}

	func comp_remove(coll: String, id: String) -> Variant:
		var p := _p()
		if not p.can("content"):
			return {"__error": "hm.comp.remove needs the 'content' capability"}
		var why := _k().comp.remove(str(coll), str(id), plugin_id + ".homebrew")
		return true if why == "" else {"__error": why}

	func comp_versions() -> Dictionary:
		return _k().comp.versions(plugin_id)

	func comp_outdated(actor_id: String) -> Dictionary:
		return _k().comp.outdated(_k().state.encounter.actor(str(actor_id)))

	func test_check(cond: bool, msg: String) -> void:
		var h := _h()
		h._test_counts[0] += 1
		if not cond:
			h._test_counts[1] += 1
			h._test_failures.append(msg)

	func test_actor(data: Variant) -> Variant:
		var a := PluginHost._as_dict(data)
		if not a.has("id"):
			a.id = JsonDoc.new_id("a")
		if a.has("ext"):
			a.ext = PluginHost._as_dict(a.ext)
		if not a.has("packs"):
			a.packs = _k().comp.versions(plugin_id)
		var why := _k().commit([{"t": "actor.add", "actor": a}], "Test actor")
		return str(a.id) if why == "" else {"__error": why}

	## A scene on a real map for a plugin test, with tokens placed by cell.
	func test_scene(map_path: String, tokens: Variant) -> Variant:
		var k := _k()
		var m := HexMap.load_file(str(map_path))
		if m == null:
			return {"__error": "no map at " + str(map_path)}
		k.state.attach_map(m)
		var lvl := str(m.levels[0].get("id", "ground")) if not m.levels.is_empty() else "ground"
		var sc := Encounter.new_scene(m, lvl, "Test scene", str(map_path))
		var events := [{"t": "scene.add", "scene": sc}]
		for t in (tokens if tokens is Array else []):
			if not (t is Dictionary):
				continue
			var cell := Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))
			var extra := {"id": str(t.get("id", JsonDoc.new_id("t"))), "actor": str(t.get("actor", "")), "size": int(t.get("size", 1))}
			if t.has("vision"):
				extra.vision = PluginHost._as_dict(t.vision)
			if t.has("light"):
				extra.light = PluginHost._as_dict(t.light)
			if t.has("owner"):
				extra.owner = str(t.owner)
			events.append({"t": "token.add", "scene": sc.id, "token": Encounter.new_token(str(t.get("name", extra.id)), m.grid.cell_center(m.grid.offset_to_axial(cell.x, cell.y)), extra)})
		var why := k.commit(events, "Test scene")
		return str(sc.id) if why == "" else {"__error": why}

	func test_improvise(benchmark: String, params: Variant, scene: String, at: String) -> Variant:
		var k := _k()
		var pos := Vector2.ZERO
		var m := k.state.map_for(str(scene))
		if m != null and str(at) != "":
			pos = m.grid.cell_center(m.key_cell(str(at)))
		var r := Improv.spawn(k, plugin_id, str(benchmark), PluginHost._as_dict(params), str(scene), pos)
		if r.has("error"):
			return {"__error": str(r.error)}
		return str(r.actor)

	func test_dispatch(action: String, ctx: Variant, answers: Variant) -> Variant:
		var pc := _h().dispatch(plugin_id, str(action), PluginHost._as_dict(ctx))
		var list: Array = answers if answers is Array else []
		var i := 0
		while pc.status == PluginCall.PENDING and i < list.size():
			pc.resume(list[i])
			i += 1
		if pc.status == PluginCall.PENDING:
			return {"__error": "the action asked more than the test answered: %s" % [pc.request]}
		if pc.status == PluginCall.ERROR:
			return {"__error": pc.error}
		return pc.value if pc.value != null else true


# -------------------------------------------------------- normalising --

## An empty Lua table arrives as []; where an object is meant, make it {}.
static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


static func _as_list(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary and (v as Dictionary).is_empty():
		return []
	return [v] if v != null else []


const _EVENT_DICT_KEYS := ["changes", "record", "actor", "entry", "overlay", "scene", "token", "player", "patch", "ext", "audience", "derived", "meta"]
const _EFFECT_DICT_KEYS := ["duration", "source"]


static func _norm_events(v: Variant) -> Array:
	var list: Array = []
	if v is Dictionary:
		list = [v]
	elif v is Array:
		list = v
	var out := []
	for ev in list:
		if not (ev is Dictionary):
			continue
		var e: Dictionary = ev
		if str(e.get("t", "")) == "effect.apply":
			e.effect = _norm_effect(e.get("effect"))
		else:
			for k in _EVENT_DICT_KEYS:
				if e.has(k) and e[k] is Array and (e[k] as Array).is_empty():
					e[k] = {}
			if e.has("actor") and e.actor is Dictionary:
				for k in ["ext", "token", "audience", "derived"]:
					if e.actor.has(k) and e.actor[k] is Array and (e.actor[k] as Array).is_empty():
						e.actor[k] = {}
			if e.has("overlay") and e.overlay is Dictionary and e.overlay.get("patch") is Array and (e.overlay.patch as Array).is_empty():
				e.overlay.patch = {}
		if str(e.get("t", "")) == "resource.set" and e.get("record") is Dictionary and e.record.get("crossed") is Dictionary:
			e.record.crossed = []
		out.append(e)
	return out


static func _norm_effect(v: Variant) -> Dictionary:
	var fx := _as_dict(v)
	for k in _EFFECT_DICT_KEYS:
		if fx.has(k) and fx[k] is Array and (fx[k] as Array).is_empty():
			fx[k] = {}
	if fx.get("changes") is Dictionary and (fx.changes as Dictionary).is_empty():
		fx.changes = []
	return fx


## View schemas: children/tabs/actions/fields are lists, an empty intent
## or cost is an object; anything else empty stays a list.
static func _norm_view(v: Variant) -> Variant:
	if v is Array:
		var out := []
		for item in v:
			out.append(_norm_view(item))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			var key := str(k)
			if ["intent", "cost", "values", "submit", "on_tap", "on_mark", "on_clear", "spend", "gain"].has(key) and v[k] is Array and (v[k] as Array).is_empty():
				out[k] = {}
			else:
				out[k] = _norm_view(v[k])
		return out
	return v


const _SCHEMA_LIST_KEYS := ["required", "enum", "prefixItems", "allOf", "anyOf", "oneOf", "type", "examples"]

static func _norm_schema(v: Variant) -> Variant:
	if v is Array:
		if (v as Array).is_empty():
			return {}
		var out := []
		for item in v:
			out.append(_norm_schema(item))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			if _SCHEMA_LIST_KEYS.has(str(k)) and v[k] is Array:
				out[k] = v[k]
			else:
				out[k] = _norm_schema(v[k])
		return out
	return v
