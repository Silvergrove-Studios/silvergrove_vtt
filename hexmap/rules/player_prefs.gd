class_name PlayerPrefs
extends RefCounted
## Each player's own choices of how the table treats them — whose dice
## roll for them, which cards they are asked — within what the DM allows.
## A ruleset declares its preferences beside its settings (the manifest's
## `preferences`: a JSON schema's properties, and defaults); each says with
## `x-when` which of the ruleset's settings must hold for players to be
## offered it (the DM's "each player chooses"). A player's choices live on
## their record in the encounter's `players`, under `prefs` by plugin id
## (`{"srd5e": {"dice": "typed"}}`), and go into the campaign with the rest
## of the player. A player sets their own from their screen (HostSession's
## `prefs` intent); the DM sees and changes anyone's in Table settings. A
## plugin reads one with `hm.players.pref(player, key)`: the player's choice
## while it is offered, else the declared default (docs/plugin-authoring.md).

## The types a preference may have (what a screen can show).
const TYPES := ["string", "boolean", "integer", "number"]


## A manifest's preferences ({} when it declares none).
static func properties_of(manifest: Dictionary) -> Dictionary:
	var prefs: Variant = manifest.get("preferences", {})
	var schema: Variant = prefs.get("schema", {}) if prefs is Dictionary else {}
	var props: Variant = schema.get("properties", {}) if schema is Dictionary else {}
	return props if props is Dictionary else {}


## A manifest's preferences' defaults.
static func defaults_of(manifest: Dictionary) -> Dictionary:
	var prefs: Variant = manifest.get("preferences", {})
	var d: Variant = prefs.get("defaults", {}) if prefs is Dictionary else {}
	return d if d is Dictionary else {}


## A preference's default: the manifest's `defaults`, else its schema's.
static func default_of(manifest: Dictionary, key: String) -> Variant:
	var defaults := defaults_of(manifest)
	if defaults.has(key):
		return JsonDoc.deep(defaults[key])
	var d: Variant = properties_of(manifest).get(key)
	return JsonDoc.deep(d.get("default")) if d is Dictionary else null


## Whether players are offered a preference under these settings: every
## setting its `x-when` names holds one of the values it gives (one, or a
## list of them). A preference with no `x-when` is always offered.
static func offered(d: Dictionary, settings: Dictionary) -> bool:
	var cond: Variant = d.get("x-when", {})
	if not (cond is Dictionary):
		return true
	for k in cond:
		var have: Variant = JsonDoc.at_path(settings, str(k)) if str(k).contains("/") else settings.get(str(k))
		var ok := false
		for w in (cond[k] if cond[k] is Array else [cond[k]]):
			if JsonDoc.same(w, have) or str(w) == str(have):
				ok = true
		if not ok:
			return false
	return true


## A player's stored choices for a plugin ({} for none).
static func stored(e: Encounter, pid: String, plugin: String) -> Dictionary:
	if e == null or pid == "":
		return {}
	var all: Variant = e.player(pid).get("prefs", {})
	if not (all is Dictionary):
		return {}
	var mine: Variant = (all as Dictionary).get(plugin, {})
	return mine if mine is Dictionary else {}


## The value in force for a player: their choice while the preference is
## offered (and fits its schema), else its default. null for a preference
## the plugin doesn't declare.
static func value(e: Encounter, manifest: Dictionary, settings: Dictionary, plugin: String, pid: String, key: String) -> Variant:
	var props := properties_of(manifest)
	if not (props.get(key) is Dictionary):
		return null
	var d: Dictionary = props[key]
	if pid != "" and offered(d, settings):
		var mine := stored(e, pid, plugin)
		if mine.has(key):
			var r := check(d, mine[key])
			if str(r[0]) == "":
				return r[1]
	return default_of(manifest, key)


