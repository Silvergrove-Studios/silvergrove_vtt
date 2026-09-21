class_name Improv
extends RefCounted
## Improvisation (G4): "give me a level-4 brute right now". A ruleset
## registers *benchmarks* — `hm.improv.register(name, {label, params,
## make})` — a form of parameters (a JSON-schema `properties` table:
## level, role, …) and a function from them to an actor's data. The
## Table's Improvise dialog renders the form, the plugin makes the actor,
## the kernel adds it with a token where the DM pointed. Beside that: a
## name generator, and number-only tokens for the fight nobody planned —
## an actor under the `table` pseudo-plugin whose numbers are pools, so
## bulk damage and the inspector work on it without any ruleset.

const TABLE_PLUGIN := "table"


## Make an actor from a plugin's benchmark and put it on a scene.
## {actor, token} or {error}. `opts` may carry name, owner, hidden, color,
## size, art, kind.
static func spawn(kernel: RulesKernel, plugin: String, benchmark: String, params: Dictionary, scene_id: String, pos: Vector2, opts: Dictionary = {}) -> Dictionary:
	var host: PluginHost = kernel.plugin_host.get_ref() if kernel.plugin_host != null else null
	if host == null:
		return {"error": "no plugins here"}
	var pc := host.improvise(plugin, benchmark, params)
	if pc.status != PluginHost.PluginCall.OK:
		return {"error": pc.error if pc.error != "" else "the benchmark did not finish"}
	if not (pc.value is Dictionary):
		return {"error": "%s/%s returned %s, not an actor" % [plugin, benchmark, type_string(typeof(pc.value))]}
	var made: Dictionary = pc.value
	var actor := {"id": JsonDoc.new_id("a"), "kind": str(opts.get("kind", made.get("kind", "npc"))), "name": str(opts.get("name", made.get("name", ""))),
		"ext": {}, "token": JsonDoc.deep(made.get("token", {}))}
	if actor.name == "":
		actor.name = generate_name(int(params.get("seed", hash(str(params)) & 0x7fffffff)))
	if made.get("ext") is Dictionary:
		# either the plugin's own block, or a whole ext table keyed by plugin
		var ext: Dictionary = made.ext
		actor.ext = JsonDoc.deep(ext) if ext.has(plugin) else {plugin: JsonDoc.deep(ext)}
	if opts.has("owner") and str(opts.owner) != "":
		actor.owner = str(opts.owner)
	actor.improvised = {"plugin": plugin, "benchmark": benchmark, "params": JsonDoc.deep(params)}
	return place(kernel, actor, scene_id, pos, opts, made.get("resources", {}) if made.get("resources") is Dictionary else {})


## A number-only actor: {hp: 12, ac: 15} become pools under the `table`
## pseudo-plugin (current = max), shown by the inspector and spent by
## bulk ops like any pool. {actor, token} or {error}.
static func quick(kernel: RulesKernel, p_name: String, numbers: Dictionary, scene_id: String, pos: Vector2, opts: Dictionary = {}) -> Dictionary:
	var actor := {"id": JsonDoc.new_id("a"), "kind": str(opts.get("kind", "npc")), "name": p_name if p_name != "" else generate_name(int(hash(str(numbers)) & 0x7fffffff)),
		"ext": {TABLE_PLUGIN: {"numbers": JsonDoc.deep(numbers)}}, "token": {}}
	var resources := {}
	for k in numbers:
		if numbers[k] is float or numbers[k] is int:
			resources[str(k)] = Resources.pool(float(numbers[k]), float(numbers[k]), "manual")
	return place(kernel, actor, scene_id, pos, opts, {TABLE_PLUGIN: resources})


## Add an actor and a token for it as one step. `resources` is
## plugin -> name -> record to set on the actor.
static func place(kernel: RulesKernel, actor: Dictionary, scene_id: String, pos: Vector2, opts: Dictionary = {}, resources: Dictionary = {}) -> Dictionary:
	var st := kernel.state
	if st.encounter.scene(scene_id).is_empty():
		return {"error": "no scene '%s'" % scene_id}
	var extra := {"actor": str(actor.id), "hidden": bool(opts.get("hidden", false))}
	var td: Dictionary = actor.get("token", {})
	for k in ["color", "size", "art", "vision", "label"]:
		if opts.has(k):
			extra[k] = opts[k]
		elif td.has(k):
			extra[k] = td[k]
	if opts.has("owner") and str(opts.owner) != "":
		extra.owner = str(opts.owner)
	var m := st.map_for(scene_id)
	var at := pos
	if m != null and bool(opts.get("snap", true)):
		at = m.grid.snap_to_center(pos)
	var tk := Encounter.new_token(str(actor.name), at, extra)
	var events := [{"t": "actor.add", "actor": actor}]
	for pid in resources:
		for n in resources[pid]:
			events.append(Resources.set_event("actor:" + str(actor.id), str(pid), str(n), resources[pid][n]))
	events.append({"t": "token.add", "scene": scene_id, "token": tk})
	var why := kernel.commit(events, "Improvise %s" % str(actor.name), {"by": "gm"})
	if why != "":
		return {"error": why}
	return {"actor": str(actor.id), "token": str(tk.id)}


## The benchmarks every loaded plugin offers: [{plugin, name, label, params}].
static func benchmarks(host: PluginHost) -> Array:
	var out := []
	if host == null:
		return out
	var ids := host.plugins.keys()
	ids.sort()
	for pid in ids:
		var p: PluginHost.Plugin = host.plugins[pid]
		var names := p.improv.keys()
		names.sort()
		for n in names:
			var spec: Dictionary = p.improv[n]
			out.append({"plugin": str(pid), "name": str(n), "label": str(spec.get("label", n)), "params": spec.get("params", {}) if spec.get("params") is Dictionary else {}})
	return out


# ------------------------------------------------------------- names --

const _ONSETS := ["b", "br", "d", "dr", "f", "g", "gr", "h", "k", "kr", "l", "m", "n", "p", "r", "s", "sk", "t", "th", "v", "z", ""]
const _VOWELS := ["a", "e", "i", "o", "u", "ae", "ia", "ei", "ou"]
const _CODAS := ["", "", "n", "r", "l", "s", "k", "th", "m", "nd", "rk", "sh"]


## A pronounceable name, the same for the same seed.
static func generate_name(seed: int, syllables := 0) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := syllables if syllables > 0 else rng.randi_range(2, 3)
	var s := ""
	for i in n:
		s += _ONSETS[rng.randi_range(0, _ONSETS.size() - 1)] + _VOWELS[rng.randi_range(0, _VOWELS.size() - 1)]
		if i == n - 1 or rng.randf() < 0.4:
			s += _CODAS[rng.randi_range(0, _CODAS.size() - 1)]
	return s.capitalize()
