class_name Views
extends RefCounted
## What a client is shown: the projection of the encounter's rules data
## for one audience, as plain data plus the view schemas plugins
## registered. Players never receive the rules blocks themselves; they
## receive this. The same projection, with the GM audience, feeds the
## Table's own panels.
##
## Audience strings on records and log entries: "all", "gm", "owner:<pid>",
## "players:<pid>,<pid>" (the players named, and the GM), "private:<pid>,<pid>"
## (the players named, not the GM: what players say among themselves).
## An actor's `audience.fields` maps field paths (within ext or derived,
## "ext/x/secret") to "gm" | "owner" | "all"; fields not listed are "all"
## for player characters and "gm" for everything else.

const ROLE_PLAYER := "player"
const ROLE_DISPLAY := "display"
const ROLE_GM := "gm"
## The DM's own web screen, on the Table's machine: the GM's audience.
const ROLE_DM := "dm"
## A co-GM client: projected with ROLE_GM, joins with the table's code.
const ROLE_COGM := "cogm"


## May `player_id` with `role` see something whose audience is `audience`?
static func can_see(audience: String, player_id: String, role: String) -> bool:
	# what players say among themselves, and not to the DM, is theirs
	if audience.begins_with("private:"):
		return role == ROLE_PLAYER and audience.substr(8).split(",").has(player_id)
	if role == ROLE_GM:
		return true
	match audience:
		"", "all": return true
		"gm": return false
	if audience.begins_with("owner:"):
		return role == ROLE_PLAYER and audience.substr(6) == player_id
	if audience.begins_with("players:"):
		return role == ROLE_PLAYER and audience.substr(8).split(",").has(player_id)
	if audience.begins_with("private:"):
		return role == ROLE_PLAYER and audience.substr(8).split(",").has(player_id)
	return false


## The projection for one client. `host` may be null (no plugins loaded).
static func project(kernel: RulesKernel, host: PluginHost, player_id: String, role := ROLE_PLAYER) -> Dictionary:
	var st := kernel.state
	var e := st.encounter
	var out := {"player": player_id, "role": role, "seq": kernel.log.seq, "turns": JsonDoc.deep(e.turns), "clock": JsonDoc.deep(e.clock),
		"actors": {}, "status": [], "tracks": [], "prompts": [], "rolls": [], "log": [], "actions": {}, "plugins": [], "cards": {}}
	var plugin_ids := []
	if host != null:
		plugin_ids = host.plugins.keys()
		plugin_ids.sort()
		for pid in plugin_ids:
			var p: PluginHost.Plugin = host.plugins[pid]
			out.plugins.append({"id": pid, "name": str(p.manifest.get("name", pid)), "version": str(p.manifest.get("version", ""))})
			# the cards entries read as (entry:<collection> views), so a device can show what it looks up
			for kind in p.views:
				if str(kind).begins_with("entry:"):
					out.cards[str(kind).substr(6)] = {"plugin": pid, "schema": p.views[kind]}
			out.actions[pid] = JsonDoc.deep(p.actions)
	# actors
	var ids := e.actors.keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = e.actors[aid]
		var mine := role == ROLE_PLAYER and str(a.get("owner", "")) == player_id and player_id != ""
		var visible := role == ROLE_GM or mine or str(a.get("kind", "")) == "pc" or str(a.get("audience", {}).get("visible", "")) == "all"
		if not visible:
			continue
		var pa := {"id": str(aid), "name": str(a.get("name", "")), "kind": str(a.get("kind", "")), "owner": str(a.get("owner", "")), "mine": mine, "sheets": [],
			"ext": _fields(a, "ext", mine, role), "derived": _fields(a, "derived", mine, role),
			"packs": JsonDoc.deep(a.get("packs", {})) if (mine or role == ROLE_GM) else {}, "token": JsonDoc.deep(a.get("token", {})),
			"outdated": kernel.comp.outdated(a) if (mine or role == ROLE_GM) else {}}
		var effects := []
		for fx in kernel.effects_on_actor(str(aid)):
			if can_see(str(fx.get("audience", "all")), player_id, role):
				effects.append(JsonDoc.deep(fx))
		pa.effects = effects
		pa.resources = _resources(kernel, str(aid))
		pa.tokens = []
		for sc in e.scenes:
			for tk in sc.tokens:
				if str(tk.get("actor", "")) == str(aid) and (role == ROLE_GM or not bool(tk.get("hidden", false))):
					pa.tokens.append({"id": str(tk.id), "scene": str(sc.id), "name": str(tk.get("name", ""))})
		if host != null and (mine or role == ROLE_GM):
			for pid in plugin_ids:
				var p: PluginHost.Plugin = host.plugins[pid]
				# a ruleset's sheet is for the actors that carry its data
				if p.views.has("sheet") and a.get("ext", {}).has(pid):
					pa.sheets.append({"plugin": pid, "schema": p.views["sheet"], "data": sheet_data(kernel, pa, pid, player_id, role)})
		out.actors[str(aid)] = pa
	# tracks, prompts, rolls, log
	var tids := e.tracks.keys()
	tids.sort()
	for tid in tids:
		var tr: Dictionary = e.tracks[tid]
		if can_see(str(tr.get("audience", "all")), player_id, role):
			out.tracks.append(JsonDoc.deep(tr))
	var pids: Array = e.pending.prompts.keys()
	pids.sort()
	for pr in pids:
		var rec: Dictionary = e.pending.prompts[pr]
		if role == ROLE_GM or (role == ROLE_PLAYER and str(rec.get("to", "")) == player_id):
			out.prompts.append(JsonDoc.deep(rec))
	var rids: Array = e.pending.rolls.keys()
	rids.sort()
	for rr in rids:
		var rec: Dictionary = e.pending.rolls[rr]
		var open_to: Variant = rec.get("open_to", "all")
		if role == ROLE_GM or (open_to is String and str(open_to) == "all") or (open_to is Array and (open_to as Array).has(player_id)):
			out.rolls.append(JsonDoc.deep(rec))
	for entry in e.log:
		if can_see(str(entry.get("audience", "all")), player_id, role):
			out.log.append(JsonDoc.deep(entry))
	# status views
	if host != null:
		for pid in plugin_ids:
			var p: PluginHost.Plugin = host.plugins[pid]
			if p.views.has("status"):
				out.status.append({"plugin": pid, "schema": p.views["status"], "data": status_data(kernel, out, pid, player_id, role)})
	return out