## A value as a preference's schema allows it: ["", the value made right
## (a whole number an int)] or [why not, null].
static func check(d: Dictionary, v: Variant) -> Array:
	var title := str(d.get("title", "That"))
	match str(d.get("type", "")):
		"boolean":
			if not (v is bool):
				return ["%s: on or off" % title, null]
		"integer", "number":
			if not (v is float or v is int):
				return ["%s: a number" % title, null]
			if str(d.type) == "integer":
				if float(v) != floorf(float(v)):
					return ["%s: a whole number" % title, null]
				v = int(v)
			if d.has("minimum") and float(v) < float(d.minimum):
				return ["%s: at least %s" % [title, str(d.minimum)], null]
			if d.has("maximum") and float(v) > float(d.maximum):
				return ["%s: at most %s" % [title, str(d.maximum)], null]
		"string":
			if not (v is String):
				return ["%s: words" % title, null]
		_:
			return ["%s: not a preference a screen can show" % title, null]
	if d.get("enum") is Array:
		var found := false
		for c in d.enum:
			if JsonDoc.same(c, v):
				found = true
		if not found:
			return ["%s: not one of the choices" % title, null]
	return ["", v]


## Every loaded plugin's preferences as the screens draw them, each with
## whether players are offered it now and, when it's the DM's to allow, the
## settings that would: [{id ("<plugin>/<key>"), plugin, plugin_name, key,
## title, description, type, enum, labels, minimum, maximum, default,
## offered, when: [{key, title, value}]}].
static func items(host: PluginHost) -> Array:
	var out := []
	if host == null:
		return out
	var ids := host.plugins.keys()
	ids.sort()
	for pid in ids:
		var p: PluginHost.Plugin = host.plugins[pid]
		var props := properties_of(p.manifest)
		var setting_props: Variant = p.manifest.get("settings", {}).get("schema", {}).get("properties", {}) if p.manifest.get("settings") is Dictionary and p.manifest.settings.get("schema") is Dictionary else {}
		for key in props:
			var d: Variant = props[key]
			if not (d is Dictionary) or not TYPES.has(str(d.get("type", ""))):
				continue
			var it := {"id": "%s/%s" % [pid, key], "plugin": str(pid), "plugin_name": str(p.manifest.get("name", pid)), "key": str(key),
				"title": str(d.get("title", key)), "description": str(d.get("description", "")), "type": str(d.type),
				"default": default_of(p.manifest, str(key)), "offered": offered(d, p.settings), "when": []}
			if d.get("enum") is Array:
				it.enum = JsonDoc.deep(d.enum)
				it.labels = JsonDoc.deep(d.enumNames) if d.get("enumNames") is Array and (d.enumNames as Array).size() == (d.enum as Array).size() else (d.enum as Array).map(func(x: Variant) -> String: return str(x))
			for bound in ["minimum", "maximum"]:
				if d.has(bound):
					it[bound] = d[bound]
			# the settings that offer it, in words, for the DM ("Players' dice: Each player chooses")
			var cond: Variant = d.get("x-when", {})
			if cond is Dictionary:
				for k in cond:
					var sd: Variant = setting_props.get(str(k), {}) if setting_props is Dictionary else {}
					var want: Variant = cond[k][0] if cond[k] is Array and not (cond[k] as Array).is_empty() else cond[k]
					var words := str(want)
					if sd is Dictionary and sd.get("enum") is Array and sd.get("enumNames") is Array:
						var i := (sd.enum as Array).find(want)
						if i >= 0 and i < (sd.enumNames as Array).size():
							# (its label's head: "Each player chooses", not what follows it in brackets)
							words = str(sd.enumNames[i]).get_slice(" (", 0).get_slice(":", 0)
					elif want is bool:
						words = "On" if want else "Off"
					it.when.append({"key": str(k), "title": str(sd.get("title", k)) if sd is Dictionary else str(k), "value": words})
			out.append(it)
	return out


