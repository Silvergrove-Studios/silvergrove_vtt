class_name EntryCard
extends RefCounted
## How a compendium entry reads: the card a ruleset registered for the
## collection (`hm.ui.register("entry:spells", …)`, bound to {entry,
## role, me}), or, without one, a generic card — the name, the scalar
## fields on one dim line, the text as rules text. The Compendium pane,
## the lookup popup and the phone's lookups render these read-only.

const SKIP := ["id", "name", "text", "rules", "__pack", "provenance"]


## The schema for a collection's entries: a plugin's card or the generic one.
## `cards` is {collection: {plugin, schema}} — the projection's, or the host's.
static func schema_for(cards: Dictionary, collection: String) -> Dictionary:
	if cards.has(collection) and cards[collection] is Dictionary and (cards[collection] as Dictionary).has("schema"):
		return cards[collection].schema
	return generic()


## The cards a host's plugins registered, in the projection's shape.
static func cards_of(host: PluginHost) -> Dictionary:
	var out := {}
	if host == null:
		return out
	for pid in host.plugins:
		var p: PluginHost.Plugin = host.plugins[pid]
		for kind in p.views:
			if str(kind).begins_with("entry:"):
				out[str(kind).substr(6)] = {"plugin": str(pid), "schema": p.views[kind]}
	return out


static func data_for(entry: Dictionary, role := "gm", me := "") -> Dictionary:
	var e: Dictionary = JsonDoc.deep(entry)
	e.erase("__pack")
	return {"entry": e, "role": role, "me": me, "facts": facts(e)}


## The scalar fields of an entry as "key value" strings, for the generic card.
static func facts(e: Dictionary) -> Array:
	var out := []
	var keys := e.keys()
	keys.sort()
	for k in keys:
		if SKIP.has(str(k)):
			continue
		var v: Variant = e[k]
		if v is Dictionary or v == null:
			continue
		if v is Array:
			if (v as Array).is_empty() or not (v as Array).all(func(x: Variant) -> bool: return not (x is Dictionary or x is Array)):
				continue
			v = ", ".join((v as Array).map(func(x: Variant) -> String: return str(x)))
		if v is bool:
			if not v:
				continue
			out.append(str(k).replace("_", " "))
			continue
		if str(v) == "":
			continue
		out.append("%s %s" % [str(k).replace("_", " "), str(v)])
	return out


static func generic() -> Dictionary:
	return {"type": "column", "children": [
		{"type": "text", "bind": "/entry/name", "style": "header"},
		{"type": "text", "expr": "join(@facts, ' · ')", "style": "dim", "if": "len(@facts) > 0"},
		{"type": "text", "bind": "/entry/text", "rich": true, "if": "(@entry.text ?? '') != ''"},
	]}