## The data a plugin's sheet schema binds to, for one projected actor.
static func sheet_data(kernel: RulesKernel, pa: Dictionary, plugin: String, player_id: String, role: String) -> Dictionary:
	var res := {}
	for name in pa.get("resources", {}).get(plugin, {}):
		res[name] = pa.resources[plugin][name]
	var effects := []
	for fx in pa.get("effects", []):
		if str(fx.get("plugin", plugin)) == plugin:
			effects.append(fx)
	return {"me": player_id, "role": role, "actor": {"id": pa.id, "name": pa.name, "owner": pa.owner, "kind": pa.kind, "mine": pa.mine},
		"ext": JsonDoc.deep(pa.get("ext", {}).get(plugin, {})), "derived": JsonDoc.deep(pa.get("derived", {}).get(plugin, {})),
		"resources": res, "effects": effects, "tokens": pa.get("tokens", []),
		"turns": JsonDoc.deep(kernel.state.encounter.turns), "clock": JsonDoc.deep(kernel.state.encounter.clock),
		"state": JsonDoc.deep(kernel.state.encounter.doc.state.ext.get(plugin, {}))}


## The data a plugin's status schema binds to.
static func status_data(kernel: RulesKernel, projection: Dictionary, plugin: String, player_id: String, role: String) -> Dictionary:
	var actors := []
	var mine := []
	for aid in projection.actors:
		var pa: Dictionary = projection.actors[aid]
		actors.append({"id": pa.id, "name": pa.name, "owner": pa.owner, "mine": pa.mine, "kind": pa.kind,
			"derived": pa.get("derived", {}).get(plugin, {}), "resources": pa.get("resources", {}).get(plugin, {}), "effects": pa.get("effects", [])})
		if pa.mine:
			mine.append(pa.id)
	var tracks := []
	for tr in projection.tracks:
		if str(tr.get("plugin", plugin)) == plugin:
			tracks.append(tr)
	# `mine`: this player's own actors (a status view offers a new
	# character only to a player without one)
	return {"me": player_id, "mine": mine, "role": role, "turns": projection.turns, "clock": projection.clock, "actors": actors, "tracks": tracks,
		"prompts": projection.prompts, "rolls": projection.rolls, "log": projection.log, "scene": str(kernel.state.encounter.active_scene_id),
		"state": JsonDoc.deep(kernel.state.encounter.doc.state.ext.get(plugin, {}))}


## An actor's ext or derived block with the fields this audience may not
## see removed. Player characters are public but for what `audience.fields`
## hides; other actors are GM-only but for what it opens.
static func _fields(a: Dictionary, block: String, mine: bool, role: String) -> Dictionary:
	var src: Dictionary = a.get(block, {})
	if role == ROLE_GM or mine:
		return JsonDoc.deep(src)
	var rules: Dictionary = a.get("audience", {}).get("fields", {})
	var public := str(a.get("kind", "")) == "pc"
	var out: Dictionary = JsonDoc.deep(src) if public else {}
	for path in rules:
		var p := str(path)
		if not p.begins_with(block + "/"):
			continue
		var rel := p.substr(block.length() + 1)
		var who := str(rules[path])
		if public and who != "all":
			JsonDoc.set_at_path(out, rel, null)
		elif not public and who == "all":
			var v: Variant = JsonDoc.at_path(src, rel)
			if v != null:
				JsonDoc.set_at_path(out, rel, v)
	return out


static func _resources(kernel: RulesKernel, actor_id: String) -> Dictionary:
	var res: Dictionary = JsonDoc.deep(kernel.state.encounter.resources.get("actor:" + actor_id, {}))
	for sc in kernel.state.encounter.scenes:
		for tk in sc.tokens:
			if str(tk.get("actor", "")) == actor_id:
				var tres: Dictionary = kernel.state.encounter.resources.get("token:" + str(tk.id), {})
				for pid in tres:
					if not res.has(pid):
						res[pid] = {}
					for n in tres[pid]:
						res[pid][n] = JsonDoc.deep(tres[pid][n])
	return res