## Each player's preferences as the DM's Table settings lists them:
## [{id, name, values: {"<plugin>/<key>": value in force}, own: {"<plugin>/<key>": true}}]
## (`own`: what the player chose themselves, rather than the default).
static func players(e: Encounter, host: PluginHost) -> Array:
	var out := []
	if e == null or host == null:
		return out
	for p in e.players:
		var pid := str(p.get("id", ""))
		var row := {"id": pid, "name": str(p.get("name", pid)), "values": {}, "own": {}}
		for plugin in host.plugins:
			var pl: PluginHost.Plugin = host.plugins[plugin]
			var mine := stored(e, pid, str(plugin))
			for key in properties_of(pl.manifest):
				var id := "%s/%s" % [plugin, key]
				row.values[id] = value(e, pl.manifest, pl.settings, str(plugin), pid, str(key))
				if mine.has(key):
					row.own[id] = true
		out.append(row)
	return out


## Change a player's preference: checked against its schema (and, for a
## player changing their own, against what the DM allows now), then made
## one step by `commit` — (events: Array, label: String, reason: Dictionary)
## -> String, the Table's own (one step of its undo, sent to every screen
## as a `player.set`). `by` is the player who asked, or "" for the DM. ""
## or why not.
static func change(e: Encounter, host: PluginHost, pid: String, plugin: String, key: String, v: Variant, by: String, commit: Callable) -> String:
	if e == null or e.player(pid).is_empty():
		return "no such player"
	if by != "" and by != pid:
		return "your own preferences only"
	if host == null or not host.plugins.has(plugin):
		return "no ruleset '%s' here" % plugin
	var pl: PluginHost.Plugin = host.plugins[plugin]
	var props := properties_of(pl.manifest)
	if not (props.get(key) is Dictionary):
		return "'%s' has no preference '%s'" % [plugin, key]
	var d: Dictionary = props[key]
	var r := check(d, v)
	if str(r[0]) != "":
		return str(r[0])
	if by != "" and not offered(d, pl.settings):
		return "%s is the DM's to choose at this table" % str(d.get("title", key))
	var all: Dictionary = JsonDoc.deep(e.player(pid).get("prefs", {})) if e.player(pid).get("prefs") is Dictionary else {}
	var mine: Dictionary = all.get(plugin, {}) if all.get(plugin) is Dictionary else {}
	if mine.has(key) and JsonDoc.same(mine[key], r[1]):
		return ""
	mine[key] = r[1]
	all[plugin] = mine
	var who := str(e.player(pid).get("name", pid))
	return str(commit.call([{"t": "player.set", "id": pid, "changes": {"prefs": all}}], "%s: %s" % [who, str(d.get("title", key))], {"by": by if by != "" else "gm"}))


## What is wrong with a manifest's preferences, as sentences ([] when
## nothing is): a type no screen shows, an `x-when` naming a setting the
## plugin doesn't have, a default its schema refuses.
static func check_manifest(manifest: Dictionary) -> Array:
	var out := []
	var props := properties_of(manifest)
	var settings: Variant = manifest.get("settings", {}).get("schema", {}).get("properties", {}) if manifest.get("settings") is Dictionary and manifest.settings.get("schema") is Dictionary else {}
	for key in props:
		var d: Variant = props[key]
		if not (d is Dictionary) or not TYPES.has(str(d.get("type", ""))):
			out.append("preference '%s': a type a screen shows (%s)" % [key, ", ".join(PackedStringArray(TYPES))])
			continue
		var cond: Variant = d.get("x-when", {})
		if not (cond is Dictionary):
			out.append("preference '%s': x-when is an object of setting → value" % key)
		else:
			for k in cond:
				if not (settings is Dictionary) or not (settings as Dictionary).has(str(k)):
					out.append("preference '%s': x-when names '%s', which is no setting of this plugin" % [key, str(k)])
		var dflt: Variant = default_of(manifest, str(key))
		if dflt == null:
			out.append("preference '%s': no default" % key)
		elif str(check(d, dflt)[0]) != "":
			out.append("preference '%s': its default: %s" % [key, str(check(d, dflt)[0])])
	return out
